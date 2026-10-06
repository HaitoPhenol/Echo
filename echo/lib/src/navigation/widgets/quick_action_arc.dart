import 'package:flutter/material.dart';

import '../../theme/app_colors.dart';
import '../quick_action.dart';

/// 竖直上甩导航条时弹出的「快捷操作弧」。
///
/// 三个圆形操作项沿弧线排列（位置由父级根据屏幕几何计算后传入）。
/// 横移手指可切换选中项，松手时触发并在选中项处显示涟漪，随后弧收起。
///
/// 当前三个图标均为占位，真实操作后续接入。
class QuickActionArc extends StatefulWidget {
  const QuickActionArc({
    super.key,
    required this.actions,
    required this.positions,
    required this.selection,
    required this.onFire,
    required this.onDismissed,
  }) : assert(
         actions.length == positions.length,
         'QuickActionArc：actions 与 positions 数量必须一致',
       );

  /// 按钮视觉直径（与 DockGeometry.quickArcButtonDiameter 同值，
  /// 组件内定位用本常量）。
  static const double buttonDiameter = 40;

  /// 相邻项入场错峰时长（曲线末端/上方项先出）。
  static const double _stagger = 0.14;

  /// 弧上的操作配置（与 [positions] 一一对应）。
  final List<QuickAction> actions;

  /// 操作项圆心的屏幕坐标。
  final List<Offset> positions;

  /// 当前选中项序号。
  final int selection;

  /// 触发（松手）时回调，参数为被选中项序号。
  final ValueChanged<int> onFire;

  /// 收起动画结束后回调（通知父级将本组件从树上移除）。
  final VoidCallback onDismissed;

  @override
  State<QuickActionArc> createState() => QuickActionArcState();
}

class QuickActionArcState extends State<QuickActionArc>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller =
      AnimationController(
        vsync: this,
        duration: const Duration(milliseconds: 360),
      )..addStatusListener((status) {
        if (status == AnimationStatus.dismissed) {
          widget.onDismissed();
        }
      });

  @override
  void initState() {
    super.initState();
    _controller.forward();
  }

  /// 收起弧；[fire] 为 true 时先触发当前选中项（父级负责显示涟漪）。
  void dismiss({required bool fire}) {
    if (fire) {
      widget.onFire(widget.selection);
    }
    _controller.reverse();
  }

  /// 第 [index] 个操作项的入场进度（上方项先出，向下依次错峰）。
  Animation<double> _itemAnimation(int index, Curve curve) {
    // 末项（index 最大）start=0，每项向下延后一个错峰。
    final start = QuickActionArc._stagger * (widget.actions.length - 1 - index);
    return CurvedAnimation(
      parent: _controller,
      curve: Interval(start, 1, curve: curve),
    );
  }

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      // 选择过程由父级的移动回调驱动，本组件自身不接收手势。
      child: Stack(
        children: List.generate(widget.actions.length, (i) {
          final selected = i == widget.selection;
          return Positioned(
            left: widget.positions[i].dx - QuickActionArc.buttonDiameter / 2,
            top: widget.positions[i].dy - QuickActionArc.buttonDiameter / 2,
            width: QuickActionArc.buttonDiameter,
            height: QuickActionArc.buttonDiameter,
            child: FadeTransition(
              opacity: _itemAnimation(i, Curves.easeOut),
              child: ScaleTransition(
                scale: _itemAnimation(
                  i,
                  const Cubic(0.3, 1.5, 0.4, 1),
                ).drive(Tween(begin: 0.55, end: 1.0)),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 220),
                  decoration: BoxDecoration(
                    color: selected
                        ? AppColors.tone4
                        : AppColors.searchBackground,
                    shape: BoxShape.circle,
                    border: selected
                        ? null
                        : Border.all(color: AppColors.tone1),
                    boxShadow: selected
                        ? const [
                            BoxShadow(color: AppColors.tone2, blurRadius: 18),
                            BoxShadow(
                              color: Color(0x80000000),
                              blurRadius: 24,
                              offset: Offset(0, 10),
                            ),
                          ]
                        : null,
                  ),
                  child: Icon(
                    widget.actions[i].icon,
                    size: 19,
                    color: selected ? AppColors.inverse : AppColors.textMuted,
                  ),
                ),
              ),
            ),
          );
        }),
      ),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }
}
