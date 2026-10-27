import 'package:flutter/material.dart';

import '../../services/chat_store.dart';
import '../../theme/app_colors.dart';
import '../ai_chat_controller.dart';

// AI 对话的共用渲染件：两处入口（AI 条对话框、聊天页全屏对话）
// 都只用这里的消息流与输入行，样式与行为保持一致。

/// 消息流：倒序列表（最新在底部，无需滚动控制器）。
///
/// 数据源分两层：
/// - 已完成消息来自 [ChatStore] 的 AI 会话（持久化、列表预览同源）；
/// - 正在流入的正文来自 [AiChatController.draft]（尚未落库）。
///
/// 顶部固定展示最近一次 token 用量（有数据时）。
class AiChatTranscript extends StatelessWidget {
  const AiChatTranscript({
    super.key,
    this.padding = const EdgeInsets.fromLTRB(14, 10, 14, 6),
  });

  /// 列表内边距（对话框与全屏页可按可用高度微调）。
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    final store = ChatStoreScope.of(context);
    final chat = AiChatScope.of(context);
    final usage = chat.lastUsage;

    final messages = store.conversationOf(AiConversation.id) == null
        ? const <ChatMessage>[]
        : store
              .messagesOf(AiConversation.id, limit: AiConversation.historyLimit)
              .items;

    final hasDraft = chat.draft.isNotEmpty;
    final error = chat.lastError;
    final empty = messages.isEmpty && !hasDraft && error == null;

    return Column(
      children: [
        if (usage != null && !usage.isEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 8, 14, 0),
            child: Align(
              alignment: Alignment.centerRight,
              child: Text(usage.label, style: _usageStyle),
            ),
          ),
        Expanded(
          child: empty
              ? const Center(
                  child: Text(AiConversation.emptyHint, style: _emptyHintStyle),
                )
              : ListView.builder(
                  key: const ValueKey<String>('ai-chat-transcript'),
                  reverse: true,
                  padding: padding,
                  itemCount:
                      messages.length +
                      (hasDraft ? 1 : 0) +
                      (error != null ? 1 : 0),
                  itemBuilder: (context, index) {
                    // 索引 0 是最新内容：流入中的草稿在最下，其次错误。
                    if (hasDraft && index == 0) {
                      return _AssistantBubble(text: '${chat.draft}▍');
                    }
                    final errorIndex = hasDraft ? 1 : 0;
                    if (error != null && index == errorIndex) {
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Align(
                          alignment: Alignment.centerLeft,
                          child: Text(error, style: _errorStyle),
                        ),
                      );
                    }
                    final messageIndex =
                        index - (hasDraft ? 1 : 0) - (error != null ? 1 : 0);
                    final message = messages[messageIndex];
                    return message.direction == ChatDirection.outgoing
                        ? _UserBubble(text: message.text)
                        : _AssistantBubble(text: message.text);
                  },
                ),
        ),
      ],
    );
  }
}

/// 输入行：圆角输入框 + 圆形发送键；发送中/未配置时禁用。
///
/// 键盘行为由外层页面承担（对话框随键盘抬升、全屏页用 Scaffold
/// 默认避让），本组件只管输入与提交。
class AiChatComposer extends StatefulWidget {
  const AiChatComposer({
    super.key,
    this.hintText = '问点什么…',
    this.focusNode,
    this.textController,
    this.padding = const EdgeInsets.fromLTRB(12, 8, 12, 12),
  });

  final String hintText;

  /// 外部提供的焦点/文本控制器（对话框入场后要自动聚焦）。
  final FocusNode? focusNode;
  final TextEditingController? textController;

  final EdgeInsets padding;

  @override
  State<AiChatComposer> createState() => _AiChatComposerState();
}

class _AiChatComposerState extends State<AiChatComposer> {
  late final FocusNode _focusNode = widget.focusNode ?? FocusNode();
  late final TextEditingController _textController =
      widget.textController ?? TextEditingController();

  @override
  void dispose() {
    if (widget.focusNode == null) _focusNode.dispose();
    if (widget.textController == null) _textController.dispose();
    super.dispose();
  }

  void _submit() {
    final chat = AiChatScope.maybeOf(context);
    if (chat == null || !chat.canSend) return;
    final text = _textController.text;
    if (text.trim().isEmpty) return;
    _textController.clear();
    chat.send(text);
    _focusNode.requestFocus();
  }

  @override
  Widget build(BuildContext context) {
    final chat = AiChatScope.of(context);
    final canSend = chat.canSend;
    final hint = chat.isConfigured
        ? widget.hintText
        : AiConversation.unconfiguredHint;

    return Padding(
      padding: widget.padding,
      child: Row(
        children: [
          Expanded(
            child: Container(
              height: 40,
              alignment: Alignment.center,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              decoration: BoxDecoration(
                color: AppColors.tone1,
                borderRadius: BorderRadius.circular(20),
              ),
              child: TextField(
                key: const ValueKey<String>('ai-chat-input'),
                controller: _textController,
                focusNode: _focusNode,
                style: const TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 15,
                ),
                cursorColor: AppColors.accentBlue,
                textInputAction: TextInputAction.send,
                onSubmitted: (_) => _submit(),
                decoration: InputDecoration(
                  isCollapsed: true,
                  border: InputBorder.none,
                  hintText: hint,
                  hintStyle: const TextStyle(color: Color(0xFF5A646E)),
                ),
              ),
            ),
          ),
          const SizedBox(width: 10),
          _SendButton(enabled: canSend, onTap: _submit),
        ],
      ),
    );
  }
}

/// 发送键：白色圆形 + 深色上箭头；禁用时半透明且不响应点击。
class _SendButton extends StatelessWidget {
  const _SendButton({required this.enabled, required this.onTap});

  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: enabled ? onTap : null,
      child: AnimatedOpacity(
        duration: const Duration(milliseconds: 120),
        opacity: enabled ? 1 : 0.3,
        child: Container(
          width: 36,
          height: 36,
          alignment: Alignment.center,
          decoration: const BoxDecoration(
            shape: BoxShape.circle,
            color: AppColors.tone4,
            boxShadow: [BoxShadow(color: Color(0x66FFFFFF), blurRadius: 18)],
          ),
          child: const Icon(
            Icons.arrow_upward,
            size: 16,
            color: AppColors.inverse,
          ),
        ),
      ),
    );
  }
}

/// 用户消息：右对齐、强调蓝底气泡。
class _UserBubble extends StatelessWidget {
  const _UserBubble({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return _bubble(
      context,
      text: text,
      alignment: Alignment.centerRight,
      color: AppColors.accentBlue.withValues(alpha: 0.20),
      radius: const BorderRadius.only(
        topLeft: Radius.circular(14),
        topRight: Radius.circular(14),
        bottomLeft: Radius.circular(14),
        bottomRight: Radius.circular(4),
      ),
    );
  }
}

/// AI 消息：左对齐、tone1 底气泡。
class _AssistantBubble extends StatelessWidget {
  const _AssistantBubble({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return _bubble(
      context,
      text: text,
      alignment: Alignment.centerLeft,
      color: AppColors.tone1,
      radius: const BorderRadius.only(
        topLeft: Radius.circular(14),
        topRight: Radius.circular(14),
        bottomLeft: Radius.circular(4),
        bottomRight: Radius.circular(14),
      ),
    );
  }
}

Widget _bubble(
  BuildContext context, {
  required String text,
  required Alignment alignment,
  required Color color,
  required BorderRadius radius,
}) {
  return Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: Align(
      alignment: alignment,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: MediaQuery.sizeOf(context).width * 0.82,
        ),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(color: color, borderRadius: radius),
          child: Text(
            text,
            style: const TextStyle(
              color: AppColors.textPrimary,
              fontSize: 15,
              height: 1.35,
            ),
          ),
        ),
      ),
    ),
  );
}

const TextStyle _usageStyle = TextStyle(
  fontSize: 11,
  color: AppColors.textMuted,
);

const TextStyle _emptyHintStyle = TextStyle(
  fontSize: 13,
  color: AppColors.textMuted,
);

const TextStyle _errorStyle = TextStyle(
  fontSize: 12,
  color: AppColors.anchorRed,
);
