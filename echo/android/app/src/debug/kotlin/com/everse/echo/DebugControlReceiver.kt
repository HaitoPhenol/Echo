package com.everse.echo

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.os.Handler
import android.os.Looper
import android.util.Log
import io.flutter.plugin.common.MethodChannel
import org.json.JSONObject
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit

/// debug 包专属 ECP 广播入口（设计 §7）。
///
/// action `com.everse.echo.CTRL`，参数：
/// - `--es cmd`：命令全名（如 sys.ping）；
/// - `--es args`：JSON 对象字符串（可选）；
/// - `--ez confirm`：3 级命令的显式确认（可选）；
/// - `--es nonce`：逐请求回响，便于脚本在 logcat 匹配。
///
/// 结果经 `setResultData(JSON 信封)` 原样回传（`am broadcast`
/// 需在 shell uid 下读取 result-data）；同时打到 logcat（tag
/// EchoCtrl）。接收器本身不做任何鉴权/业务判断。
///
/// 不声明任何 permission：shell uid（adb）即受信边界；release 包
/// 物理不注册本接收器（仅 debug manifest）。
class DebugControlReceiver : BroadcastReceiver() {

    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action != ACTION) return

        val cmd = intent.getStringExtra(EXTRA_CMD)
        if (cmd.isNullOrEmpty()) {
            finishWith(goAsync(), errorEnvelope(null, "USAGE", "缺少 --es cmd"))
            return
        }
        val pending = goAsync()
        workerThread {
            try {
                val app = context.applicationContext as? DebugEchoApp
                val engine = app?.engine
                if (engine == null) {
                    // 冷启动竞态：脚本已先 am start 等首帧；仍未就绪
                    // 时按 CONFLICT（4）回报，调用方重试即可。
                    finishWith(
                        pending,
                        errorEnvelope(cmd, "CONFLICT", "Flutter 引擎尚未就绪，请稍后重试"),
                    )
                    return@workerThread
                }

                val arguments = HashMap<String, Any?>().apply {
                    put("cmd", cmd)
                    intent.getStringExtra(EXTRA_ARGS)?.takeIf { it.isNotEmpty() }
                        ?.let { put("args", it) }
                    if (intent.getBooleanExtra(EXTRA_CONFIRM, false)) {
                        put("confirmed", true)
                    }
                    intent.getStringExtra(EXTRA_NONCE)?.let { put("nonce", it) }
                }

                val latch = CountDownLatch(1)
                val reply = arrayOfNulls<String>(1)
                Handler(Looper.getMainLooper()).post {
                    // MethodChannel 调用必须在平台主线程发起。
                    MethodChannel(engine.dartExecutor.binaryMessenger, CHANNEL)
                        .invokeMethod("exec", arguments, object : MethodChannel.Result {
                            override fun success(result: Any?) {
                                reply[0] = (result as? String) ?: JSONObject()
                                    .put("ok", false)
                                    .put("cmd", cmd)
                                    .put("error", JSONObject()
                                        .put("code", "BUSINESS")
                                        .put("message", "Dart 回包不是字符串"))
                                    .toString()
                                latch.countDown()
                            }

                            override fun error(
                                errorCode: String,
                                errorMessage: String?,
                                errorDetails: Any?,
                            ) {
                                reply[0] = errorEnvelope(
                                    cmd,
                                    errorCode,
                                    errorMessage ?: "通道错误",
                                )
                                Log.w(TAG, "exec 通道错误: $errorCode $errorMessage")
                                latch.countDown()
                            }

                            override fun notImplemented() {
                                reply[0] = errorEnvelope(
                                    cmd,
                                    "UNKNOWN_COMMAND",
                                    "echo/control 未挂载（请确认是 debug 包）",
                                )
                                latch.countDown()
                            }
                        })
                }

                // goAsync 的系统预算约 10s；通道（总线）侧最长 60s，
                // 超长导出等命令应在 10s 内回包，否则按超时报告。
                val answered = latch.await(RECEIVER_BUDGET_SECONDS, TimeUnit.SECONDS)
                finishWith(
                    pending,
                    reply[0]
                        ?: errorEnvelope(cmd, "TIMEOUT", "接收器等待回包超时"),
                    logged = answered,
                )
            } catch (t: Throwable) {
                Log.e(TAG, "ECP 广播处理失败", t)
                finishWith(pending, errorEnvelope(cmd, "BUSINESS", t.toString()))
            }
        }
    }

    private fun workerThread(block: () -> Unit) {
        // goAsync 后可在非主线程工作；finish 必须在预算内调用。
        Thread(block, "echo-ctrl").start()
    }

    private fun finishWith(
        pending: PendingResult,
        json: String,
        logged: Boolean = true,
    ) {
        if (logged) Log.i(TAG, "result: $json")
        pending.resultData = json
        pending.finish()
    }

    private fun errorEnvelope(cmd: String?, code: String, message: String): String {
        val error = JSONObject()
            .put("code", code)
            .put("message", message)
        return JSONObject()
            .put("ok", false)
            .put("cmd", cmd ?: JSONObject.NULL)
            .put("ms", 0)
            .put("error", error)
            .toString()
    }

    companion object {
        const val ACTION = "com.everse.echo.CTRL"
        const val CHANNEL = "echo/control"
        const val EXTRA_CMD = "cmd"
        const val EXTRA_ARGS = "args"
        const val EXTRA_CONFIRM = "confirm"
        const val EXTRA_NONCE = "nonce"

        private const val TAG = "EchoCtrl"

        /// goAsync 预算取保守值：略小于系统 10s 广播窗口。
        private const val RECEIVER_BUDGET_SECONDS = 9L
    }
}
