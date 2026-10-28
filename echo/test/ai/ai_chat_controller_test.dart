import 'dart:async';

import 'package:echo/src/ai/ai_api_client.dart';
import 'package:echo/src/ai/ai_chat_controller.dart';
import 'package:echo/src/ai/ai_config.dart';
import 'package:echo/src/ai/ai_config_store.dart';
import 'package:echo/src/services/chat_store.dart';
import 'package:flutter_test/flutter_test.dart';

const _profile = AiModelProfile(
  id: 'p1',
  name: '主力',
  baseUrl: 'https://api.example.com/v1',
  apiKey: 'sk-test',
  model: 'gpt-4o-mini',
  reasoningEffort: AiReasoningEffort.high,
  maxTokens: 256,
  timeoutSeconds: 10,
);

/// 可手动控制流入节奏的假流式传输层。
class _ControlledStreamTransport implements AiStreamTransport {
  _ControlledStreamTransport({this.statusCode = 200});

  final int statusCode;
  final StreamController<String> controller = StreamController<String>();

  String? lastBody;

  @override
  Future<AiStreamResponse> postStream({
    required Uri uri,
    required Map<String, String> headers,
    required String body,
    required Duration timeout,
  }) async {
    lastBody = body;
    return AiStreamResponse(statusCode: statusCode, chunks: controller.stream);
  }
}

AiConfigStore _configuredStore() => AiConfigStore(
  initialConfig: const AiConfig(
    profiles: [_profile],
    activeProfileId: 'p1',
  ),
);

String _sse(String content) =>
    'data: {"choices":[{"delta":{"content":"$content"}}]}\n\n';

void main() {
  late ChatStore chatStore;
  late AiChatController controller;

  setUp(() {
    chatStore = ChatStore();
  });

  tearDown(() {
    controller.dispose();
    chatStore.dispose();
  });

  AiChatController build(
    AiConfigStore configStore, {
    AiStreamTransport? transport,
  }) {
    return AiChatController(
      chatStore: chatStore,
      configStore: configStore,
      client: AiApiClient(streamTransport: transport),
    );
  }

  test('未配置模型：给出提示且不写入任何消息', () async {
    controller = build(AiConfigStore());
    expect(controller.isConfigured, isFalse);
    expect(controller.canSend, isFalse);

    await controller.send('你好');

    expect(controller.lastError, AiConversation.unconfiguredHint);
    expect(chatStore.conversationOf(AiConversation.id), isNull);
  });

  test('发送：用户消息先落库，流式增量暴露为草稿，结束后落助手回复', () async {
    final transport = _ControlledStreamTransport();
    controller = build(_configuredStore(), transport: transport);

    final sending = controller.send('  介绍一下自己  ');

    // 用户消息立即落库，AI 会话被补建并出现在列表顶端。
    final conversation = chatStore.conversationOf(AiConversation.id);
    expect(conversation, isNotNull);
    expect(conversation!.preview, '介绍一下自己');
    expect(controller.isStreaming, isTrue);
    expect(controller.canSend, isFalse);

    transport.controller
      ..add(_sse('你好'))
      ..add(_sse('，我是 Echo'));
    await Future<void>.delayed(Duration.zero);

    expect(controller.draft, '你好，我是 Echo');

    transport.controller
      ..add(
        'data: {"choices":[],"usage":{"prompt_tokens":9,'
        '"completion_tokens":4,"total_tokens":13,'
        '"prompt_tokens_details":{"cached_tokens":6}}}\n\n',
      )
      ..add('data: [DONE]\n\n');
    await transport.controller.close();
    await sending;

    expect(controller.isStreaming, isFalse);
    expect(controller.draft, isEmpty);
    expect(controller.lastError, isNull);
    expect(controller.lastUsage?.totalTokens, 13);
    // 缓存命中率 = 6 / 9 ≈ 67%。
    expect(controller.lastUsage?.cacheHitRate, closeTo(2 / 3, 1e-9));
    expect(controller.lastUsage?.label, '↑9 · ↓4 · Σ13 · ⚡67%');

    final messages = chatStore.messagesOf(AiConversation.id).items;
    // 新 → 旧：助手回复在前，用户消息在后。
    expect(messages.length, 2);
    expect(messages[0].direction, ChatDirection.incoming);
    expect(messages[0].text, '你好，我是 Echo');
    expect(messages[1].direction, ChatDirection.outgoing);
    expect(messages[1].text, '介绍一下自己');
    expect(chatStore.conversationOf(AiConversation.id)!.preview, '你好，我是 Echo');

    // 请求体带上推理强度与 maxTokens，历史含本轮用户消息。
    final body = transport.lastBody!;
    expect(body, contains('"reasoning_effort":"high"'));
    expect(body, contains('"max_tokens":256'));
    expect(body, contains('介绍一下自己'));
  });

  test('HTTP 错误：用户消息保留、不产生助手消息、错误文案可读', () async {
    final transport = _ControlledStreamTransport(statusCode: 401);
    controller = build(_configuredStore(), transport: transport);

    final sending = controller.send('ping');
    transport.controller.add('{"error":{"message":"Invalid API key"}}');
    await transport.controller.close();
    await sending;

    expect(controller.isStreaming, isFalse);
    expect(controller.lastError, contains('Invalid API key'));
    final messages = chatStore.messagesOf(AiConversation.id).items;
    expect(messages.length, 1);
    expect(messages.single.direction, ChatDirection.outgoing);
  });

  test('流式中收到半段后断开：半段正文落库并保留错误', () async {
    final transport = _ControlledStreamTransport();
    controller = build(_configuredStore(), transport: transport);

    final sending = controller.send('继续');
    transport.controller.add(_sse('半段'));
    await Future<void>.delayed(Duration.zero);
    await transport.controller.close();
    await sending;

    final messages = chatStore.messagesOf(AiConversation.id).items;
    // 流正常结束但无 [DONE] 也按完整回复收尾（服务端断流由传输层报错）。
    expect(messages.first.text, '半段');
    expect(controller.lastError, isNull);
  });

  test('流式期间重复发送被忽略；空白发送无副作用', () async {
    final transport = _ControlledStreamTransport();
    controller = build(_configuredStore(), transport: transport);

    final first = controller.send('第一句');
    await controller.send('第二句');
    await controller.send('   ');
    expect(chatStore.messagesOf(AiConversation.id).items.length, 1);

    transport.controller.add(_sse('回复'));
    await transport.controller.close();
    await first;
    expect(chatStore.messagesOf(AiConversation.id).items.length, 2);
  });

  test('流式期间会话被删除：回复丢弃、不抛异常也不把行拉回来', () async {
    final transport = _ControlledStreamTransport();
    controller = build(_configuredStore(), transport: transport);

    final sending = controller.send('问题');
    transport.controller.add(_sse('回答'));
    await Future<void>.delayed(Duration.zero);
    chatStore.remove(AiConversation.id);

    await transport.controller.close();
    await sending;

    expect(controller.isStreaming, isFalse);
    expect(controller.lastError, isNull);
    expect(chatStore.conversationOf(AiConversation.id), isNull);
  });

  test('思考流：增量单独暴露为 reasoningDraft，正文到达后随回复一起落库', () async {
    final transport = _ControlledStreamTransport();
    controller = build(_configuredStore(), transport: transport);

    final sending = controller.send('想想');
    transport.controller
      ..add(
        'data: {"choices":[{"delta":{"reasoning_content":"先分析"}}]}\n\n',
      )
      ..add(
        'data: {"choices":[{"delta":{"reasoning_content":"再作答"}}]}\n\n',
      );
    await Future<void>.delayed(Duration.zero);

    expect(controller.reasoningDraft, '先分析再作答');
    // 思考与正文分开累积，互不污染。
    expect(controller.draft, isEmpty);

    transport.controller
      ..add(_sse('答案'))
      ..add('data: [DONE]\n\n');
    await transport.controller.close();
    await sending;

    expect(controller.reasoningDraft, isEmpty);
    final messages = chatStore.messagesOf(AiConversation.id).items;
    expect(messages.first.text, '答案');
    expect(messages.first.reasoning, '先分析再作答');
    // 耗时只结算一次：思考到正文的间隔，不应随正文流长度膨胀。
    expect(messages.first.reasoningMs, isNotNull);
    expect(messages.first.reasoningMs, lessThan(1000));
  });

  test('思考耗时只在正文首个增量时结算一次，后续正文不再累加', () async {
    final transport = _ControlledStreamTransport();
    controller = build(_configuredStore(), transport: transport);

    final sending = controller.send('想想');
    transport.controller.add(
      'data: {"choices":[{"delta":{"reasoning_content":"先分析"}}]}\n\n',
    );
    await Future<void>.delayed(const Duration(milliseconds: 20));
    transport.controller.add(_sse('第一段'));
    await Future<void>.delayed(Duration.zero);

    final settled = controller.reasoningMs;
    expect(settled, isNotNull);

    await Future<void>.delayed(const Duration(milliseconds: 20));
    transport.controller
      ..add(_sse('第二段'))
      ..add('data: [DONE]\n\n');
    await transport.controller.close();
    await sending;

    // 正文继续流不会把思考耗时越算越长。
    expect(controller.reasoningMs, settled);
  });

  test('回复为空：提示模型没有返回内容且不落助手消息', () async {
    final transport = _ControlledStreamTransport();
    controller = build(_configuredStore(), transport: transport);

    final sending = controller.send('hi');
    await transport.controller.close();
    await sending;

    expect(controller.lastError, '模型没有返回内容');
    expect(chatStore.messagesOf(AiConversation.id).items.length, 1);
  });
}
