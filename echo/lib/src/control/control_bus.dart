import 'dart:async';

import 'auth/audit_log.dart';
import 'control_registry.dart';
import 'events/event_bus.dart';
import 'events/event_types.dart';
import 'jobs/job_store.dart';
import 'protocol/command_spec.dart';
import 'protocol/control_envelope.dart';
import 'protocol/control_error.dart';

/// 命令总线：注册清单、发现、参数校验、权限裁决、审计与统一错误收口
/// （设计 §3.1）。
///
/// 通道适配层（adb / 未来 slash、MCP）只负责把请求翻译成
/// [execute] 调用并渲染 [ControlEnvelope]，不做业务判断。
class ControlBus implements ControlBusHandle {
  ControlBus({
    required this.buildMode,
    required this.services,
    required this.authorizer,
    required this.auditLog,
    required this.jobs,
    required this.events,
  });

  @override
  final ControlBuildMode buildMode;

  /// 服务注册表（也是 [ControlBusHandle] 对命令层暴露的唯一入口）。
  @override
  final ControlRegistry services;
  final ControlAuthorizer authorizer;
  final AuditLog auditLog;

  /// P4：slow 命令后台作业表（adb 通道作业化执行 / sys.job.get
  /// 轮询；同时注册进 services 供命令层取）。
  final ControlJobStore jobs;

  /// P4：事件中心（sys.events 经 services 取；域命令经句柄缝发射）。
  final ControlEventBus events;

  @override
  void emitEvent({
    required String type,
    required ControlLevel level,
    Map<String, Object?> data = const {},
    // 关停容忍：事件是尽力而为的遥测，总线收口/handler 可能在事件
    // 中心 close 之后才跑完（后台作业撞上宿主 dispose），此时安静
    // 丢事件，绝不把命令执行打成失败。
  }) => events.tryEmit(type: type, level: level, data: data);

  /// 已注册命令（全名 → 规格），注册后不可变。
  final Map<String, CommandSpec> _specs = {};

  /// 全局标志：由通道层消费、不进命令参数。总线对它们做「已知忽略」，
  /// 其余未声明参数一律 USAGE（防 typo 静默）。
  static const Set<String> globalFlags = {'format', 'stay', 'timeout'};

  // ---- 注册 / 发现 -------------------------------------------------------

  /// 注册一条命令。重名、debug 风味下的 debug-only 规则在此收口；
  /// 注册顺序即 help 的展示顺序（内部用 LinkedHashMap）。
  void register(CommandSpec spec) {
    if (spec.debugOnly && buildMode == ControlBuildMode.release) {
      // release manifest 中物理不存在，而非「存在但拒绝」。
      return;
    }
    if (_specs.containsKey(spec.name)) {
      throw StateError('命令重复注册：${spec.name}');
    }
    _specs[spec.name] = spec;
  }

  /// 批量注册（各域适配器一行接一行）。
  void registerAll(Iterable<CommandSpec> specs) => specs.forEach(register);

  /// 当前构建可见的全部命令（help / 手册一致性测试用）。
  @override
  List<CommandSpec> get visibleSpecs => _specs.values.toList(growable: false);

  CommandSpec? specOf(String name) => _specs[name];

  // ---- 执行 -------------------------------------------------------------

  /// 执行一次调用。
  ///
  /// [rawArgs] 为通道解码后的参数 Map（adb 侧由 JSON 字符串解码）；
  /// [confirmed] 对应 3 级命令的 `--confirm`；[nonce] 仅 adb 回响。
  ///
  /// [backgroundSlow]（P4-G1，默认 false）：true 且命令标 `slow` 时
  /// 立即回 async running 信封，真正执行在后台继续、终态落 [jobs]
  /// 供 `sys.job.get` 轮询——根治 adb 接收器 9s 预算（E4）。false
  /// （slash 与全部非 slow 命令）行为与历史逐字节一致。
  Future<ControlEnvelope> execute({
    required ControlChannel channel,
    required String cmd,
    Map<String, Object?>? rawArgs,
    bool confirmed = false,
    String? nonce,
    bool backgroundSlow = false,
  }) async {
    final stopwatch = Stopwatch()..start();
    ControlEnvelope failBeforeRun(ControlException error) {
      stopwatch.stop();
      return ControlEnvelope.failure(
        cmd,
        stopwatch.elapsedMilliseconds,
        error,
        nonce: nonce,
      );
    }

    final spec = _specs[cmd];
    if (spec == null) {
      return failBeforeRun(
        ControlException(ControlErrorCode.unknownCommand, '未知命令：$cmd'),
      );
    }

    // 1) 参数校验与缺省填充。
    final Map<String, Object?> args;
    try {
      args = _parseArgs(spec, rawArgs ?? const {});
    } on ControlException catch (e) {
      return failBeforeRun(e);
    }

    // 2) 权限裁决（含 3 级 --confirm）。
    final denied = authorizer.check(spec, channel, confirmed: confirmed);
    if (denied != null) {
      _auditIfNeeded(
        spec,
        channel,
        args,
        ok: false,
        error: denied,
        ms: stopwatch.elapsedMilliseconds,
      );
      return failBeforeRun(denied);
    }

    // 3) slow 命令作业化（仅当通道显式要求；adb 传 true，slash 不传）。
    if (backgroundSlow && spec.slow) {
      final job = jobs.start(
        spec: spec,
        channel: channel,
        confirmed: confirmed,
        // nonce 即 jobId：接收器 9s TIMEOUT 后工作站仍能用同一 nonce
        // 轮询到终态（E4 兜底）；撞表/无 nonce 时作业表自行生成。
        preferredId: nonce,
      );
      // 完成路径与同步调用完全共用：审计/超时/脱敏绝不分叉。
      unawaited(
        _finishAuthorized(
          spec,
          channel,
          args,
          nonce,
          stopwatch,
          jobId: job.id,
        ).then((envelope) => jobs.complete(job, envelope)),
      );
      return ControlEnvelope(
        ok: true,
        cmd: cmd,
        ms: stopwatch.elapsedMilliseconds,
        async: true,
        jobId: job.id,
        nonce: nonce,
        result: {
          'status': 'running',
          'jobId': job.id,
          'cmd': cmd,
          'hint': 'sys.job.get --id ${job.id}',
        },
      );
    }

    return _finishAuthorized(spec, channel, args, nonce, stopwatch);
  }

  /// 鉴权通过后的执行收口（同步调用与后台作业**唯一**共用路径）：
  /// 跑 handler（普通 10s / slow 60s 超时）、成败入审计、统一异常
  /// 映射。设计 §6：≥2 级调用无论成败都记；参数解析/未知命令/鉴权
  /// 拒绝发生在进入本方法之前。
  Future<ControlEnvelope> _finishAuthorized(
    CommandSpec spec,
    ControlChannel channel,
    Map<String, Object?> args,
    String? nonce,
    Stopwatch stopwatch, {
    // 仅后台作业路径传入：command.finished 事件带 jobId，消费者可
    // 据此把终态与 running 首包关联。同步路径恒为 null。
    String? jobId,
  }) async {
    // P4：裁决后执行收口的唯一事件出口（成功/业务失败/超时都经此）。
    // 裁决前失败（未知命令/USAGE/鉴权拒绝）走不到本方法，天然不发。
    void emitFinished(ControlEnvelope envelope) {
      events.emit(
        type: ControlEventType.commandFinished,
        level: ControlLevel.owner,
        data: {
          'cmd': envelope.cmd,
          'ok': envelope.ok,
          if (!envelope.ok) 'error': envelope.error!.toJson(),
          'ms': envelope.ms,
          'nonce': ?nonce,
          'jobId': ?jobId,
        },
      );
    }

    ControlEnvelope failAudited(ControlException error) {
      stopwatch.stop();
      _auditIfNeeded(
        spec,
        channel,
        args,
        ok: false,
        error: error,
        ms: stopwatch.elapsedMilliseconds,
      );
      final envelope = ControlEnvelope.failure(
        spec.name,
        stopwatch.elapsedMilliseconds,
        error,
        nonce: nonce,
      );
      emitFinished(envelope);
      return envelope;
    }

    final context = CommandContext(
      bus: this,
      channel: channel,
      spec: spec,
      args: args,
    );
    try {
      final result = await spec.handler(context).timeout(spec.timeout);
      stopwatch.stop();
      _auditIfNeeded(
        spec,
        channel,
        args,
        ok: true,
        ms: stopwatch.elapsedMilliseconds,
      );
      final envelope = ControlEnvelope(
        ok: true,
        cmd: spec.name,
        ms: stopwatch.elapsedMilliseconds,
        result: result,
        nonce: nonce,
      );
      emitFinished(envelope);
      return envelope;
    } on ControlException catch (e) {
      return failAudited(e);
    } on TimeoutException {
      return failAudited(
        ControlException(
          ControlErrorCode.timeout,
          '执行超时（${spec.timeout.inSeconds}s）：${spec.name}',
        ),
      );
    } on ArgumentError catch (e) {
      return failAudited(
        ControlException(
          ControlErrorCode.usage,
          e.message?.toString() ?? '参数错误',
        ),
      );
    } on StateError catch (e) {
      return failAudited(
        ControlException(ControlErrorCode.conflict, e.message.toString()),
      );
    } catch (e) {
      return failAudited(
        ControlException(ControlErrorCode.business, e.toString()),
      );
    }
  }

  void _auditIfNeeded(
    CommandSpec spec,
    ControlChannel channel,
    Map<String, Object?> args, {
    required bool ok,
    required int ms,
    ControlException? error,
  }) {
    // 设计 §6：所有 ≥2 级命令调用入审计（读命令 0/1 不记）。
    if (spec.level.value < ControlLevel.user.value) return;
    auditLog.record(
      AuditEntry(
        time: DateTime.now(),
        channel: channel.wire,
        cmd: spec.name,
        paramSummary: _sanitizeForAudit(spec, args),
        ok: ok,
        errorCode: error?.code.wire,
        ms: ms,
      ),
    );
  }

  /// 参数摘要：清单标注 [ParamSpec.auditRedact] 的键（PIN、聊天正文
  /// 等）整体抹除，只留 trim 后落库长度；其余长字符串截断
  /// （设计 §6：绝不记录 PIN / 正文全文，仅记长度与目标 id）。
  /// 成功与失败路径共用本方法，保证失败审计同样不含字面。
  Map<String, Object?> _sanitizeForAudit(
    CommandSpec spec,
    Map<String, Object?> args,
  ) {
    final redacted = {
      for (final p in spec.params)
        if (p.auditRedact) p.name,
    };
    final out = <String, Object?>{};
    for (final entry in args.entries) {
      if (redacted.contains(entry.key)) {
        final value = entry.value;
        // N 取 trim 后长度（与 store 落库文本一致；空白文本记 0），
        // 非字符串（清单上不应出现）防御性记 0。
        final n = value is String ? value.trim().length : 0;
        out[entry.key] = '<redacted:$n>';
        continue;
      }
      final value = entry.value;
      if (value is String && value.length > 80) {
        out[entry.key] = '${value.substring(0, 80)}…(+${value.length - 80})';
      } else if (value is DateTime) {
        out[entry.key] = value.toIso8601String();
      } else {
        out[entry.key] = value;
      }
    }
    return out;
  }

  // ---- 参数解析 ----------------------------------------------------------

  Map<String, Object?> _parseArgs(CommandSpec spec, Map<String, Object?> raw) {
    final out = <String, Object?>{};
    final declared = {for (final p in spec.params) p.name: p};

    for (final key in raw.keys) {
      if (globalFlags.contains(key)) continue;
      final param = declared[key];
      if (param == null) {
        throw ControlException(
          ControlErrorCode.usage,
          '未知参数 --$key（命令 ${spec.name}）',
        );
      }
      out[key] = _convert(spec, param, raw[key]);
    }

    for (final param in spec.params) {
      if (!out.containsKey(param.name)) {
        if (param.required) {
          throw ControlException(
            ControlErrorCode.usage,
            '缺少必填参数 --${param.name}（${param.type.wire}）',
          );
        }
        out[param.name] = param.defaults;
      }
    }
    return out;
  }

  Object? _convert(CommandSpec spec, ParamSpec param, Object? raw) {
    if (raw == null) {
      throw ControlException(
        ControlErrorCode.usage,
        '--${param.name} 不能为 null',
      );
    }
    try {
      switch (param.type) {
        case ArgType.string:
          if (raw is String) return raw;
          return raw.toString();
        case ArgType.integer:
          if (raw is int) return raw;
          if (raw is String) return int.parse(raw, radix: 10);
          throw const FormatException('不是整数');
        case ArgType.boolean:
          if (raw is bool) return raw;
          if (raw is String) {
            if (raw == 'true') return true;
            if (raw == 'false') return false;
          }
          throw const FormatException('不是布尔值（true/false）');
        case ArgType.date:
          final date = _parseDate(raw);
          if (date == null) {
            throw const FormatException('日期应为 YYYY-MM-DD');
          }
          return date;
        case ArgType.month:
          final month = _parseMonth(raw);
          if (month == null) {
            throw const FormatException('月份应为 YYYY-MM');
          }
          return month;
        case ArgType.dateTime:
          final dt = _parseDateTime(raw);
          if (dt == null) {
            throw const FormatException('时间应为 YYYY-MM-DDTHH:mm[:ss]');
          }
          return dt;
      }
    } on FormatException catch (e) {
      throw ControlException(
        ControlErrorCode.usage,
        '--${param.name} 类型错误：${e.message}',
      );
    }
  }

  /// `YYYY-MM-DD`（严格校验，拒绝 13 月 40 日）。
  static DateTime? _parseDate(Object raw) {
    if (raw is! String) return null;
    final match = RegExp(r'^(\d{4})-(\d{2})-(\d{2})$').firstMatch(raw);
    if (match == null) return null;
    final date = DateTime(
      int.parse(match.group(1)!),
      int.parse(match.group(2)!),
      int.parse(match.group(3)!),
    );
    final reassembled =
        '${date.year.toString().padLeft(4, '0')}-'
        '${date.month.toString().padLeft(2, '0')}-'
        '${date.day.toString().padLeft(2, '0')}';
    return reassembled == raw ? date : null;
  }

  /// `YYYY-MM`。
  static DateTime? _parseMonth(Object raw) {
    if (raw is! String) return null;
    final match = RegExp(r'^(\d{4})-(\d{2})$').firstMatch(raw);
    if (match == null) return null;
    final month = int.parse(match.group(2)!);
    if (month < 1 || month > 12) return null;
    return DateTime(int.parse(match.group(1)!), month, 1);
  }

  /// `YYYY-MM-DDTHH:mm[:ss]` 本地时间。
  static DateTime? _parseDateTime(Object raw) {
    if (raw is! String) return null;
    final match = RegExp(
      r'^(\d{4})-(\d{2})-(\d{2})T(\d{2}):(\d{2})(?::(\d{2}))?$',
    ).firstMatch(raw);
    if (match == null) return null;
    final dt = DateTime(
      int.parse(match.group(1)!),
      int.parse(match.group(2)!),
      int.parse(match.group(3)!),
      int.parse(match.group(4)!),
      int.parse(match.group(5)!),
      match.group(6) == null ? 0 : int.parse(match.group(6)!),
    );
    // DateTime 归一化会把越界时间进位（如 25 点），重组校验拒绝。
    return dt.toIso8601String().startsWith(raw) ? dt : null;
  }
}
