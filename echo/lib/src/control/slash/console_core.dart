/// slash 控制台核心：与入口 Widget 无关的命令行交互状态机
/// （设计 §7）。搜索栏指令态（G2）是第一个消费者，未来终端页是
/// 第二个——本类只依赖 [ControlBus] 与 [flutter/foundation]，
/// 不 import 任何 Widget。
///
/// 职责：
/// - [submitLine]：行文本 → [line_parser] → `bus.execute(slash 通道)`
///   → 信封流（[entries]，pending→done 两态，多条可在飞，[busy] 为
///   任一在跑）；超时完全复用总线 spec.timeout，本类不持有 Timer；
/// - [submitMultiline]：多行进文本（多行输入区）的唯一入口，参数
///   契约仍是普通的 string 参数（见 plan「多行进文本」）；
/// - 命令历史（会话内，↑↓ 召回）；auditRedact 参数（PIN/聊天正文）
///   在历史中截断，不留下可被误重发的字面。
library;

import 'dart:collection';

import 'package:flutter/foundation.dart';

import '../control_bus.dart';
import '../protocol/command_spec.dart';
import '../protocol/control_envelope.dart';
import '../protocol/control_error.dart';
import 'line_parser.dart';
import 'result_view.dart';

enum ConsoleEntryStatus { running, done }

/// 控制台结果历史中的一条（一次提交 = 一条）。
class ConsoleEntry {
  const ConsoleEntry({
    required this.id,
    required this.line,
    required this.cmd,
    required this.helpIntent,
    required this.stay,
    required this.status,
    this.envelope,
  });

  final int id;

  /// 用户提交的原始行（running 期用于回显；历史召回另走 Core 历史）。
  final String line;

  /// 调用目标命令全名；helpIntent 时为被查询的命令而非 sys.help。
  final String cmd;

  /// 尾随 `?`/`--help` 的 man 查询。
  final bool helpIntent;

  /// `--stay`：可视命令执行后不收起（G2 消费）。
  final bool stay;

  final ConsoleEntryStatus status;
  final ControlEnvelope? envelope;

  bool get ok => envelope?.ok ?? false;

  /// 完成后的结构化视图；running 期为 null。
  ResultView? get view => envelope == null ? null : viewOf(envelope!);

  ConsoleEntry copyWith({
    ConsoleEntryStatus? status,
    ControlEnvelope? envelope,
  }) => ConsoleEntry(
    id: id,
    line: line,
    cmd: cmd,
    helpIntent: helpIntent,
    stay: stay,
    status: status ?? this.status,
    envelope: envelope ?? this.envelope,
  );
}

class ControlConsoleCore extends ChangeNotifier {
  ControlConsoleCore({
    required this.bus,
    this.historyLimit = 100,
    this.entryLimit,
  });

  final ControlBus bus;
  final int historyLimit;

  /// 结果条数上限（null = 不裁剪，搜索栏指令态的历史行为）。
  ///
  /// nit③（维护者 2026-10-13）：正式终端页是长生命周期宿主，结果流
  /// 需要上限——传本参数即可环形丢弃最旧条目（对齐命令历史 100 /
  /// 审计环 200 的裁剪口径）。搜索栏不传，行为完全不变。
  final int? entryLimit;

  /// 结果历史（旧→新追加，消费方自行倒序展示），不可变视图。
  final List<ConsoleEntry> _entries = [];

  late final List<ConsoleEntry> entries = UnmodifiableListView<ConsoleEntry>(
    _entries,
  );

  final List<String> _history = [];

  /// ↑↓ 召回指针：== _history.length 表示停在「最新端」的空输入。
  int _recall = 0;

  int _nextId = 1;
  bool _disposed = false;

  /// 是否有命令在飞（多条并发时任一未完即为 true）。
  bool get busy => _entries.any((e) => e.status == ConsoleEntryStatus.running);

  /// 提交一行。空行忽略并返回 null；否则返回完成态 entry（成功/失败
  /// 均完成；调用方可 await 等结果，也可只听 notifyListeners）。
  Future<ConsoleEntry?> submitLine(String line) async {
    final trimmed = line.trim();
    if (trimmed.isEmpty) return null;

    final ParsedInvocation inv;
    try {
      inv = parseLine(line, lookup: bus.specOf);
    } on SlashUsageException catch (e) {
      // 词法/形状错误不进总线：合成 USAGE 信封，保证 UI 只渲染一种
      // 错误形状。解析失败行不入命令历史（可能含未成形的敏感裸值）。
      return _finish(
        _append(
          line: trimmed,
          cmd: _guessCmd(trimmed),
          helpIntent: false,
          stay: false,
        ),
        _syntheticFailure(
          _guessCmd(trimmed),
          ControlErrorCode.usage,
          e.message,
        ),
      );
    }
    _pushHistory(_historyLine(inv));
    return _runInvocation(trimmed, inv);
  }

  /// 多行正文提交：[head] 是除正文外的行（如 `chat.send --id x`），
  /// [param] 为接收全文的 string 参数名（清单 camelCase 或 CLI
  /// kebab 形态都认），[text] 为全文（换行保留）。
  ///
  /// 校验：head 能解析、命令存在、参数在清单上且为 string、head 中
  /// 未以任何形态给出该参数（与 adb `--text/--text-stdin` 互斥同语义）。
  Future<ConsoleEntry?> submitMultiline({
    required String head,
    required String param,
    required String text,
  }) async {
    final trimmed = head.trim();
    if (trimmed.isEmpty) {
      return null;
    }

    final ParsedInvocation inv;
    try {
      inv = parseLine(head, lookup: bus.specOf);
    } on SlashUsageException catch (e) {
      return _finish(
        _append(
          line: trimmed,
          cmd: _guessCmd(trimmed),
          helpIntent: false,
          stay: false,
        ),
        _syntheticFailure(
          _guessCmd(trimmed),
          ControlErrorCode.usage,
          e.message,
        ),
      );
    }

    ControlException reject(String msg) =>
        ControlException(ControlErrorCode.usage, msg);

    final spec = bus.specOf(inv.cmd);
    final paramKey = camelize(param);
    final paramSpec = spec?.params
        .where((p) => p.name == paramKey)
        .cast<ParamSpec?>()
        .firstWhere((_) => true, orElse: () => null);
    if (spec == null) {
      return _failParsed(trimmed, inv, reject('未知命令：${inv.cmd}'));
    }
    if (paramSpec == null || paramSpec.type != ArgType.string) {
      return _failParsed(
        trimmed,
        inv,
        reject('${spec.name} 没有 string 参数 --${kebabOf(paramKey)}'),
      );
    }
    if (inv.args.containsKey(paramKey)) {
      return _failParsed(
        trimmed,
        inv,
        reject('--${kebabOf(paramKey)} 只能给一次（行内值与多行全文互斥）'),
      );
    }

    inv.args[paramKey] = text;
    // 历史由调用参数重建：全文经 auditRedact 规则截断（见 _historyLine）。
    _pushHistory(_historyLine(inv));
    return _runInvocation(trimmed, inv);
  }

  // ---- 执行 -------------------------------------------------------------

  Future<ConsoleEntry> _runInvocation(String line, ParsedInvocation inv) async {
    final entry = _append(
      line: line,
      cmd: inv.cmd,
      helpIntent: inv.helpIntent,
      stay: inv.stay,
    );

    final String executeCmd;
    final Map<String, Object?> executeArgs;
    if (inv.helpIntent) {
      // man 查询统一走 sys.help，不另造帮助数据源。
      executeCmd = 'sys.help';
      executeArgs = {'command': inv.cmd};
    } else {
      executeCmd = inv.cmd;
      executeArgs = inv.args;
    }

    try {
      final envelope = await bus.execute(
        channel: ControlChannel.slash,
        cmd: executeCmd,
        rawArgs: executeArgs,
        confirmed: inv.confirmed,
      );
      return _finish(entry, envelope);
    } catch (e) {
      // 总线已兜底全部异常；此分支仅为防御（总线失配时不吞异常）。
      return _finish(
        entry,
        _syntheticFailure(inv.cmd, ControlErrorCode.business, '控制台内部错误：$e'),
      );
    }
  }

  /// 解析成功但调用前校验失败（多行注入校验）：合成信封 + 入史保护。
  Future<ConsoleEntry> _failParsed(
    String line,
    ParsedInvocation inv,
    ControlException error,
  ) async {
    return _finish(
      _append(
        line: line,
        cmd: inv.cmd,
        helpIntent: inv.helpIntent,
        stay: inv.stay,
      ),
      _syntheticFailure(inv.cmd, error.code, error.message),
    );
  }

  // ---- 历史 -------------------------------------------------------------

  /// 会话内命令历史（旧→新）。
  List<String> get history => UnmodifiableListView<String>(_history);

  /// ↑：向更旧的一条召回；已在最旧端时返回 null（输入保持不变）。
  String? recallOlder() {
    if (_history.isEmpty || _recall <= 0) return null;
    _recall--;
    return _history[_recall];
  }

  /// ↓：向更新的一条召回；越过最新端时返回空串（清空输入）。
  String? recallNewer() {
    if (_history.isEmpty || _recall >= _history.length) return null;
    _recall++;
    return _recall == _history.length ? '' : _history[_recall];
  }

  /// 提交/输入变化时复位召回指针到最新端。
  void resetRecall() => _recall = _history.length;

  void _pushHistory(String line) {
    // 连续重复去重（与 shell HISTSIZE 行为一致）；上限环形丢弃最旧。
    if (_history.isNotEmpty && _history.last == line) {
      resetRecall();
      return;
    }
    _history.add(line);
    if (_history.length > historyLimit) {
      _history.removeRange(0, _history.length - historyLimit);
    }
    resetRecall();
  }

  /// 把已解析调用重建为可安全召回的历史行。
  ///
  /// 关键隐私规则：清单标 auditRedact 的参数（PIN、聊天正文）不把
  /// 字面留在历史里——遇到第一个即停止重建（其后参数一并省略），
  /// 保证 ↑ 召回的行重跑时不会把正文/PIN 当值再发一次。
  String _historyLine(ParsedInvocation inv) {
    final spec = bus.specOf(inv.cmd);
    final redacted = {
      if (spec != null)
        for (final p in spec.params)
          if (p.auditRedact) p.name,
    };

    final parts = <String>[inv.cmd];
    for (final entry in inv.args.entries) {
      if (redacted.contains(entry.key)) {
        // 直接截断：脱敏参数名/值与其后参数全部省略。不能留
        // `--text <redacted:N>` 占位——召回重跑会把占位符当正文发出；
        // 截到前一个安全参数为止，由用户重新输入正文（安全优先）。
        break;
      }
      final v = entry.value;
      if (v is bool) {
        if (v) parts.add('--${kebabOf(entry.key)}');
      } else {
        parts.addAll(['--${kebabOf(entry.key)}', v.toString()]);
      }
    }
    if (inv.confirmed) parts.add('--confirm');
    if (inv.stay) parts.add('--stay');
    if (inv.helpIntent) parts.add('?');
    return parts.join(' ');
  }

  // ---- entry 装配 -------------------------------------------------------

  ConsoleEntry _append({
    required String line,
    required String cmd,
    required bool helpIntent,
    required bool stay,
  }) {
    final entry = ConsoleEntry(
      id: _nextId++,
      line: line,
      cmd: cmd,
      helpIntent: helpIntent,
      stay: stay,
      status: ConsoleEntryStatus.running,
    );
    _entries.add(entry);
    _trimToLimit();
    _notify();
    return entry;
  }

  /// 只在超过 [entryLimit] 时裁剪，且只裁已完成条目：在飞命令保留到
  /// [_finish] 回填（总线 timeout 兜底保证其必然完成），避免结果被静默
  /// 丢弃；并发提交挤满时先完成者优先被裁，长度最终仍收敛到上限。
  void _trimToLimit() {
    final limit = entryLimit;
    if (limit == null || _entries.length <= limit) return;
    for (var i = 0; i < _entries.length && _entries.length > limit;) {
      if (_entries[i].status == ConsoleEntryStatus.done) {
        _entries.removeAt(i);
      } else {
        i++;
      }
    }
  }

  ConsoleEntry _finish(ConsoleEntry entry, ControlEnvelope envelope) {
    final done = entry.copyWith(
      status: ConsoleEntryStatus.done,
      envelope: envelope,
    );
    final i = _entries.indexWhere((e) => e.id == entry.id);
    if (i >= 0) _entries[i] = done;
    _trimToLimit();
    _notify();
    return done;
  }

  ControlEnvelope _syntheticFailure(
    String cmd,
    ControlErrorCode code,
    String message,
  ) => ControlEnvelope.failure(cmd, 0, ControlException(code, message));

  /// 解析失败时从原始行猜命令名（仅用于错误信封回显，不做裁决）。
  String _guessCmd(String line) {
    var head = line.startsWith('/') ? line.substring(1) : line;
    head = head.split(RegExp(r'\s')).first;
    if (head.endsWith('?')) head = head.substring(0, head.length - 1);
    if (head.contains('.')) return head;
    final rest = line.trim().split(RegExp(r'\s+'));
    return rest.length >= 2 ? '$head.${rest[1].replaceAll('?', '')}' : head;
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    // 在飞调用不取消：总线 spec.timeout 兜底，完成后 _notify 静默。
    super.dispose();
  }
}
