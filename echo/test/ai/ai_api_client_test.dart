import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:echo/src/ai/ai_api_client.dart';
import 'package:echo/src/ai/ai_config.dart';
import 'package:flutter_test/flutter_test.dart';

/// 记录请求并返回预设结果的假传输层。
class _FakeTransport implements AiHttpTransport {
  _FakeTransport({this.response, this.error});

  AiHttpResponse? response;
  Object? error;

  Uri? lastUri;
  Map<String, String>? lastHeaders;
  String? lastBody;
  Duration? lastTimeout;

  @override
  Future<AiHttpResponse> post({
    required Uri uri,
    required Map<String, String> headers,
    required String body,
    required Duration timeout,
  }) async {
    lastUri = uri;
    lastHeaders = headers;
    lastBody = body;
    lastTimeout = timeout;
    final failure = error;
    if (failure != null) throw failure;
    return response ?? const AiHttpResponse(statusCode: 200, body: '{}');
  }
}

const _profile = AiModelProfile(
  id: 'p1',
  name: '主力',
  baseUrl: 'https://api.example.com/v1',
  apiKey: 'sk-1234567890abcd',
  model: 'gpt-4o-mini',
  reasoningEffort: AiReasoningEffort.medium,
  timeoutSeconds: 30,
);

/// 记录请求并按块吐出预设 SSE 文本的假流式传输层。
class _FakeStreamTransport implements AiStreamTransport {
  _FakeStreamTransport({
    this.chunks = const <String>[],
    this.statusCode = 200,
    this.stream,
  });

  final List<String> chunks;
  final int statusCode;

  /// 需要自己控制节奏时直接给流（优先级高于 [chunks]）。
  final Stream<String>? stream;

  Uri? lastUri;
  Map<String, String>? lastHeaders;
  String? lastBody;

  @override
  Future<AiStreamResponse> postStream({
    required Uri uri,
    required Map<String, String> headers,
    required String body,
    required Duration timeout,
  }) async {
    lastUri = uri;
    lastHeaders = headers;
    lastBody = body;
    return AiStreamResponse(
      statusCode: statusCode,
      chunks: stream ?? Stream<String>.fromIterable(chunks),
    );
  }
}

void main() {
  test('成功响应返回延迟与成功说明', () async {
    final transport = _FakeTransport(
      response: const AiHttpResponse(statusCode: 200, body: '{}'),
    );
    final result = await AiApiClient(
      transport: transport,
    ).testConnection(_profile);

    expect(result.ok, isTrue);
    expect(result.latencyMs, isNotNull);
    expect(result.message, contains('连接成功'));

    // 请求口径：/chat/completions、Bearer、最小非流式请求。
    expect(
      transport.lastUri?.toString(),
      'https://api.example.com/v1/chat/completions',
    );
    expect(transport.lastHeaders?['Authorization'], 'Bearer sk-1234567890abcd');
    expect(transport.lastTimeout, const Duration(seconds: 30));
    final body = jsonDecode(transport.lastBody!) as Map<String, dynamic>;
    expect(body['model'], 'gpt-4o-mini');
    expect(body['stream'], false);
    expect(body['max_tokens'], 1);
  });

  test('API Key 为空时不发送 Authorization 头', () async {
    final transport = _FakeTransport();
    await AiApiClient(transport: transport).testConnection(
      _profile.copyWith(apiKey: '  '),
    );
    expect(transport.lastHeaders?.containsKey('Authorization'), isFalse);
  });

  test('HTTP 401 提取 OpenAI 错误信息', () async {
    final transport = _FakeTransport(
      response: const AiHttpResponse(
        statusCode: 401,
        body: '{"error":{"message":"Invalid API key"}}',
      ),
    );
    final result = await AiApiClient(
      transport: transport,
    ).testConnection(_profile);

    expect(result.ok, isFalse);
    expect(result.message, contains('HTTP 401'));
    expect(result.message, contains('Invalid API key'));
  });

  test('非 JSON 错误体截断展示', () async {
    final transport = _FakeTransport(
      response: AiHttpResponse(
        statusCode: 500,
        body: 'x' * 300,
      ),
    );
    final result = await AiApiClient(
      transport: transport,
    ).testConnection(_profile);

    expect(result.ok, isFalse);
    expect(result.message, contains('HTTP 500'));
    expect(result.message, contains('…'));
  });

  test('网络不可达与超时给出可读原因', () async {
    final unreachable = _FakeTransport(
      error: const SocketException('Network is unreachable'),
    );
    final first = await AiApiClient(
      transport: unreachable,
    ).testConnection(_profile);
    expect(first.ok, isFalse);
    expect(first.message, contains('网络不可达'));

    final timeout = _FakeTransport(error: TimeoutException('slow'));
    final second = await AiApiClient(
      transport: timeout,
    ).testConnection(_profile);
    expect(second.ok, isFalse);
    expect(second.message, contains('请求超时'));
  });

  test('本地校验失败时不发请求', () async {
    final transport = _FakeTransport();

    final badUrl = await AiApiClient(transport: transport).testConnection(
      _profile.copyWith(baseUrl: 'api.example.com/v1'),
    );
    expect(badUrl.ok, isFalse);
    expect(badUrl.message, contains('http://'));

    final noModel = await AiApiClient(
      transport: transport,
    ).testConnection(_profile.copyWith(model: ' '));
    expect(noModel.ok, isFalse);
    expect(noModel.message, contains('模型名'));

    expect(transport.lastUri, isNull);
  });

  test('已填完整路径的 Base URL 不重复追加', () async {
    final transport = _FakeTransport();
    await AiApiClient(transport: transport).testConnection(
      _profile.copyWith(
        baseUrl: 'https://api.example.com/v1/chat/completions',
      ),
    );
    expect(
      transport.lastUri?.toString(),
      'https://api.example.com/v1/chat/completions',
    );
  });

  group('streamChat', () {
    test('SSE 增量拼接正文并解析用量与模型名', () async {
      final transport = _FakeStreamTransport(
        chunks: const [
          'data: {"model":"gpt-4o-mini","choices":[{"delta":{"content":"你"}}]}\n',
          '\ndata: {"choices":[{"delta":{"content":"好"}}]}\n\n',
          'data: {"choices":[{"delta":{"content":"！"}}]}\n\n',
          'data: {"choices":[],"usage":{"prompt_tokens":12,'
              '"completion_tokens":3,"total_tokens":15,'
              '"prompt_tokens_details":{"cached_tokens":5}}}\n\n',
          'data: [DONE]\n\n',
        ],
      );
      final deltas = <String>[];
      final result = await AiApiClient(
        streamTransport: transport,
      ).streamChat(
        profile: _profile,
        messages: const [
          AiPromptMessage(role: 'user', content: '你好'),
        ],
        onDelta: deltas.add,
      );

      expect(result.text, '你好！');
      expect(deltas, ['你', '好', '！']);
      expect(result.model, 'gpt-4o-mini');
      expect(result.promptTokens, 12);
      expect(result.completionTokens, 3);
      expect(result.totalTokens, 15);
      // OpenAI 口径的缓存命中数（prompt_tokens_details.cached_tokens）。
      expect(result.cachedTokens, 5);

      // 请求口径：/chat/completions、Bearer、stream + 推理强度。
      expect(
        transport.lastUri?.toString(),
        'https://api.example.com/v1/chat/completions',
      );
      expect(
        transport.lastHeaders?['Authorization'],
        'Bearer sk-1234567890abcd',
      );
      final body = jsonDecode(transport.lastBody!) as Map<String, dynamic>;
      expect(body['stream'], isTrue);
      expect(body['reasoning_effort'], 'medium');
      expect(body['temperature'], 0.7);
      expect(body['max_tokens'], 1024);
      expect((body['messages'] as List).single, {
        'role': 'user',
        'content': '你好',
      });
    });

    test('DeepSeek 口径的 prompt_cache_hit_tokens 也能解析', () async {
      final transport = _FakeStreamTransport(
        chunks: const [
          'data: {"choices":[{"delta":{"content":"好"}}]}\n\n',
          'data: {"choices":[],"usage":{"prompt_tokens":20,'
              '"completion_tokens":2,"total_tokens":22,'
              '"prompt_cache_hit_tokens":16}}\n\n',
          'data: [DONE]\n\n',
        ],
      );
      final result = await AiApiClient(
        streamTransport: transport,
      ).streamChat(
        profile: _profile,
        messages: const [
          AiPromptMessage(role: 'user', content: 'hi'),
        ],
      );
      expect(result.cachedTokens, 16);
    });

    test('非 2xx 时抛出带服务端说明的异常', () async {
      final transport = _FakeStreamTransport(
        statusCode: 401,
        chunks: const [
          '{"error":{"message":"Invalid API key"}}',
        ],
      );
      await expectLater(
        AiApiClient(streamTransport: transport).streamChat(
          profile: _profile,
          messages: const [
            AiPromptMessage(role: 'user', content: 'ping'),
          ],
        ),
        throwsA(
          isA<AiChatException>().having(
            (e) => e.message,
            'message',
            allOf(contains('HTTP 401'), contains('Invalid API key')),
          ),
        ),
      );
    });

    test('兼容服务忽略 stream 直接回整段 JSON 时走兜底解析', () async {
      final transport = _FakeStreamTransport(
        chunks: const [
          '{"model":"m","choices":[{"message":{"role":"assistant",'
              '"content":"整段回复"}}],"usage":{"total_tokens":7}}',
        ],
      );
      final result = await AiApiClient(
        streamTransport: transport,
      ).streamChat(
        profile: _profile,
        messages: const [
          AiPromptMessage(role: 'user', content: 'hi'),
        ],
      );
      expect(result.text, '整段回复');
      expect(result.totalTokens, 7);
    });

    test('[DONE] 之后对端不断流也立即收尾，不误判为超时', () async {
      final source = StreamController<String>();
      addTearDown(source.close);
      final transport = _FakeStreamTransport(stream: source.stream);

      final future = AiApiClient(
        streamTransport: transport,
      ).streamChat(
        profile: _profile,
        messages: const [
          AiPromptMessage(role: 'user', content: 'hi'),
        ],
      );
      source
        ..add('data: {"choices":[{"delta":{"content":"好"}}]}\n\n')
        ..add('data: [DONE]\n\n');

      // 对端发完 [DONE] 后既不关流也不再发数据：正常实现应立即返回。
      final result = await future.timeout(const Duration(seconds: 2));
      expect(result.text, '好');

      // 主动退出订阅后不挂在源流上（否则连接泄漏）。
      await Future<void>.delayed(Duration.zero);
      expect(source.hasListener, isFalse);
    });

    test('未配置模型时不发请求', () async {
      final transport = _FakeStreamTransport();
      final client = AiApiClient(streamTransport: transport);
      await expectLater(
        client.streamChat(
          profile: _profile.copyWith(model: ' '),
          messages: const [
            AiPromptMessage(role: 'user', content: 'hi'),
          ],
        ),
        throwsA(isA<AiChatException>()),
      );
      expect(transport.lastUri, isNull);
    });
  });
}
