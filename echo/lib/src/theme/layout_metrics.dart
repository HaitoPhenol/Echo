/// 跨模块共享的布局度量（非视觉皮肤色值，也不绑定某个组件）。
///
/// 底部停靠区的三个基础量收在这里：`DockGeometry` 与日记导出弹窗都
/// 引用同一份常量，避免 UI 层为拿「停靠件避让高度」反向 import
/// navigation。数值与原 `DockGeometry` 常量逐字一致，行为不变。
abstract final class LayoutMetrics {
  LayoutMetrics._();

  /// 屏幕两侧留白 & 底部三条的统一间距。
  static const double dockSideMargin = 14;

  /// 底部三条距屏幕底部（安全区之上）的距离。
  static const double dockBottomMargin = 16;

  /// 底部三条的共同高度（也是翻页圆点的直径）。
  static const double dockBarHeight = 10;

  /// 停靠件上沿再留的间隙（浮层/弹窗收在导航条上方时使用）。
  static const double dockGap = 12;

  /// 浮层相对底部停靠件需要让出的高度：
  /// 安全区之外的 `bottomMargin + barHeight + gap`。
  static const double dockClearance =
      dockBottomMargin + dockBarHeight + dockGap;
}
