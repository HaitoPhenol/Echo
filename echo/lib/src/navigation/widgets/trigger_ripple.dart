import 'package:flutter/material.dart';

import '../../theme/app_colors.dart';

/// 快捷操作触发处的扩散涟漪。
///
/// 60px 的亮白圆环从 0.45 倍扩散到 2.5 倍并淡出，时长 650ms。
class TriggerRipple extends StatefulWidget {
  const TriggerRipple({super.key, required this.onEnded});

  /// 动画结束后回调（父级将其移除）。
  final VoidCallback onEnded;

  @override
  State<TriggerRipple> createState() => _TriggerRippleState();
}

class _TriggerRippleState extends State<TriggerRipple>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller =
      AnimationController(
        vsync: this,
        duration: const Duration(milliseconds: 650),
      )..addStatusListener((status) {
        if (status == AnimationStatus.completed) {
          widget.onEnded();
        }
      });

  late final Animation<double> _scale = CurvedAnimation(
    parent: _controller,
    curve: const Cubic(0.2, 0.7, 0.3, 1),
  ).drive(Tween(begin: 0.45, end: 2.5));

  late final Animation<double> _opacity = Tween(
    begin: 1.0,
    end: 0.0,
  ).animate(_controller);

  @override
  void initState() {
    super.initState();
    _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: FadeTransition(
        opacity: _opacity,
        child: ScaleTransition(
          scale: _scale,
          child: Container(
            width: 60,
            height: 60,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: AppColors.tone4, width: 2),
              boxShadow: const [
                BoxShadow(color: AppColors.tone2, blurRadius: 16),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
