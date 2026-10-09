package com.everse.echo

import android.content.Intent
import android.content.IntentFilter
import android.os.BatteryManager
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

    /// 设备状态快照通道名（机能风实验 feat/page-background-art）。
    /// 实验放弃时本通道与 Dart 端 MechanicalCoordsBar 一起删除。
    private val deviceStatsChannelName = "echo/device_stats"

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

        // -------- 设备状态监控（机能风实验，零三方库、零权限）--------
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, deviceStatsChannelName)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "snapshot" -> result.success(readDeviceStats())
                    else -> result.notImplemented()
                }
            }
    }

    /// 读取一次设备状态：型号 / 电池温度 / 瞬时功耗绝对值。
    ///
    /// 全部来自系统 API（Build + 电池粘性广播 + BatteryManager），
    /// 无传感器或缺字段时对应值返回 null，由 Dart 端显示「—」。
    private fun readDeviceStats(): Map<String, Any?> {
        // 粘性广播：receiver 传 null 直接拿到最近一次电池广播。
        val intent = registerReceiver(null, IntentFilter(Intent.ACTION_BATTERY_CHANGED))

        // 温度：EXTRA_TEMPERATURE 单位 0.1°C。
        val tempRaw = intent?.getIntExtra(BatteryManager.EXTRA_TEMPERATURE, Int.MIN_VALUE)
        val tempC = if (tempRaw != null && tempRaw != Int.MIN_VALUE) tempRaw / 10.0 else null

        // 功耗：|瞬时电流(µA)| × 电压(mV) / 1e9 = W
        // （µA·mV = 1e-9 W；取绝对值，放电/充电都显示正功率）。
        val bm = getSystemService(BATTERY_SERVICE) as? BatteryManager
        val currentUa = bm?.getIntProperty(BatteryManager.BATTERY_PROPERTY_CURRENT_NOW)
        val voltageMv = intent?.getIntExtra(BatteryManager.EXTRA_VOLTAGE, -1) ?: -1
        val powerW = if (currentUa != null &&
            currentUa != Int.MIN_VALUE &&
            voltageMv > 0
        ) {
            kotlin.math.abs(currentUa).toDouble() * voltageMv / 1_000_000_000.0
        } else {
            null
        }

        return mapOf(
            "model" to Build.MODEL,
            "tempC" to tempC,
            "powerW" to powerW,
        )
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
