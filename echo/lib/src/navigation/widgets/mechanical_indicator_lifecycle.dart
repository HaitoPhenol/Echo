import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../theme/mechanical_style.dart';

/// 页码指示器（左下页名牌 / 右下转鼓）共用的显隐骨架，二者借此
/// 保持「分开的整体」——同一个 [visible] 边沿、同一组时长。
///
/// **入场**（沿用旧节奏）：[AnimatedOpacity] 220ms 淡入 +
/// [AnimatedSlide] 340ms 上浮（带回弹曲线）。
///
/// **退场**（赛博故障风）：水平「百叶窗」——构件切成
/// [MechanicalStyle.indicatorExitBandCount] 条横带，按固定乱序
/// 错峰熄灭，每带在自己的窗口内快速两明两暗后彻底消失；前半段
/// 叠加整构件小幅数码横抖（快速衰减）。总时长仍是
/// [MechanicalStyle.indicatorRiseDuration] 340ms，所有横带在
/// 约 300ms 前灭完，干脆不拖尾。用单个 [ClipPath] 合成（子树
/// 每帧只绘一次），转鼓的 3D painter 也不会乘 N 倍重绘。
class MechanicalIndicatorLifecycle extends StatefulWidget {
  const MechanicalIndicatorLifecycle({
    super.key,
    required this.visible,
    this.instant = false,
    required this.child,
  });

  /// 与转鼓同一 rollerVisible：true 显示（播入场），false 时按
  /// [instant] 决定立即离屏或播退场百叶窗。
  final bool visible;

  /// true：本次隐藏立即离屏、不播退场（上甩切快捷弧/进入搜索态，
  /// 互斥不叠加）。
  final bool instant;

  final Widget child;

  @override
  State<MechanicalIndicatorLifecycle> createState() =>
      _MechanicalIndicatorLifecycleState();
}

class _MechanicalIndicatorLifecycleState
    extends State<MechanicalIndicatorLifecycle>
    with SingleTickerProviderStateMixin {
  late final AnimationController _exit = AnimationController(
    vsync: this,
    // 退场总时长与旧 fade/rise 中较长的 rise 相同（340ms）。
    duration: MechanicalStyle.indicatorRiseDuration,
  );

  /// 退场动画播放期间为 true：保持挂树、内容全亮，只让百叶窗裁掉；
  /// 播完置 false 离屏（Offstage），同时 AnimatedOpacity/Slide 在
  /// 离屏态回到 0/下沉，下次唤醒重新淡入上浮。
  bool _exiting = false;

  @override
  void initState() {
    super.initState();
    if (!widget.visible) {
      // 首帧即隐藏：停在退场终点（离屏态由 Offstage 处理）。
      _exit.value = 1;
    }
  }

  @override
  void didUpdateWidget(MechanicalIndicatorLifecycle oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.visible == widget.visible) return;
    if (widget.visible) {
      // 中途唤醒（打断退场）：立即回全亮，不补入场。
      _exit.value = 0;
      _exiting = false;
    } else {
      if (widget.instant) {
        // 互斥路径：立即离屏，不播退场。
        _exit.value = 1;
        _exiting = false;
      } else {
        _exiting = true;
        _exit.forward(from: 0).whenCompleteOrCancel(() {
          if (mounted && !widget.visible) {
            setState(() => _exiting = false);
          }
        });
      }
    }
  }

  @override
  void dispose() {
    _exit.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final shown = widget.visible || _exiting;
    return IgnorePointer(
      ignoring: !shown,
      child: Offstage(
        offstage: !shown,
        child: AnimatedBuilder(
          animation: _exit,
          builder: (context, child) {
            final t = _exit.value;
            // 仅退场前 55% 有横抖，正弦高频、线性衰减到 0。
            final jitter = t > 0 && t < 0.55
                ? math.sin(t * 64) *
                      MechanicalStyle.indicatorExitJitter *
                      (1 - t / 0.55)
                : 0.0;
            return Transform.translate(
              offset: Offset(jitter, 0),
              child: ClipPath(clipper: _ExitBlindsClipper(t), child: child),
            );
          },
          // 入场骨架：离屏态 opacity 0 + 下沉 0.4；退场期间保持
          // 全亮原位（shown 为 true），避免与百叶窗叠加发灰。
          child: AnimatedOpacity(
            opacity: shown ? 1 : 0,
            duration: MechanicalStyle.indicatorFadeDuration,
            child: AnimatedSlide(
              offset: shown ? Offset.zero : const Offset(0, 0.4),
              duration: MechanicalStyle.indicatorRiseDuration,
              curve: const Cubic(0.3, 1.4, 0.4, 1),
              child: widget.child,
            ),
          ),
        ),
      ),
    );
  }
}

/// 退场百叶窗裁剪：t=0 全显，t 推进时各横带按固定乱序错峰，
/// 在自身窗口内两明两暗后熄灭，t=1 全灭。
class _ExitBlindsClipper extends CustomClipper<Path> {
  const _ExitBlindsClipper(this.t);

  final double t;

  /// 横带熄灭次序（0..9 的一个固定置换，乘 7 取模得到的伪随机序；
  /// 不使用 Random——同一次退场必须逐帧确定、可复现）。
  static const List<int> _order = [0, 7, 4, 1, 8, 5, 2, 9, 6, 3];

  /// 错峰窗口起点占总时长的跨度：最后一带在 t≈0.42 才开始灭。
  static const double _staggerSpan = 0.42;

  /// 每带自身闪烁窗口占总时长比例。
  static const double _bandWindow = 0.5;

  static bool _bandOn(int i, double t) {
    final rank = _order.indexOf(i);
    final start = rank / MechanicalStyle.indicatorExitBandCount * _staggerSpan;
    if (t <= start) return true;
    final p = (t - start) / _bandWindow;
    if (p >= 1) return false;
    // 两明两暗：明 [0,.18) / 暗 [.18,.30) / 明 [.30,.52) /
    // 暗 [.52,.66) / 明 [.66,.80) / 灭 [.80,1]。
    return p < 0.18 || (p >= 0.30 && p < 0.52) || (p >= 0.66 && p < 0.80);
  }

  @override
  Path getClip(Size size) {
    const n = MechanicalStyle.indicatorExitBandCount;
    assert(_order.length == n);
    // 四边外扩 2px：亮角标骑边框外扩 1px，不能在退场期间被硬裁掉。
    const bleed = 2.0;
    final path = Path();
    if (t <= 0) {
      path.addRect(
        Rect.fromLTRB(-bleed, -bleed, size.width + bleed, size.height + bleed),
      );
      return path;
    }
    final bandH = size.height / n;
    for (var i = 0; i < n; i++) {
      if (_bandOn(i, t)) {
        path.addRect(
          Rect.fromLTRB(
            -bleed,
            i * bandH - bleed,
            size.width + bleed,
            (i + 1) * bandH + bleed,
          ),
        );
      }
    }
    return path;
  }

  @override
  bool shouldReclip(_ExitBlindsClipper oldClipper) => oldClipper.t != t;
}
