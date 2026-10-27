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

/// 流式响应的传输层抽象：拿到状态码后按块吐出已解码的文本。
///
/// 与 [AiHttpTransport] 分开声明：连通测试的假实现不必同时实现流式，
/// 聊天客户端可单独注入流式 fake。
abstract interface class AiStreamTransport {
  Future<AiStreamResponse> postStream({
    required Uri uri,
    required Map<String, String> headers,
    required String body,
    required Duration timeout,
  });
}

/// 流式响应：HTTP 状态码 + 原始文本块流。
class AiStreamResponse {
  const AiStreamResponse({required this.statusCode, required this.chunks});

  final int statusCode;

  /// UTF-8 解码后的文本块（SSE 的 `data:` 行由客户端解析）。
  final Stream<String> chunks;
}

/// 生产实现：创建短生命周期 HttpClient，读完响应即关闭。
class HttpClientTransport implements AiHttpTransport, AiStreamTransport {
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

  @override
  Future<AiStreamResponse> postStream({
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
      // 响应体读完、出错或被提前取消（收到 [DONE]/超时）时都要关连接。
      final chunks = response
          .transform(utf8.decoder)
          .transform(_ClosingTransformer(() => client.close(force: true)));
      return AiStreamResponse(statusCode: response.statusCode, chunks: chunks);
    } catch (error) {
      client.close(force: true);
      rethrow;
    }
  }
}

/// 流结束、出错或被下游提前取消时执行一次清理（关闭 HttpClient）。
///
/// `StreamTransformer.fromHandlers` 没有取消回调，而收到 `[DONE]` 后
/// 主动 break 会取消订阅——此时不关连接就会漏 socket。
class _ClosingTransformer extends StreamTransformerBase<String, String> {
  _ClosingTransformer(this._onClose);

  final void Function() _onClose;

  @override
  Stream<String> bind(Stream<String> stream) {
    late StreamController<String> controller;
    late StreamSubscription<String> subscription;
    var closed = false;

    void finish() {
      if (closed) return;
      closed = true;
      _onClose();
      controller.close();
    }

    controller = StreamController<String>(
      onListen: () {
        subscription = stream.listen(
          controller.add,
          onError: (Object error, StackTrace stackTrace) {
            if (closed) return;
            closed = true;
            _onClose();
            controller.addError(error, stackTrace);
            controller.close();
          },
          onDone: finish,
        );
      },
      onCancel: () {
        _onClose();
        return subscription.cancel();
      },
    );
    return controller.stream;
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

/// 一次对话请求里的单条上下文消息。
class AiPromptMessage {
  const AiPromptMessage({required this.role, required this.content});

  /// `system` / `user` / `assistant`。
  final String role;
  final String content;

  Map<String, Object?> toJson() => {'role': role, 'content': content};
}

/// 一次流式对话的最终结果（正文 + 用量）。
class AiChatCompletion {
  const AiChatCompletion({
    required this.text,
    this.model = '',
    this.promptTokens,
    this.completionTokens,
    this.totalTokens,
  });

  final String text;
  final String model;
  final int? promptTokens;
  final int? completionTokens;
  final int? totalTokens;
}

/// 对话链路上的可读异常（网络/鉴权/协议错误统一收口）。
class AiChatException implements Exception {
  const AiChatException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// OpenAI 兼容 API 的最小客户端：连通测试 + 流式对话。
///
/// 请求口径：`POST {baseUrl}/chat/completions`；连通测试走非流式
/// `max_tokens: 1` 的最小消息，聊天走 `stream: true` 的 SSE。
class AiApiClient {
  AiApiClient({AiHttpTransport? transport, AiStreamTransport? streamTransport})
    : _transport = transport ?? const HttpClientTransport(),
      _streamTransport = streamTransport ?? const HttpClientTransport();

  final AiHttpTransport _transport;
  final AiStreamTransport _streamTransport;

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

  /// 发起一次流式对话，逐段回调增量正文，最终返回整段与用量。
  ///
  /// 协议：SSE，每行 `data: {json}`，最后一行为 `data: [DONE]`；
  /// 用量可能在末尾的空 choices 块里（`include_usage`）。
  /// 非 SSE 的 JSON 响应（部分兼容服务忽略 stream）作整段兜底解析。
  Future<AiChatCompletion> streamChat({
    required AiModelProfile profile,
    required List<AiPromptMessage> messages,
    void Function(String delta)? onDelta,
  }) async {
    final baseUrl = profile.baseUrl.trim();
    if (!baseUrl.startsWith('http://') && !baseUrl.startsWith('https://')) {
      throw const AiChatException('Base URL 需以 http:// 或 https:// 开头');
    }
    if (profile.model.trim().isEmpty) {
      throw const AiChatException('请先填写模型名称');
    }
    if (messages.isEmpty) {
      throw const AiChatException('消息不能为空');
    }
    final uri = Uri.tryParse(resolveChatCompletionsUrl(baseUrl));
    if (uri == null || !uri.hasScheme || uri.host.isEmpty) {
      throw const AiChatException('Base URL 格式无效');
    }

    final headers = <String, String>{
      'Content-Type': 'application/json',
      'Accept': 'text/event-stream',
      if (profile.apiKey.trim().isNotEmpty)
        'Authorization': 'Bearer ${profile.apiKey.trim()}',
    };
    final body = jsonEncode({
      'model': profile.model.trim(),
      'messages': [for (final m in messages) m.toJson()],
      'temperature': profile.temperature,
      'max_tokens': profile.maxTokens,
      'stream': true,
      'stream_options': {'include_usage': true},
      if (profile.reasoningEffort != AiReasoningEffort.unspecified)
        'reasoning_effort': profile.reasoningEffort.wireValue,
    });
    final timeout = Duration(seconds: profile.timeoutSeconds);

    try {
      final response = await _streamTransport.postStream(
        uri: uri,
        headers: headers,
        body: body,
        timeout: timeout,
      );
      if (response.statusCode < 200 || response.statusCode >= 300) {
        // 错误体可能迟迟不收尾，给读取加同一个超时，避免永久挂住。
        final raw = await response.chunks
            .join()
            .timeout(timeout, onTimeout: () => '');
        throw AiChatException(
          'HTTP ${response.statusCode}：${_extractErrorMessage(raw)}',
        );
      }
      return await _consumeSse(
        response.chunks.timeout(timeout),
        onDelta: onDelta,
      );
    } on AiChatException {
      rethrow;
    } on TimeoutException {
      throw AiChatException('请求超时（${profile.timeoutSeconds}s），请检查地址或网络');
    } on SocketException catch (error) {
      throw AiChatException('网络不可达：${error.message}');
    } on HandshakeException catch (error) {
      throw AiChatException('TLS 握手失败：${error.message}');
    } on HttpException catch (error) {
      throw AiChatException('请求失败：${error.message}');
    } on FormatException {
      throw const AiChatException('响应格式异常');
    }
  }

  /// 解析 SSE 文本块：逐行取 `data:`，拼接 delta.content 与 usage。
  Future<AiChatCompletion> _consumeSse(
    Stream<String> chunks, {
    void Function(String delta)? onDelta,
  }) async {
    final text = StringBuffer();
    final raw = StringBuffer();
    var model = '';
    int? promptTokens;
    int? completionTokens;
    int? totalTokens;
    var sawData = false;
    var pending = '';

    /// 处理一行 SSE；返回 true 表示收到了结束标记 `data: [DONE]`。
    bool handleLine(String line) {
      final trimmed = line.trim();
      if (!trimmed.startsWith('data:')) return false;
      sawData = true;
      final payload = trimmed.substring(5).trim();
      if (payload.isEmpty) return false;
      if (payload == '[DONE]') return true;
      final Map<String, dynamic> decoded;
      try {
        final parsed = jsonDecode(payload);
        if (parsed is! Map) return false;
        decoded = Map<String, dynamic>.from(parsed);
      } catch (_) {
        // 单行坏 JSON 跳过，不影响已收到的正文。
        return false;
      }
      final modelName = decoded['model'];
      if (modelName is String && modelName.isNotEmpty) model = modelName;

      final choices = decoded['choices'];
      if (choices is List && choices.isNotEmpty) {
        final first = choices.first;
        if (first is Map) {
          final delta = first['delta'];
          final content = (delta is Map ? delta['content'] : null) ??
              (first['message'] is Map
                  ? (first['message'] as Map)['content']
                  : null);
          if (content is String && content.isNotEmpty) {
            text.write(content);
            onDelta?.call(content);
          }
        }
      }

      final usage = decoded['usage'];
      if (usage is Map) {
        promptTokens = _intOrNull(usage['prompt_tokens']) ?? promptTokens;
        completionTokens =
            _intOrNull(usage['completion_tokens']) ?? completionTokens;
        totalTokens = _intOrNull(usage['total_tokens']) ?? totalTokens;
      }
      return false;
    }

    var done = false;
    await for (final chunk in chunks) {
      raw.write(chunk);
      pending += chunk;
      final lines = pending.split('\n');
      // 最后一段可能是不完整行，留到下一块再拼。
      pending = lines.removeLast();
      for (final line in lines) {
        if (handleLine(line)) {
          done = true;
          break;
        }
      }
      // 服务端发完 [DONE] 常常不立刻断流：主动退出订阅，
      // 否则后续静默会被 idle 超时误判为整次请求失败。
      if (done) break;
    }
    if (!done) handleLine(pending);

    // 非流式兜底：部分兼容服务忽略 stream，直接回一条完整 JSON。
    if (!sawData && text.isEmpty) {
      final trimmed = raw.toString().trim();
      if (trimmed.startsWith('{')) {
        try {
          final parsed = jsonDecode(trimmed);
          if (parsed is Map) {
            final choices = parsed['choices'];
            if (choices is List && choices.isNotEmpty && choices.first is Map) {
              final first = choices.first as Map;
              final message = first['message'];
              final content = message is Map ? message['content'] : null;
              if (content is String) {
                text.write(content);
                if (content.isNotEmpty) onDelta?.call(content);
              }
              final usage = parsed['usage'];
              if (usage is Map) {
                promptTokens = _intOrNull(usage['prompt_tokens']);
                completionTokens = _intOrNull(usage['completion_tokens']);
                totalTokens = _intOrNull(usage['total_tokens']);
              }
            }
          }
        } catch (_) {
          // 不是完整 JSON：按空回复处理。
        }
      }
    }

    return AiChatCompletion(
      text: text.toString(),
      model: model,
      promptTokens: promptTokens,
      completionTokens: completionTokens,
      totalTokens: totalTokens,
    );
  }

  static int? _intOrNull(Object? value) =>
      value is num ? value.toInt() : null;

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
