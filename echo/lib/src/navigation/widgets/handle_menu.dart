import 'package:flutter/material.dart';

import '../../theme/app_colors.dart';
import '../dock_geometry.dart';
import '../page_action.dart';

/// 单击把手条后，从把手位置向上生长的**本页操作竖单**。
///
/// 起始帧与把手条完全一致（10px 高的 tone1 半圆小条），随后在 340ms
/// （曲线 (.3,1.2,.4,1)）内长高为深色胶囊：底色过渡到
/// [AppColors.overlaySurface]、描边与阴影淡入；三个圆形操作按钮
/// 从底部错峰弹入（30/70/110ms，translateY 12、scale .6 起手）。
///
/// 收起时反向播放，播完才通过 [onDismissed] 通知父级卸载并重新显示
/// 把手条——和搜索 pill 一样的「双组件同帧交接」，避免生长/收回
/// 期间的身份跳变。
///
/// 本组件只负责外观与入场编排；按钮位置（供父级画涟漪）、热区与
/// 互斥状态都在父级 SmartNavScreen 管理。
class HandleMenu extends StatefulWidget {
  const HandleMenu({
    super.key,
    required this.actions,
    required this.handleWidth,
    required this.onFire,
    required this.onDismissed,
  });

  /// 竖单内的操作（长度固定为 3，几何按 3 个按钮计算）。
  final List<PageAction> actions;

  /// 把手条宽度（竖单宽度与其一致）。
  final double handleWidth;

  /// 点按某个操作按钮（序号自上而下 0..2）。
  final ValueChanged<int> onFire;

  /// 收起动画播放结束（父级据此卸载本组件、重新显示把手条）。
  final VoidCallback onDismissed;

  @override
  State<HandleMenu> createState() => HandleMenuState();
}

class HandleMenuState extends State<HandleMenu>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller =
      AnimationController(
        vsync: this,
        duration: const Duration(milliseconds: 340),
      )..addStatusListener((status) {
        if (status == AnimationStatus.dismissed) {
          widget.onDismissed();
        }
      });

  /// 形状/高度时间轴曲线。
  static const Cubic _growCurve = Cubic(0.3, 1.2, 0.4, 1);

  @override
  void initState() {
    super.initState();
    _controller.forward();
  }

  /// 开始收起（由父级在触发操作或点外部关闭时调用）。
  void dismiss() {
    _controller.reverse();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  /// 第 i 个按钮（自上而下）的错峰入场区间。
  Animation<double> _item({
    required int index,
    required double spanMs,
    required Curve curve,
  }) {
    final start = (30 + 40 * index) / 340;
    return CurvedAnimation(
      parent: _controller,
      curve: Interval(
        start,
        (start + spanMs / 340).clamp(0.0, 1.0),
        curve: curve,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final width = widget.handleWidth;
    final menuHeight = DockGeometry.menuHeightFor(width);
    final buttonDiameter = DockGeometry.menuButtonDiameterFor(width);
    // 按钮距胶囊边缘的留白（横纵同值）：保证上下端弧与端按钮同心。
    final edgeInset = DockGeometry.menuEdgeInsetFor(width);
    // 圆角恒为宽度的一半：矮时两端是半圆，长高后是标准胶囊
    // （不写 999——渲染器对超大半径做横纵独立夹取会出椭圆角）。
    final radius = BorderRadius.circular(width / 2);

    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        final t = _growCurve.transform(_controller.value);
        final height =
            DockGeometry.barHeight + (menuHeight - DockGeometry.barHeight) * t;
        final surface = Color.lerp(
          AppColors.tone1,
          AppColors.overlaySurface,
          t,
        )!;
        final borderColor = AppColors.tone1.withValues(
          alpha: AppColors.tone1.a * t,
        );

        // IgnorePointer 必须在本 builder 内：只在挂载时构建一次的
        // 外层节点拿不到 status 翻转为 completed 的重建。
        return IgnorePointer(
          // 只有完全展开后按钮才接受点击；生长/收回途中交给父级 scrim。
          ignoring: _controller.status != AnimationStatus.completed,
          child: SizedBox(
            width: width,
            height: height,
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                // 阴影画在裁剪区之外（模糊不会被切掉）。
                if (t > 0.02)
                  Positioned.fill(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        borderRadius: radius,
                        boxShadow: [
                          BoxShadow(
                            color: const Color(0x8C000000)
                                .withValues(alpha: (0x8C / 255) * t),
                            blurRadius: 38,
                            offset: const Offset(0, 14),
                          ),
                        ],
                      ),
                    ),
                  ),
                // 形状层（底色 + 描边）同样在裁剪区之外。
                Positioned.fill(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: surface,
                      borderRadius: radius,
                      border: Border.all(color: borderColor),
                    ),
                  ),
                ),
                // 内容层按胶囊圆角裁剪。
                Positioned.fill(
                  child: ClipRRect(
                    borderRadius: radius,
                    child: Stack(
                      children: [
                        Positioned(
                          left: 0,
                          right: 0,
                          bottom: edgeInset,
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              for (
                                var i = 0;
                                i < widget.actions.length;
                                i++
                              ) ...[
                                if (i > 0) const SizedBox(height: 10),
                                _MenuButton(
                                  action: widget.actions[i],
                                  diameter: buttonDiameter,
                                  // 位移与缩放共用同一条错峰时间轴。
                                  entrance: _item(
                                    index: i,
                                    spanMs: 300,
                                    curve: const Cubic(0.3, 1.4, 0.4, 1),
                                  ),
                                  opacity: _item(
                                    index: i,
                                    spanMs: 200,
                                    curve: Curves.easeOut,
                                  ),
                                  onTap: () => widget.onFire(i),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// 竖单内的单个圆形操作按钮：白色圆底 + 深色图标 + 白色光晕。
///
/// 自身处理点击（在父级 scrim 之上，事件不会落到 scrim）。
class _MenuButton extends StatelessWidget {
  const _MenuButton({
    required this.action,
    required this.diameter,
    required this.entrance,
    required this.opacity,
    required this.onTap,
  });

  final PageAction action;
  final double diameter;

  /// 位移/缩放的错峰入场时间轴（区间内 0→1）。
  final Animation<double> entrance;

  /// 不透明度的错峰入场时间轴。
  final Animation<double> opacity;

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: opacity,
      child: AnimatedBuilder(
        animation: entrance,
        builder: (context, child) {
          final v = entrance.value;
          return Transform.translate(
            offset: Offset(0, 12 * (1 - v)),
            child: Transform.scale(scale: 0.6 + 0.4 * v, child: child),
          );
        },
        child: GestureDetector(
          onTap: onTap,
          behavior: HitTestBehavior.opaque,
          child: Container(
            width: diameter,
            height: diameter,
            alignment: Alignment.center,
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              color: AppColors.tone4,
              boxShadow: [BoxShadow(color: Color(0x66FFFFFF), blurRadius: 18)],
            ),
            child: Icon(
              action.icon,
              size: diameter * 0.46,
              color: AppColors.inverse,
            ),
          ),
        ),
      ),
    );
  }
}
