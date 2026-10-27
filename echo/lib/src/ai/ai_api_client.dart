import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'ai_config.dart';

/// 一次 HTTP 响应（只保留连通测试需要的字段）。
class AiHttpResponse {
  const AiHttpResponse({required this.statusCode, required this.body});

  final int statusCode;
  final String body;
}

/// 连通测试的传输层抽象：默认走 `dart:io` HttpClient，
/// 测试可注入 fake 以避免真实网络。
abstract interface class AiHttpTransport {
  Future<AiHttpResponse> post({
    required Uri uri,
    required Map<String, String> headers,
    required String body,
    required Duration timeout,
  });
}

/// 生产实现：创建短生命周期 HttpClient，读完响应即关闭。
class HttpClientTransport implements AiHttpTransport {
  const HttpClientTransport();

  @override
  Future<AiHttpResponse> post({
    required Uri uri,
    required Map<String, String> headers,
    required String body,
    required Duration timeout,
  }) async {
    final client = HttpClient()..connectionTimeout = timeout;
    try {
      final request = await client.postUrl(uri).timeout(timeout);
      headers.forEach(request.headers.set);
      request.add(utf8.encode(body));
      final response = await request.close().timeout(timeout);
      final text = await response
          .transform(utf8.decoder)
          .join()
          .timeout(timeout);
      return AiHttpResponse(statusCode: response.statusCode, body: text);
    } finally {
      client.close(force: true);
    }
  }
}

/// 连通测试结果。
class AiConnectivityResult {
  const AiConnectivityResult({
    required this.ok,
    required this.message,
    this.latencyMs,
  });

  final bool ok;

  /// 面向用户的说明（成功含延迟；失败含原因）。
  final String message;

  /// 成功时的往返耗时（毫秒）。
  final int? latencyMs;

  static AiConnectivityResult failure(String message) =>
      AiConnectivityResult(ok: false, message: message);
}

/// OpenAI 兼容 API 的最小客户端（当前仅连通测试）。
///
/// 请求口径：`POST {baseUrl}/chat/completions`，非流式、
/// `max_tokens: 1` 的最小消息。成功只代表网络、鉴权、端点与
/// 模型名可用，不校验回复内容。
class AiApiClient {
  AiApiClient({AiHttpTransport? transport})
    : _transport = transport ?? const HttpClientTransport();

  final AiHttpTransport _transport;

  /// 对一条配置发起最小连通请求。
  Future<AiConnectivityResult> testConnection(AiModelProfile profile) async {
    final baseUrl = profile.baseUrl.trim();
    if (!baseUrl.startsWith('http://') && !baseUrl.startsWith('https://')) {
      return AiConnectivityResult.failure('Base URL 需以 http:// 或 https:// 开头');
    }
    if (profile.model.trim().isEmpty) {
      return AiConnectivityResult.failure('请先填写模型名称');
    }
    final uri = Uri.tryParse(resolveChatCompletionsUrl(baseUrl));
    if (uri == null || !uri.hasScheme || uri.host.isEmpty) {
      return AiConnectivityResult.failure('Base URL 格式无效');
    }

    final headers = <String, String>{
      'Content-Type': 'application/json',
      'Accept': 'application/json',
      if (profile.apiKey.trim().isNotEmpty)
        'Authorization': 'Bearer ${profile.apiKey.trim()}',
    };
    final body = jsonEncode({
      'model': profile.model.trim(),
      'messages': [
        {'role': 'user', 'content': 'ping'},
      ],
      'max_tokens': 1,
      'stream': false,
    });
    final timeout = Duration(seconds: profile.timeoutSeconds);

    final stopwatch = Stopwatch()..start();
    try {
      final response = await _transport.post(
        uri: uri,
        headers: headers,
        body: body,
        timeout: timeout,
      );
      stopwatch.stop();
      if (response.statusCode >= 200 && response.statusCode < 300) {
        final latency = stopwatch.elapsedMilliseconds;
        return AiConnectivityResult(
          ok: true,
          latencyMs: latency,
          message: '连接成功 · ${latency}ms',
        );
      }
      return AiConnectivityResult.failure(
        'HTTP ${response.statusCode}：${_extractErrorMessage(response.body)}',
      );
    } on TimeoutException {
      return AiConnectivityResult.failure(
        '请求超时（${profile.timeoutSeconds}s），请检查地址或网络',
      );
    } on SocketException catch (error) {
      return AiConnectivityResult.failure('网络不可达：${error.message}');
    } on HandshakeException catch (error) {
      return AiConnectivityResult.failure('TLS 握手失败：${error.message}');
    } on HttpException catch (error) {
      return AiConnectivityResult.failure('请求失败：${error.message}');
    } on FormatException {
      return AiConnectivityResult.failure('响应格式异常');
    }
  }

  /// 从错误响应体里提取可读信息：OpenAI 口径是
  /// `{"error":{"message":"..."}}`，其余按截断文本兜底。
  String _extractErrorMessage(String body) {
    final text = body.trim();
    if (text.isEmpty) return '服务端未返回内容';
    try {
      final decoded = jsonDecode(text);
      if (decoded is Map) {
        final error = decoded['error'];
        if (error is Map && error['message'] is String) {
          return error['message'] as String;
        }
        if (decoded['message'] is String) {
          return decoded['message'] as String;
        }
      }
    } catch (_) {
      // 非 JSON：走文本兜底。
    }
    return text.length > 160 ? '${text.substring(0, 160)}…' : text;
  }
}
