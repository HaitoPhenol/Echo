/// 控制面运行时状态：`sys.*` 命令读取的 App 现场。
library;

///
/// 与业务模块不同，这两个持有器没有自身逻辑——bootstrap 装配时
/// 注册到 ControlRegistry，平台侧实现（生命周期观察、MethodChannel
/// 设备快照）只负责往里写。

/// App 前后台状态（`sys.status.lifecycle`）。
///
/// 取值与 [WidgetsBindingObserver] 语义对齐：foreground/background。
/// 会话销毁另有 [AuthManager] 自行监听，本类仅作现场展示。
class ControlAppState {
  /// `foreground`（resumed/inactive 瞬态仍计前台）或 `background`（paused）。
  String lifecycle = 'foreground';
}

/// 设备/版本快照获取器（`sys.info`）。
///
/// bootstrap 注入真实实现（`echo/device_stats` MethodChannel +
/// BuildConfig）；测试注入假函数，不碰平台通道。
class ControlDeviceInfo {
  ControlDeviceInfo(this.fetchSnapshot);

  /// 返回 model/osVersion/version/buildNumber/flavor 等字段。
  final Future<Map<String, Object?>> Function() fetchSnapshot;
}
