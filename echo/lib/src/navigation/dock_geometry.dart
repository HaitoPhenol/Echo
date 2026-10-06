import 'dart:math' as math;

/// 底部「三条一行」停靠区的几何事实来源。
///
/// 屏幕底部同一水平线上等高地住着三兄弟（原型
/// ideas/another_two_lines.html）：
/// - **把手条**（左）：宽 12% 屏宽；单击弹出本页操作竖单、右拖出抽屉；
/// - **AI 条**（中）：虹彩流动条，长按呼出对话框；
/// - **导航条整体**（右，含两端翻页圆点）：宽半屏。
///
/// 三条与屏幕边缘、条与条之间的间距全部为 [sideMargin]（14px）：
/// `14 + 把手(12%) + 14 + AI条(38%-56) + 14 + 导航整体(50%) + 14 = 屏宽`。
///
/// 所有视觉矩形与隐形热区都由本类静态常量/函数配合 MediaQuery 推算，
/// 不在运行时用 GlobalKey 测量（原因见工程规范事故 4）。
abstract final class DockGeometry {
  /// 屏幕两侧留白 & 三条之间的统一间距。
  static const double sideMargin = 14;

  /// 三条距屏幕底部（安全区之上）的距离。
  static const double bottomMargin = 16;

  /// 三条的共同高度（也是翻页圆点的直径）。
  static const double barHeight = 10;

  /// 翻页圆点直径。
  static const double dotDiameter = 10;

  /// 导航条与两端圆点的间距（一个半径）。
  static const double dotGap = dotDiameter / 2;

  /// 搜索态全宽胶囊高度。
  static const double searchHeight = 44;

  /// 把手条占屏宽比例（12vw）。
  static const double handleFraction = 0.12;

  /// 把手条宽度。
  static double handleWidthFor(double screenWidth) =>
      screenWidth * handleFraction;

  /// 把手条常态下的左边距（= [sideMargin]）。
  static double handleLeftFor(double screenWidth) => sideMargin;

  /// AI 条左边距（屏幕留白 + 把手宽 + 间距）。
  static double aiLeftFor(double screenWidth) =>
      sideMargin + handleWidthFor(screenWidth) + sideMargin;

  /// AI 条宽度（38vw - 56：扣除两侧留白与两条间距后恰填满中段）。
  static double aiWidthFor(double screenWidth) =>
      screenWidth * 0.38 - 4 * sideMargin;

  /// 导航条整体（圆点 + 条 + 圆点）宽度：半屏宽。
  static double navAssemblyWidthFor(double screenWidth) => screenWidth / 2;

  /// 缩短后的导航条本体宽度（扣除两端圆点与间距）。
  static double navBarWidthFor(double screenWidth) =>
      screenWidth / 2 - 2 * dotDiameter - 2 * dotGap;

  // ================================================================
  //  本页操作竖单（把手单击后向上生长的胶囊）
  // ================================================================

  /// 竖单内圆形按钮直径：把手宽 - 12，夹在 32~42 之间。
  static double menuButtonDiameterFor(double handleWidth) =>
      (handleWidth - 12).clamp(32.0, 42.0);

  /// 竖单按钮与胶囊边缘的留白（横、纵一致）。
  ///
  /// 必须等于 (把手宽 − 按钮直径) / 2：胶囊两端圆弧半径为把手宽的
  /// 一半，其圆心在边缘内 w/2 处；上下留白取此值时，最上/最下按钮
  /// 的圆心与端弧圆心重合——端弧恰好是按钮圆外扩同圈边距的同心圆，
  /// 胶囊端头不会在按钮之外多突出一截。
  static double menuEdgeInsetFor(double handleWidth) =>
      (handleWidth - menuButtonDiameterFor(handleWidth)) / 2;

  /// 竖单完全展开后的高度：3 个按钮 + 2 个间距(10) + 上下同心留白。
  static double menuHeightFor(double handleWidth) {
    final diameter = menuButtonDiameterFor(handleWidth);
    final edge = menuEdgeInsetFor(handleWidth);
    return 3 * diameter + 2 * 10 + 2 * edge;
  }

  // ================================================================
  //  侧边抽屉（把手右拖）
  // ================================================================

  /// 抽屉宽度：78% 屏宽，最大 340。
  static double drawerWidthFor(double screenWidth) =>
      math.min(screenWidth * 0.78, 340.0);

  /// 抽屉完全打开时把手条停靠的左边距（抽屉右缘 + 14px 间距）。
  static double dockedHandleLeftFor(double screenWidth) =>
      drawerWidthFor(screenWidth) + sideMargin;
}
