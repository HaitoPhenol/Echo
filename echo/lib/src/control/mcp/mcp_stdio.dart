import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'mcp_server.dart';

/// MCP stdio 传输（R4）：stdin 逐行读 → [McpServer] → stdout 逐行写。
///
/// 只做字节流/行边界与冲刷，不含任何协议或业务判断；JSON-RPC 的解析、
/// 错误收敛、权限与审计全在 [McpServer]/[ControlBus]。
///
/// 平台限制：stdin/stdout 只在桌面（Linux/macOS/Windows）或调试宿主
/// 有意义；移动端没有可用的标准输入，入口（bootstrap/main）只在
/// debug 构建带 `--mcp` 时挂载，故移动端保持原样、不启动本传输。
class McpStdioTransport {
  McpStdioTransport({
    required this.server,
    Stdin? stdinStream,
    IOSink? stdoutSink,
    IOSink? stderrSink,
  }) : _stdin = stdinStream ?? stdin,
       _stdout = stdoutSink ?? stdout,
       _stderr = stderrSink ?? stderr;

  final McpServer server;

  final Stdin _stdin;
  final IOSink _stdout;
  final IOSink _stderr;

  StreamSubscription<String>? _lines;

  /// 是否已挂载（幂等：重复 attach 不重复订阅）。
  bool get attached => _lines != null;

  /// 开始消费 stdin（重复挂载幂等）。
  void attach() {
    if (_lines != null) return;
    _lines = _stdin
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen(
          _handleLine,
          onError: (Object error, StackTrace stack) {
            _stderr.writeln('[mcp] stdin error: $error');
          },
          cancelOnError: false,
        );
  }

  /// 停止消费；用于测试/热卸载。
  Future<void> detach() async {
    final lines = _lines;
    _lines = null;
    await lines?.cancel();
  }

  Future<void> _handleLine(String line) async {
    // 空行不是 JSON-RPC 请求：静默跳过（不写脏行污染 stdout）。
    if (line.trim().isEmpty) return;
    try {
      final response = await server.handleLine(line);
      if (response == null) return; // 通知无响应
      _stdout.writeln(response);
      await _stdout.flush();
    } catch (error) {
      // 正常路径 [McpServer] 不抛异常；这里只兜底传输/编码层意外，
      // 记到 stderr（stdout 专供协议消息，不能混日志）。
      _stderr.writeln('[mcp] 处理失败: $error');
    }
  }
}
