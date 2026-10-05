package com.everse.echo

import android.os.Build
import android.os.VibrationEffect
import android.os.Vibrator
import androidx.annotation.NonNull
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {

    /// 触感反馈的方法通道名（与 Dart 端 Haptics 工具类一致）。
    private val hapticsChannelName = "echo/haptics"

    override fun configureFlutterEngine(@NonNull flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, hapticsChannelName)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    // 轻微短震：翻页/选择时的细粒度反馈
                    "tick" -> {
                        vibrate(durationMs = 14, amplitude = 70)
                        result.success(null)
                    }
                    // 稍强确认震：长按搜索展开、快捷操作触发
                    "confirm" -> {
                        vibrate(durationMs = 26, amplitude = 130)
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }
    }

    /// 直接驱动振动马达。
    ///
    /// 走 Vibrator 服务而非 View.performHapticFeedback，因此不受系统
    /// 「触感反馈」开关限制；需要 VIBRATE 权限。
    private fun vibrate(durationMs: Long, amplitude: Int) {
        val vibrator = getSystemService(Vibrator::class.java) ?: return
        if (!vibrator.hasVibrator()) return

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            // 振幅区间 1..255；个别设备不支持振幅控制时回退默认强度。
            val effect = if (vibrator.hasAmplitudeControl()) {
                VibrationEffect.createOneShot(durationMs, amplitude)
            } else {
                VibrationEffect.createOneShot(
                    durationMs,
                    VibrationEffect.DEFAULT_AMPLITUDE,
                )
            }
            vibrator.vibrate(effect)
        } else {
            @Suppress("DEPRECATION")
            vibrator.vibrate(durationMs)
        }
    }
}
