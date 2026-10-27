import 'package:flutter/material.dart';

import '../../ai/ui/ai_chat_panel.dart';
import '../../theme/app_colors.dart';

/// 长按 AI 条后从底部升起的 **AI 对话框**。
///
/// 对齐原型 another_two_lines.html 的形态：左右各留 14px、底部距
/// 停靠条 38px、高 min(52vh,360)、22px 圆角的深色面板，不自动收起，
/// 点外部（父级 scrim）才关闭。入场 320ms（曲线 (.3,1.2,.4,1)）
/// 从下方 20px、scale .96 弹入，不透明度 240ms。
///
/// 消息流与发送链路与聊天页全屏对话共用 [AiChatController]：
/// 消息来自聊天仓储的 AI 会话，流入中的正文来自控制器草稿，
/// 已完成的轮次两处入口同时可见。
///
/// 键盘避让由父级定位承载：根 Scaffold 不开自动避让，父级读到
/// `viewInsets.bottom` 后把本组件整体上移，并按键盘上方可用高度
/// 收敛面板高度；本组件自身不做键盘补偿。
class AiDialog extends StatefulWidget {
  const AiDialog({super.key, required this.onDismissed});

  /// 收起动画播放结束（父级据此卸载本组件）。
  final VoidCallback onDismissed;

  @override
  State<AiDialog> createState() => AiDialogState();
}

class AiDialogState extends State<AiDialog>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller =
      AnimationController(
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

  /// 输入框自管焦点与文本（面板卸载即清空；发送由共用 composer 负责）。
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
                // 消息流：与聊天页全屏对话同源（仓储消息 + 流入草稿）。
                const Expanded(
                  child: AiChatTranscript(
                    padding: EdgeInsets.fromLTRB(12, 8, 12, 4),
                  ),
                ),

                // 输入行。
                Container(
                  decoration: const BoxDecoration(
                    border: Border(top: BorderSide(color: AppColors.tone1)),
                  ),
                  child: AiChatComposer(
                    hintText: '问点什么…',
                    focusNode: _focusNode,
                    textController: _textController,
                    padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
