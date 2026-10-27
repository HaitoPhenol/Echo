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
}
