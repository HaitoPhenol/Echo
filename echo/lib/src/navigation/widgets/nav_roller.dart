import 'package:flutter/material.dart';

import '../../theme/app_colors.dart';
import '../nav_physics.dart';

/// 滚筒指示器。
///
/// 横滑翻页时浮现在胶囊上方，包含：
/// - 顶部的页名标签 [_PageLabel]（模板阶段显示「第 n 页」，带翻转动画）；
/// - 横向滚动的页标圆点条（当前用数字代替图标，后续替换为真实页面图标）；
/// - 正中央的刻度线 [_CenterTick]。
///
/// 整体随 [NavPhysicsController.rollerVisible] 淡入淡出，
/// 隐藏时不响应指针事件。
class NavRoller extends StatelessWidget {
  const NavRoller({
    super.key,
    required this.controller,
    required this.width,
  });

  final NavPhysicsController controller;

  /// 滚筒宽度（与胶囊常规态同宽，即半屏）。
  final double width;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        final visible = controller.rollerVisible;
        return IgnorePointer(
          ignoring: !visible,
          child: AnimatedOpacity(
            opacity: visible ? 1 : 0,
            duration: const Duration(milliseconds: 220),
            child: AnimatedSlide(
              offset: visible ? Offset.zero : const Offset(0, 0.4),
              duration: const Duration(milliseconds: 340),
              curve: const Cubic(0.3, 1.4, 0.4, 1),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _PageLabel(visible: visible, page: controller.activePage + 1),
                  const SizedBox(height: 18),
                  _rollerBody(),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  /// 滚筒主体：深色圆角胶囊 + 渐隐遮罩 + 页标条 + 中央刻度。
  Widget _rollerBody() {
    return Container(
      width: width,
      height: 58,
      decoration: BoxDecoration(
        color: AppColors.rollerBackground,
        borderRadius: BorderRadius.circular(29),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x73000000),
            blurRadius: 34,
            offset: Offset(0, 12),
          ),
        ],
      ),
      // 圆角裁剪：页标条平移时数字不得画出滚筒胶囊之外。
      child: ClipRRect(
        borderRadius: BorderRadius.circular(29),
        child: ShaderMask(
        // 左右两端 16% 渐隐，模拟原型的 mask。
        shaderCallback: (rect) {
          return const LinearGradient(
            begin: Alignment.centerLeft,
            end: Alignment.centerRight,
            stops: [0, 0.16, 0.84, 1],
            colors: [
              Colors.transparent,
              Colors.white,
              Colors.white,
              Colors.transparent,
            ],
          ).createShader(rect);
        },
        blendMode: BlendMode.dstIn,
        child: Stack(
          clipBehavior: Clip.hardEdge,
          children: [
            _buildStrip(),
            Positioned(
              top: 7,
              bottom: 7,
              left: width / 2 - 1,
              width: 2,
              child: _CenterTick(activePage: controller.activePage),
            ),
          ],
        ),
        ),
      ),
    );
  }

  /// 页标条：整体随当前页位置平移，使激活页对齐滚筒中心。
  Widget _buildStrip() {
    final renderedPosition = controller.rubberized(controller.position);
    final count = controller.pageCount;

    return Positioned(
      top: 0,
      bottom: 0,
      left: width / 2 -
          20 -
          renderedPosition * NavPhysicsController.rollerPitch,
      width: (count - 1) * NavPhysicsController.rollerPitch + 40,
      child: Stack(
        children: List.generate(count, (i) {
          return Positioned(
            left: i * NavPhysicsController.rollerPitch,
            top: 9,
            width: 40,
            height: 40,
            child: _RollerDot(
              label: '${i + 1}',
              active: i == controller.activePage,
            ),
          );
        }),
      ),
    );
  }
}

/// 滚筒上的单个页标圆点。
///
/// 未选中：透明底、暗灰色数字；选中：白色圆底、深色数字并带辉光，
/// 同时播放一次弹性放大动画。
class _RollerDot extends StatefulWidget {
  const _RollerDot({required this.label, required this.active});

  final String label;
  final bool active;

  @override
  State<_RollerDot> createState() => _RollerDotState();
}

class _RollerDotState extends State<_RollerDot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _popController = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 300),
  );

  late final Animation<double> _scale = TweenSequence<double>([
    TweenSequenceItem(tween: Tween(begin: 1, end: 1.35), weight: 40),
    TweenSequenceItem(tween: Tween(begin: 1.35, end: 1), weight: 60),
  ]).animate(CurvedAnimation(parent: _popController, curve: Curves.easeOut));

  @override
  void didUpdateWidget(_RollerDot oldWidget) {
    super.didUpdateWidget(oldWidget);
    // 仅在「刚被选中」时重播弹跳动一次。
    if (widget.active && !oldWidget.active) {
      _popController.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _popController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ScaleTransition(
      scale: _scale,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        decoration: BoxDecoration(
          color: widget.active ? Colors.white : Colors.transparent,
          shape: BoxShape.circle,
          boxShadow: widget.active
              ? const [
                  BoxShadow(
                    color: Color(0x66FFFFFF),
                    blurRadius: 18,
                  ),
                ]
              : null,
        ),
        alignment: Alignment.center,
        child: Text(
          widget.label,
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w700,
            color: widget.active ? AppColors.inverse : AppColors.textMuted,
          ),
        ),
      ),
    );
  }
}

/// 滚筒正中央的竖向刻度线，页面切换时播放一次高亮脉冲。
class _CenterTick extends StatefulWidget {
  const _CenterTick({required this.activePage});

  final int activePage;

  @override
  State<_CenterTick> createState() => _CenterTickState();
}

class _CenterTickState extends State<_CenterTick>
    with SingleTickerProviderStateMixin {
  late final AnimationController _tickController = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 280),
  );

  late final Animation<double> _glow =
      Tween(begin: 0.0, end: 1.0).animate(
    CurvedAnimation(parent: _tickController, curve: Curves.easeOut),
  );

  @override
  void didUpdateWidget(_CenterTick oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.activePage != oldWidget.activePage) {
      _tickController.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _tickController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _glow,
      builder: (context, _) {
        // 高亮值：0.3s 内先亮后暗（用三角包络）。
        final glow = 1 - (_glow.value - 0.3).abs() / 0.7;
        final alpha = 0.14 + 0.81 * glow.clamp(0, 1);
        return DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(1),
            color: Colors.white.withValues(alpha: alpha),
            boxShadow: glow > 0.4
                ? [
                    BoxShadow(
                      color: Colors.white.withValues(alpha: 0.7 * glow),
                      blurRadius: 10,
                    ),
                  ]
                : null,
          ),
        );
      },
    );
  }
}

/// 页名标签：显示「第 n 页」，页面切换时播放上翻隐入的翻转动画。
class _PageLabel extends StatefulWidget {
  const _PageLabel({required this.visible, required this.page});

  final bool visible;
  final int page;

  @override
  State<_PageLabel> createState() => _PageLabelState();
}

class _PageLabelState extends State<_PageLabel>
    with SingleTickerProviderStateMixin {
  late final AnimationController _flipController = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 340),
    value: 1,
  );

  @override
  void didUpdateWidget(_PageLabel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.page != oldWidget.page) {
      _flipController.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _flipController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedOpacity(
      opacity: widget.visible ? 1 : 0,
      duration: const Duration(milliseconds: 250),
      child: AnimatedBuilder(
        animation: _flipController,
        builder: (context, child) {
          final t = _flipController.value;
          // 0~45%：向上 6px 并淡出；46%~100%：从下方 6px 回到原位并淡入。
          final (Offset offset, double opacity) = t < 0.45
              ? (Offset(0, -6 * t / 0.45), 1 - t / 0.45)
              : (
                  Offset(0, 6 * (1 - (t - 0.46) / 0.54)),
                  (t - 0.46) / 0.54,
                );
          return Opacity(
            opacity: opacity.clamp(0, 1),
            child: Transform.translate(offset: offset, child: child),
          );
        },
        child: Text(
          '第 ${widget.page} 页',
          textAlign: TextAlign.center,
          style: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            letterSpacing: 3,
            color: AppColors.pageLabel,
          ),
        ),
      ),
    );
  }
}
