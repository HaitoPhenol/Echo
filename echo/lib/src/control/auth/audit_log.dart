import 'dart:collection';

/// 一条审计记录（设计 §6）。
///
/// 敏感字段在写入前由调用方/总线完成脱敏：[paramSummary] 中绝不出现
/// PIN 明文或日记正文全文。
class AuditEntry {
  const AuditEntry({
    required this.time,
    required this.channel,
    required this.cmd,
    required this.paramSummary,
    required this.ok,
    this.errorCode,
    this.ms = 0,
  });

  final DateTime time;
  final String channel;
  final String cmd;
  final Map<String, Object?> paramSummary;
  final bool ok;
  final String? errorCode;
  final int ms;

  Map<String, Object?> toJson() => {
    'time': time.toIso8601String(),
    'channel': channel,
    'cmd': cmd,
    'params': paramSummary,
    'ok': ok,
    if (errorCode != null) 'error': errorCode,
    'ms': ms,
  };
}

/// 审计流水：P1 落内存环形缓冲（设计 §6：≥200 条），
/// 持久化（sqflite 独立表）随后续阶段接入。
///
/// 记录范围：所有 ≥2 级命令调用（总线写入）、解锁成功/失败、
/// 会话失效、PIN 初始化/变更（鉴权层写入）。
class AuditLog {
  AuditLog({this.capacity = 200})
    : assert(capacity >= 200, '审计缓冲下限 200 条（设计 §6）');

  final int capacity;
  final Queue<AuditEntry> _entries = Queue();

  /// 追加一条；超容量丢弃最旧记录。
  void record(AuditEntry entry) {
    _entries.addLast(entry);
    while (_entries.length > capacity) {
      _entries.removeFirst();
    }
  }

  /// 倒序返回最近 [limit] 条（`sys.audit --limit`，上限 200）。
  List<AuditEntry> list({int limit = 50}) {
    final n = limit.clamp(1, capacity);
    return _entries.toList(growable: false).reversed.take(n).toList();
  }

  /// 当前条数（测试用）。
  int get length => _entries.length;
}
