import 'package:flutter/material.dart';

import '../../theme/app_colors.dart';

/// 长按 AI 条后从底部升起的 **AI 对话框**（当前为输入壳）。
///
/// 对齐原型 another_two_lines.html 的形态：左右各留 14px、底部距
/// 停靠条 38px、高 min(52vh,360)、22px 圆角的深色面板，不自动收起，
/// 点外部（父级 scrim）才关闭。入场 320ms（曲线 (.3,1.2,.4,1)）
/// 从下方 20px、scale .96 弹入，不透明度 240ms。
///
/// **当前阶段只做到「能唤起输入法打字」**：消息区留空、发送按钮
/// 恒为占位禁用态、提交无行为。AI 能力接入时再在消息区与发送链路上
/// 做扩展，位置与外观已在此定型。
///
/// 键盘弹出由安卓 adjustResize 压缩窗口高度承载：父级以压缩后的
/// 窗口高度给本组件定位与定高，它自然停在键盘上方，无需手动补偿。
class AiDialog extends StatefulWidget {
  const AiDialog({super.key, required this.onDismissed});

  /// 收起动画播放结束（父级据此卸载本组件）。
  final VoidCallback onDismissed;

  @override
  State<AiDialog> createState() => AiDialogState();
}

class AiDialogState extends State<AiDialog>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 320),
  )..addStatusListener((status) {
      if (status == AnimationStatus.dismissed) {
        widget.onDismissed();
      }
    });

  late final Animation<double> _opacity = CurvedAnimation(
    parent: _controller,
    curve: const Interval(0, 240 / 320, curve: Curves.easeOut),
  );

  late final Animation<double> _motion = CurvedAnimation(
    parent: _controller,
    curve: const Cubic(0.3, 1.2, 0.4, 1),
  );

  /// 输入框自管焦点与文本（当前无对外逻辑需要；组件卸载即清空）。
  final FocusNode _focusNode = FocusNode();
  final TextEditingController _textController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _controller.forward();
    // 入场即聚焦，键盘随面板一起升起（直接满足「能打字」的入口）。
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _focusNode.requestFocus();
    });
  }

  /// 收起：先失焦收回键盘，再反向播放退场动画。
  void dismiss() {
    _focusNode.unfocus();
    _controller.reverse();
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    _textController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    const radius = BorderRadius.all(Radius.circular(22));

    return FadeTransition(
      opacity: _opacity,
      child: AnimatedBuilder(
        animation: _motion,
        builder: (context, child) {
          final v = _motion.value;
          return Transform.translate(
            offset: Offset(0, 20 * (1 - v)),
            child: Transform.scale(scale: 0.96 + 0.04 * v, child: child),
          );
        },
        child: DecoratedBox(
          // 阴影/描边画在裁剪区外，内容在内部 ClipRRect 中裁剪。
          decoration: BoxDecoration(
            color: AppColors.overlaySurface,
            borderRadius: radius,
            border: Border.all(color: AppColors.tone1),
            boxShadow: const [
              BoxShadow(
                color: Color(0x99000000),
                blurRadius: 50,
                offset: Offset(0, 18),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: radius,
            child: Column(
              children: [
                // 消息区：当前留空，AI 能力接入后在此铺消息流。
                const Expanded(child: SizedBox.expand()),

                // 输入行。
                Container(
                  decoration: const BoxDecoration(
                    border: Border(top: BorderSide(color: AppColors.tone1)),
                  ),
                  padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
                  child: Row(
                    children: [
                      Expanded(child: _inputPill()),
                      const SizedBox(width: 10),
                      _sendButton(),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// 40px 高的全圆角输入框。
  Widget _inputPill() {
    return Container(
      height: 40,
      alignment: Alignment.center,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: AppColors.tone1,
        borderRadius: BorderRadius.circular(20),
      ),
      child: TextField(
        controller: _textController,
        focusNode: _focusNode,
        style: const TextStyle(color: AppColors.textPrimary, fontSize: 15),
        cursorColor: AppColors.accentBlue,
        textInputAction: TextInputAction.send,
        onSubmitted: (_) {
          // 占位阶段：发送链路未接入，无行为。
        },
        decoration: const InputDecoration(
          isCollapsed: true,
          border: InputBorder.none,
          hintText: '问点什么…',
          hintStyle: TextStyle(color: Color(0xFF5A646E)),
        ),
      ),
    );
  }

  /// 发送按钮：白色圆形 + 深色上箭头。
  ///
  /// 当前**恒为禁用占位**（透明度 .3、不响应点击）——AI 行为未接入，
  /// 不做一个会响应却没有结果的死按钮；接入发送链路后恢复可点态。
  Widget _sendButton() {
    return IgnorePointer(
      child: Opacity(
        opacity: 0.3,
        child: Container(
          width: 36,
          height: 36,
          alignment: Alignment.center,
          decoration: const BoxDecoration(
            shape: BoxShape.circle,
            color: AppColors.tone4,
            boxShadow: [
              BoxShadow(color: Color(0x66FFFFFF), blurRadius: 18),
            ],
          ),
          child: const Icon(Icons.arrow_upward, size: 16, color: AppColors.inverse),
        ),
      ),
    );
  }
}
