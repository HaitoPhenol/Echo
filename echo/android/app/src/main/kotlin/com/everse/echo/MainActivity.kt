package com.everse.echo

import android.content.Intent
import android.content.IntentFilter
import android.content.pm.ActivityInfo
import android.net.Uri
import android.os.BatteryManager
import android.os.Build
import android.os.Bundle
import android.os.VibrationEffect
import android.os.Vibrator
import androidx.annotation.NonNull
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

class MainActivity : FlutterActivity() {

    /// 触感反馈的方法通道名（与 Dart 端 Haptics 工具类一致）。
    private val hapticsChannelName = "echo/haptics"

    /// 设备状态快照通道名（机能风顶部读数条的数据源）。
    /// Dart 端消费方：MechanicalCoordsBar。
    private val deviceStatsChannelName = "echo/device_stats"

    /// 文件另存通道名（Dart 端 DiaryExportService 的「另存」渠道）。
    private val filesChannelName = "echo/files"

    /// ACTION_CREATE_DOCUMENT 的请求码（避开插件常用值）。
    private val createDocumentRequestCode = 0x4543

    /// 等待系统保存对话框返回的通道结果；null 表示无进行中的请求。
    private var pendingSaveResult: MethodChannel.Result? = null
    private var pendingSaveSource: String? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        // Q2 设备形态：手机强制锁竖屏，平板不锁方向（按最小宽度 dp 判定，约 sw600dp 为平板）
        val smallestWidthDp = resources.configuration.smallestScreenWidthDp
        requestedOrientation = if (smallestWidthDp >= 600) {
            ActivityInfo.SCREEN_ORIENTATION_UNSPECIFIED // 平板：跟随系统方向
        } else {
            ActivityInfo.SCREEN_ORIENTATION_PORTRAIT // 手机：锁定竖屏
        }
    }

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

        // -------- 日记导出「另存」（ACTION_CREATE_DOCUMENT / SAF）--------
        // 用户自选目录与文件名，无需存储权限；只负责把临时 zip 拷过去。
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, filesChannelName)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "saveFile" -> {
                        val sourcePath = call.argument<String>("sourcePath")
                        val fileName = call.argument<String>("fileName")
                        val mimeType =
                            call.argument<String>("mimeType") ?: "application/octet-stream"
                        when {
                            sourcePath == null || fileName == null ->
                                result.error("bad_args", "sourcePath / fileName 不能为空", null)
                            pendingSaveResult != null ->
                                result.error("busy", "已有另存请求在进行中", null)
                            else -> startSave(sourcePath, fileName, mimeType, result)
                        }
                    }
                    else -> result.notImplemented()
                }
            }
    }

    /// 拉起系统「保存到」对话框。
    private fun startSave(
        sourcePath: String,
        fileName: String,
        mimeType: String,
        result: MethodChannel.Result,
    ) {
        pendingSaveResult = result
        pendingSaveSource = sourcePath
        val intent = Intent(Intent.ACTION_CREATE_DOCUMENT).apply {
            addCategory(Intent.CATEGORY_OPENABLE)
            type = mimeType
            putExtra(Intent.EXTRA_TITLE, fileName)
        }
        try {
            startActivityForResult(intent, createDocumentRequestCode)
        } catch (e: Exception) {
            // 无文件选择器（极简系统）时直接回报未保存。
            finishPendingSave(false)
        }
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        if (requestCode == createDocumentRequestCode) {
            val uri: Uri? = data?.data
            val source = pendingSaveSource
            if (resultCode != RESULT_OK || uri == null || source == null) {
                finishPendingSave(false)
                return
            }
            // 拷贝放后台线程：整月 zip 可能较大，避免阻塞主线程。
            Thread {
                val saved = try {
                    contentResolver.openOutputStream(uri)?.use { out ->
                        File(source).inputStream().use { input -> input.copyTo(out) }
                    } != null
                } catch (e: Exception) {
                    false
                }
                runOnUiThread { finishPendingSave(saved) }
            }.start()
            return
        }
        super.onActivityResult(requestCode, resultCode, data)
    }

    /// 结束当前另存请求并回报结果（必须在主线程调用）。
    private fun finishPendingSave(saved: Boolean) {
        val result = pendingSaveResult ?: return
        pendingSaveResult = null
        pendingSaveSource = null
        result.success(saved)
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

        // 版本信息走 PackageManager（不引 package_info_plus）；
        // 长版本号即 pubspec 的 +buildNumber。
        val pkgInfo = packageManager.getPackageInfo(packageName, 0)
        @Suppress("DEPRECATION") // 新版 API 在 28 以下不可用，minSdk 26
        val buildNumber = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
            pkgInfo.longVersionCode
        } else {
            pkgInfo.versionCode.toLong()
        }

        // flavor 以包的 debuggable 标志为准：debug 构建自动置位，
        // release 清单不置位（本项目未开 buildConfig feature，
        // 直接读 PackageManager 标志，免生成 BuildConfig）。
        val debuggable =
            (pkgInfo.applicationInfo!!.flags and
                android.content.pm.ApplicationInfo.FLAG_DEBUGGABLE) != 0

        return mapOf(
            "model" to Build.MODEL,
            "osVersion" to Build.VERSION.RELEASE,
            "version" to pkgInfo.versionName,
            "buildNumber" to buildNumber,
            "flavor" to if (debuggable) "debug" else "release",
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
