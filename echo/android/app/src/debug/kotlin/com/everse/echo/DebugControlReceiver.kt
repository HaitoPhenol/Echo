package com.everse.echo

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.os.Binder
import android.os.Build
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
/// EchoCtrl）。接收器本身不做任何业务鉴权（命令级鉴权在总线）。
///
/// 发送方信任边界是**调用方 uid**（root=0 / shell=2000，即 adb），
/// 而**不是**包的 debuggable 标志——第三方 App 同样可装在 debug
/// 包里，debuggable 不构成任何信任。门禁分两层：
///  1. 清单 `android:permission="android.permission.DUMP"`（主门禁）：
///     AMS 派发前用发送方真实 uid 校验，普通三方 App 拿不到 DUMP，
///     未持有者的广播根本不会进入这里（等效静默丢弃）；
///  2. API 34+ 可用 [getSentFromUid] 在进程内按 0/2000 白名单二次
///     确认（[isCallerTrusted]），取不到身份时按不信任处理。
/// 注意：onReceive 经 ActivityThread 消息派发，已离开 binder 事务，
/// 此时 Binder.getCallingUid() 恒为本 App uid（MIX 2S/Android10 实测
/// 10378），不能作为发送方判据。release 包物理不注册本接收器。
class DebugControlReceiver : BroadcastReceiver() {

    override fun onReceive(context: Context, intent: Intent) {
        // API 34+ 进程内二次门禁（主门禁 DUMP 在 AMS 层，见清单）；
        // 身份缺失（异常）时 fail-closed。
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
            val senderUid = runCatching { sentFromUid }.getOrNull()
                ?: Binder.getCallingUid()
            if (!isCallerTrusted(senderUid)) return
        }
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

        // Linux uid：root=0，adb shell=2000（AID_SHELL）。
        const val ROOT_UID = 0
        const val SHELL_UID = 2000

        /// 纯判定函数（无 Android 框架依赖，便于 JVM 单测）：
        /// 仅 root / shell 是 ECP 受信调用方。
        fun isCallerTrusted(uid: Int): Boolean =
            uid == ROOT_UID || uid == SHELL_UID
    }
}
