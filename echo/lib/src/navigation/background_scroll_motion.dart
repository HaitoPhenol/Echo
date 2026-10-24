import 'package:flutter/widgets.dart';

/// 竖向滚动手势 → 背景纵向位移的通用桥接。
///
/// 页面里的任何竖向滚动（`ListView` / `CustomScrollView` / …）都会发出
/// [ScrollUpdateNotification]。本类只累加它的
/// [ScrollUpdateNotification.scrollDelta]，因此：
/// * 不依赖具体列表，也不需要给每个列表挂 `ScrollController`；
/// * 不受列表绝对偏移、换页、重建影响——只认"这一帧滚了多少"；
/// * 手指往上推（内容上移，delta > 0）时背景同步上移（offsetY 减小），
///   与现有横向「图纸随页面同速平移」的方向语义一致。
class BackgroundScrollMotion extends ChangeNotifier {
  BackgroundScrollMotion({this.factor = 1});

  /// 背景位移倍率：`背景位移 = -滚动增量 × factor`。
  ///
  /// 1 表示与内容同速（像图纸被一起拖动），0.5 为减速视差。
  final double factor;

  double _offsetY = 0;

  /// 背景纵向位移（dp，正数为向下）。取模由绘制层按需处理。
  double get offsetY => _offsetY;

  /// 累加一次竖向滚动增量。
  void applyScrollDelta(double delta) {
    if (delta == 0 || factor == 0) return;
    _offsetY -= delta * factor;
    notifyListeners();
  }

  /// 归零（页面重建/需要重新对齐时使用）。
  void reset() {
    if (_offsetY == 0) return;
    _offsetY = 0;
    notifyListeners();
  }
}

/// 把子树中的竖向滚动增量转发给 [motion]。
///
/// 只认 `depth == 0` 的竖向滚动：嵌套滚动（如行内横向滑动、
/// 列表里的横向小条）不会污染背景位移。
class BackgroundScrollListener extends StatelessWidget {
  const BackgroundScrollListener({
    super.key,
    required this.motion,
    required this.child,
  });

  final BackgroundScrollMotion motion;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return NotificationListener<ScrollNotification>(
      onNotification: (notification) {
        if (notification.depth != 0) return false;
        if (notification.metrics.axis != Axis.vertical) return false;
        if (notification is ScrollUpdateNotification) {
          motion.applyScrollDelta(notification.scrollDelta ?? 0);
        }
        return false;
      },
      child: child,
    );
  }
}
