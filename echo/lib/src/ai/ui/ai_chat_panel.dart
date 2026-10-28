import 'package:flutter/material.dart';

import '../../common/markdown_view.dart';
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
/// token 用量默认画在消息流顶部；整屏对话页把它放进标题栏右侧，
/// 传 `showUsage: false` 交给外层渲染。
class AiChatTranscript extends StatelessWidget {
  const AiChatTranscript({
    super.key,
    this.padding = const EdgeInsets.fromLTRB(14, 10, 14, 6),
    this.showUsage = true,
  });

  /// 列表内边距（对话框与全屏页可按可用高度微调）。
  final EdgeInsets padding;

  /// 是否在顶部渲染最近一次 token 用量。
  final bool showUsage;

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
    final hasReasoningDraft = chat.reasoningDraft.isNotEmpty;
    final error = chat.lastError;
    final empty =
        messages.isEmpty && !hasDraft && !hasReasoningDraft && error == null;

    return Column(
      children: [
        if (showUsage && usage != null && !usage.isEmpty)
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
                      (hasReasoningDraft ? 1 : 0) +
                      (error != null ? 1 : 0),
                  itemBuilder: (context, index) {
                    // 索引 0 是最新内容：流入中的正文在最下，思考块在其上方，
                    // 再往上才是错误与已落库消息。
                    if (hasDraft && index == 0) {
                      // 流式期间每来一个 token 都会重建文本，选取会被反复
                      // 清空，所以草稿气泡先不开选取，落库后再选。
                      return _AssistantBubble(
                        text: '${chat.draft}▍',
                        selectable: false,
                      );
                    }
                    if (hasReasoningDraft && index == (hasDraft ? 1 : 0)) {
                      // 正文一到，思考就收成一行「已思考 12.3s」，不再铺满灰字。
                      return hasDraft
                          ? _StreamingReasoning(
                              text: chat.reasoningDraft,
                              reasoningMs: chat.reasoningMs,
                            )
                          : _ReasoningBubble(text: chat.reasoningDraft);
                    }
                    final streamingCount =
                        (hasDraft ? 1 : 0) + (hasReasoningDraft ? 1 : 0);
                    if (error != null && index == streamingCount) {
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Align(
                          alignment: Alignment.centerLeft,
                          child: Text(error, style: _errorStyle),
                        ),
                      );
                    }
                    final messageIndex =
                        index - streamingCount - (error != null ? 1 : 0);
                    final message = messages[messageIndex];
                    return message.direction == ChatDirection.outgoing
                        ? _UserBubble(text: message.text)
                        : _AssistantBubble(
                            key: ValueKey<String>(message.id),
                            text: message.text,
                            reasoning: message.reasoning,
                            reasoningMs: message.reasoningMs,
                          );
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
      markdown: false,
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
///
/// 带思考内容时，气泡上方先显示一行「已思考 12.3s」，点按展开/收起
/// 思考正文（默认收起，避免淹没回答）。
class _AssistantBubble extends StatefulWidget {
  const _AssistantBubble({
    super.key,
    required this.text,
    this.reasoning,
    this.reasoningMs,
    this.selectable = true,
  });

  final String text;
  final String? reasoning;
  final int? reasoningMs;

  /// 已落库的消息可长按选取；流式草稿关闭。
  final bool selectable;

  @override
  State<_AssistantBubble> createState() => _AssistantBubbleState();
}

class _AssistantBubbleState extends State<_AssistantBubble> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final reasoning = widget.reasoning;
    if (reasoning == null || reasoning.isEmpty) {
      return _bubble(
        context,
        text: widget.text,
        alignment: Alignment.centerLeft,
        color: AppColors.tone1,
        radius: _assistantRadius,
        selectable: widget.selectable,
      );
    }
    // 思考正文与回复正文包在同一个 SelectionArea 里，可跨段连续选取。
    Widget body = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (_expanded)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxWidth: MediaQuery.sizeOf(context).width * 0.82,
              ),
              child: Text(reasoning, style: _reasoningTextStyle),
            ),
          ),
        _bubble(
          context,
          text: widget.text,
          alignment: Alignment.centerLeft,
          color: AppColors.tone1,
          radius: _assistantRadius,
          selectable: false,
        ),
      ],
    );
    if (widget.selectable) {
      // 复制时把选区还原成原文：优先按回复正文的 Markdown 块定位，
      // 选到思考区时按行定位，都对不上才退回整条消息。
      body = SourceSelectionArea(
        resolveCopy: (selected) =>
            resolveMarkdownSelection(widget.text, selected) ??
            (_expanded ? resolvePlainSelection(reasoning, selected) : null) ??
            (_expanded ? '$reasoning\n\n${widget.text}' : widget.text),
        child: body,
      );
    }
    return Align(
      alignment: Alignment.centerLeft,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          _ReasoningHeader(
            label: _reasoningLabel(widget.reasoningMs),
            expanded: _expanded,
            onTap: () => setState(() => _expanded = !_expanded),
          ),
          body,
        ],
      ),
    );
  }
}

/// 流式过程中的思考块：正文还没到 → 实时灰字；正文一到 → 收成一行耗时并可点开。
class _StreamingReasoning extends StatefulWidget {
  const _StreamingReasoning({required this.text, this.reasoningMs});

  final String text;
  final int? reasoningMs;

  @override
  State<_StreamingReasoning> createState() => _StreamingReasoningState();
}

class _StreamingReasoningState extends State<_StreamingReasoning> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          _ReasoningHeader(
            label: _reasoningLabel(widget.reasoningMs),
            expanded: _expanded,
            onTap: () => setState(() => _expanded = !_expanded),
          ),
          if (_expanded)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  maxWidth: MediaQuery.sizeOf(context).width * 0.82,
                ),
                child: Text(widget.text, style: _reasoningTextStyle),
              ),
            ),
        ],
      ),
    );
  }
}

/// 「已思考 12.3s」折叠行：图标 + 文案 + 展开箭头。
class _ReasoningHeader extends StatelessWidget {
  const _ReasoningHeader({
    required this.label,
    required this.expanded,
    required this.onTap,
  });

  final String label;
  final bool expanded;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.psychology_outlined,
              size: 13,
              color: AppColors.textMuted,
            ),
            const SizedBox(width: 4),
            Text(label, style: _reasoningLabelStyle),
            Icon(
              expanded ? Icons.expand_less : Icons.expand_more,
              size: 14,
              color: AppColors.textMuted,
            ),
          ],
        ),
      ),
    );
  }
}

String _reasoningLabel(int? ms) {
  // 思考与正文落在同一个分片里时耗时可能为 0，此时不显示时长。
  if (ms == null || ms == 0) return '已思考';
  if (ms < 1000) return '已思考 ${ms}ms';
  return '已思考 ${(ms / 1000).toStringAsFixed(1)}s';
}

/// 流式过程中的思考块：实时灰色小字，正文到达后由气泡折叠态接管。
class _ReasoningBubble extends StatelessWidget {
  const _ReasoningBubble({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Align(
        alignment: Alignment.centerLeft,
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: MediaQuery.sizeOf(context).width * 0.82,
          ),
          child: Text(text, style: _reasoningTextStyle),
        ),
      ),
    );
  }
}

const BorderRadius _assistantRadius = BorderRadius.only(
  topLeft: Radius.circular(14),
  topRight: Radius.circular(14),
  bottomLeft: Radius.circular(4),
  bottomRight: Radius.circular(14),
);

Widget _bubble(
  BuildContext context, {
  required String text,
  required Alignment alignment,
  required Color color,
  required BorderRadius radius,
  // 用户输入按原样展示：`# 标题`、`- 项` 这类字面内容不该被改写。
  bool markdown = true,
  bool selectable = true,
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
          child: markdown
              ? MarkdownView(
                  text: text,
                  selectable: selectable,
                  style: _bubbleTextStyle,
                )
              : (selectable
                    ? SourceSelectionArea(
                        resolveCopy: (selected) =>
                            resolvePlainSelection(text, selected) ?? text,
                        child: Text(text, style: _bubbleTextStyle),
                      )
                    : Text(text, style: _bubbleTextStyle)),
        ),
      ),
    ),
  );
}

const TextStyle _bubbleTextStyle = TextStyle(
  color: AppColors.textPrimary,
  fontSize: 15,
  height: 1.35,
);

const TextStyle _usageStyle = TextStyle(
  fontSize: 11,
  color: AppColors.textMuted,
);

/// 「已思考 12.3s」折叠行的文字样式。
const TextStyle _reasoningLabelStyle = TextStyle(
  fontSize: 12,
  color: AppColors.textMuted,
);

/// 思考正文样式：灰色小字，与正式回答拉开层级。
const TextStyle _reasoningTextStyle = TextStyle(
  fontSize: 13,
  height: 1.45,
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
