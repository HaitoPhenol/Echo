import 'package:flutter/widgets.dart';

import '../services/chat_store.dart';
import 'ai_api_client.dart';
import 'ai_config_store.dart';

/// 内置 AI 助手的会话标识与展示文案（会话固定存在于聊天列表）。
abstract final class AiConversation {
  /// 会话固定 id：AI 对话与普通聊天共用同一套仓储/列表。
  static const String id = 'ai-assistant';

  /// 会话列表行昵称。
  static const String nickname = 'AI 助手';

  /// 还没有任何消息时的列表预览。
  static const String idlePreview = '开始和 AI 对话';

  /// 消息区空态提示。
  static const String emptyHint = '有什么可以帮你？';

  /// 未配置模型时的提示。
  static const String unconfiguredHint = '请先在设置里配置 AI 模型';

  /// 参与请求上下文的历史消息条数上限（含本次用户消息）。
  static const int historyLimit = 40;
}

/// 一次回复的 token 用量。
@immutable
class AiChatUsage {
  const AiChatUsage({
    this.promptTokens,
    this.completionTokens,
    this.totalTokens,
    this.cachedTokens,
  });

  final int? promptTokens;
  final int? completionTokens;
  final int? totalTokens;

  /// 命中缓存的输入 token 数（服务端未返回时为 null）。
  final int? cachedTokens;

  bool get isEmpty =>
      promptTokens == null &&
      completionTokens == null &&
      totalTokens == null &&
      cachedTokens == null;

  /// 缓存命中率（0~1）；缺任一数据时为 null。
  double? get cacheHitRate {
    final cached = cachedTokens;
    final prompt = promptTokens;
    if (cached == null || prompt == null || prompt <= 0) return null;
    return cached / prompt;
  }

  /// 展示文案：`↑12 · ↓34 · Σ46 · ⚡44%`（缺项省略）。
  String get label {
    final rate = cacheHitRate;
    final parts = <String>[
      if (promptTokens != null) '↑$promptTokens',
      if (completionTokens != null) '↓$completionTokens',
      if (totalTokens != null) 'Σ$totalTokens',
      if (rate != null) '⚡${(rate * 100).round()}%',
    ];
    return parts.join(' · ');
  }
}

/// AI 对话编排器：两个入口（AI 条对话框、聊天页全屏对话）共用。
///
/// 消息实体落在 [ChatStore] 的 [AiConversation.id] 会话里（持久化、
/// 列表预览、未读/已读都由聊天仓储统一承担）；本类只负责：
/// - 发送前校验配置、把用户消息写入会话；
/// - 驱动 [AiApiClient.streamChat] 并把增量正文暴露成 [draft]；
/// - 整段结束后把助手回复写入同一会话；
/// - 记录最近一次用量与错误文案，供两处 UI 展示。
class AiChatController extends ChangeNotifier {
  AiChatController({
    required this.chatStore,
    required this.configStore,
    AiApiClient? client,
  }) : _client = client ?? AiApiClient() {
    configStore.addListener(_handleConfigChanged);
  }

  final ChatStore chatStore;
  final AiConfigStore configStore;
  final AiApiClient _client;

  bool _streaming = false;
  String _draft = '';
  String _reasoningDraft = '';
  int? _reasoningMs;
  DateTime? _reasoningStartedAt;
  String? _lastError;
  AiChatUsage? _lastUsage;
  bool _disposed = false;

  /// 是否正在等待/接收回复。
  bool get isStreaming => _streaming;

  /// 正在流入的助手正文（尚未落库）；空闲时为空串。
  String get draft => _draft;

  /// 正在流入的思考正文（推理模型）；空闲或模型不支持时为空串。
  String get reasoningDraft => _reasoningDraft;

  /// 本轮思考耗时（毫秒）：首个思考增量到首个正文增量；未结算时为 null。
  int? get reasoningMs => _reasoningMs;

  /// 最近一次失败的可读说明；发送成功或下次发送时清空。
  String? get lastError => _lastError;

  /// 最近一次回复的 token 用量；没拿到用量时为 null。
  AiChatUsage? get lastUsage => _lastUsage;

  /// 当前是否有可用的默认模型配置。
  bool get isConfigured => configStore.activeProfile != null;

  /// 是否可以发送（空闲 + 已配置模型）。
  bool get canSend => !_streaming && isConfigured;

  void _handleConfigChanged() {
    if (!_disposed) notifyListeners();
  }

  /// 发送一条用户消息并流式接收回复；空文本/重复发送/未配置时无副作用。
  Future<void> send(String rawText) async {
    final text = rawText.trim();
    if (text.isEmpty || _streaming) return;
    final profile = configStore.activeProfile;
    if (profile == null) {
      _lastError = AiConversation.unconfiguredHint;
      notifyListeners();
      return;
    }

    // 固定会话不存在时补建（独立测试只持有裸 ChatStore 的情况）。
    chatStore.ensureConversation(
      id: AiConversation.id,
      nickname: AiConversation.nickname,
      preview: AiConversation.idlePreview,
    );
    chatStore.send(AiConversation.id, text);
    _streaming = true;
    _draft = '';
    _reasoningDraft = '';
    _reasoningMs = null;
    _reasoningStartedAt = null;
    _lastError = null;
    _lastUsage = null;
    notifyListeners();

    final history = _buildHistory();
    try {
      final result = await _client.streamChat(
        profile: profile,
        messages: history,
        onDelta: (delta) {
          if (_disposed) return;
          // 正文一开始到达即视为思考结束：只结算一次，否则正文流多久，
          // 思考耗时就跟着涨多久。
          final startedAt = _reasoningStartedAt;
          if (startedAt != null) {
            _reasoningMs = DateTime.now()
                .difference(startedAt)
                .inMilliseconds;
            _reasoningStartedAt = null;
          }
          _draft += delta;
          notifyListeners();
        },
        onReasoning: (delta) {
          if (_disposed) return;
          _reasoningStartedAt ??= DateTime.now();
          _reasoningDraft += delta;
          notifyListeners();
        },
      );
      if (_disposed) return;
      final reply = result.text.trim();
      if (reply.isEmpty) {
        _lastError = '模型没有返回内容';
      } else {
        _appendReply(reply, reasoning: result.reasoning);
        final usage = AiChatUsage(
          promptTokens: result.promptTokens,
          completionTokens: result.completionTokens,
          totalTokens: result.totalTokens,
          cachedTokens: result.cachedTokens,
        );
        if (!usage.isEmpty) _lastUsage = usage;
      }
    } on AiChatException catch (error) {
      if (_disposed) return;
      // 已收到的半段正文保留落库，避免用户看着它消失。
      _appendReply(_draft, reasoning: _reasoningDraft);
      _lastError = error.message;
    } catch (error) {
      if (_disposed) return;
      _appendReply(_draft, reasoning: _reasoningDraft);
      _lastError = '请求失败：$error';
    } finally {
      if (!_disposed) {
        _streaming = false;
        _draft = '';
        _reasoningDraft = '';
        notifyListeners();
      }
    }
  }

  /// 把助手正文写回 AI 会话。
  ///
  /// 流式期间用户可能把 AI 会话删掉：此时无处可落，直接丢弃，
  /// 也不重新创建——删掉的行不该被一条迟到的回复拉回来。
  void _appendReply(String text, {String? reasoning}) {
    final body = text.trim();
    if (body.isEmpty) return;
    if (chatStore.conversationOf(AiConversation.id) == null) return;
    final thought = reasoning?.trim();
    chatStore.appendIncoming(
      AiConversation.id,
      body,
      reasoning: (thought == null || thought.isEmpty) ? null : thought,
      reasoningMs: (thought == null || thought.isEmpty) ? null : _reasoningMs,
    );
  }

  /// 用会话内最近 [AiConversation.historyLimit] 条消息拼请求上下文。
  List<AiPromptMessage> _buildHistory() {
    final page = chatStore.messagesOf(
      AiConversation.id,
      limit: AiConversation.historyLimit,
    );
    return [
      for (final message in page.items.reversed)
        AiPromptMessage(
          role: message.direction == ChatDirection.outgoing
              ? 'user'
              : 'assistant',
          content: message.text,
        ),
    ];
  }

  @override
  void notifyListeners() {
    if (_disposed) return;
    super.notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    configStore.removeListener(_handleConfigChanged);
    super.dispose();
  }
}

/// 向子树提供 [AiChatController]（与 ChatStoreScope 同范式）。
class AiChatScope extends InheritedNotifier<AiChatController> {
  const AiChatScope({
    super.key,
    required AiChatController controller,
    required super.child,
  }) : super(notifier: controller);

  /// 取 AI 对话编排器；缺失即装配错误。
  static AiChatController of(BuildContext context) {
    final controller = maybeOf(context);
    assert(controller != null, '子树中缺少 AiChatScope');
    return controller!;
  }

  /// 取编排器；scope 之外返回 null。
  static AiChatController? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<AiChatScope>()?.notifier;
}
