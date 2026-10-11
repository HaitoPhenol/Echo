package com.everse.echo

import android.app.Activity
import android.app.Application
import android.os.Bundle
import android.util.Log
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine

/// debug 包专属 Application：缓存当前 [FlutterActivity] 的 FlutterEngine，
/// 供 [DebugControlReceiver] 在无 Activity 的广播上下文里复用
/// （同一引擎：Dart 侧 ECP MethodChannel handler 只注册在它上面）。
///
/// release 包不注册本类（见 src/debug/AndroidManifest.xml），物理不存在
/// 任何 ECP 入口；不使用 FlutterEngineCache 是因为它要求主动 put/get
/// 引擎 id，而这里引擎仍由标准 FlutterActivity 生命周期托管，只借用
/// 引用，不改变引擎创建方式。
class DebugEchoApp : Application(), Application.ActivityLifecycleCallbacks {

    /// 最近一个处于 created 的 FlutterActivity 的引擎；销毁后清空。
    @Volatile
    var engine: FlutterEngine? = null
        private set

    override fun onCreate() {
        super.onCreate()
        registerActivityLifecycleCallbacks(this)
    }

    /// 抓取引擎的统一入口。注意时序：Application 的 onActivityCreated
    /// 是在 Activity.super.onCreate() 内部派发的，早于
    /// FlutterActivity.onCreate 后半段的 configureFlutterEngine，
    /// 因此首次尝试通常为 null；onStarted/onResumed 一定会再抓到。
    private fun tryCapture(activity: Activity) {
        if (activity !is FlutterActivity || engine != null) return
        // FlutterActivity.flutterEngine 是 protected，只能反射读 getter
        //（不改变引擎托管方式，只借用引用）。
        val candidate = runCatching { reflectEngine(activity) }
            .onFailure { Log.w(TAG, "读取 FlutterEngine 失败", it) }
            .getOrNull()
        if (candidate != null) {
            engine = candidate
            Log.i(TAG, "FlutterEngine 已缓存，ECP 通道就绪")
        }
    }

    override fun onActivityCreated(activity: Activity, savedInstanceState: Bundle?) =
        tryCapture(activity)

    override fun onActivityStarted(activity: Activity) = tryCapture(activity)

    override fun onActivityResumed(activity: Activity) = tryCapture(activity)

    /// 沿继承链找 protected `getFlutterEngine()` 并强制访问。
    /// 用 getDeclaredMethod 定点取而非 getDeclaredMethods：后者会解析
    /// 类上全部方法的返回类型，旧系统（API < 33）缺
    /// OnBackInvokedCallback 会直接 NoClassDefFoundError。
    private fun reflectEngine(activity: FlutterActivity): FlutterEngine? {
        var cls: Class<*>? = activity.javaClass
        while (cls != null) {
            val current = cls
            val candidate = runCatching {
                val getter = current.getDeclaredMethod("getFlutterEngine")
                getter.isAccessible = true
                getter.invoke(activity) as? FlutterEngine
            }.getOrNull()
            if (candidate != null) return candidate
            cls = current.superclass
        }
        return null
    }

    override fun onActivityDestroyed(activity: Activity) {
        if (activity is FlutterActivity) {
            engine = null
        }
    }

    override fun onActivityPaused(activity: Activity) = Unit
    override fun onActivityStopped(activity: Activity) = Unit
    override fun onActivitySaveInstanceState(activity: Activity, outState: Bundle) = Unit

    companion object {
        const val TAG = "EchoCtrl"
    }
}
