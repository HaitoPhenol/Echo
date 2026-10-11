import 'package:flutter/widgets.dart';

import '../protocol/command_spec.dart';
import '../protocol/control_error.dart';
import 'audit_log.dart';
import 'pin_store.dart';

/// 鉴权与会话管理（设计 §5）。
///
/// 会话语义（用户裁定）：`auth.unlock` 成功后颁发**仅当次前台运行
/// 有效**的内存会话；App 进入后台（paused，含息屏/切应用/锁屏）立即
/// 销毁全部会话，回前台需重新解锁。连续 5 次 PIN 错误触发冷却，
/// 30s 起指数退避到 5min。
class AuthManager extends ControlAuthorizer with WidgetsBindingObserver {
  AuthManager({
    required this.pins,
    required this.auditLog,
    DateTime Function()? now,
  }) : nowFn = now ?? DateTime.now;

  final PinVerifier pins;
  final AuditLog auditLog;
  final DateTime Function() nowFn;

  /// 已解锁通道集合（值为级别；当前解锁即 3 级，保留值便于未来分级）。
  final Map<ControlChannel, ControlLevel> _sessions = {};

  /// 各通道连续失败次数与冷却截止时刻。
  final Map<ControlChannel, int> _failures = {};
  final Map<ControlChannel, DateTime> _cooldownUntil = {};

  /// 连续失败 5 次进入冷却；30s × 2^k，封顶 5min。
  static const int failuresThreshold = 5;
  static const List<Duration> _backoff = [
    Duration(seconds: 30),
    Duration(seconds: 60),
    Duration(seconds: 120),
    Duration(seconds: 240),
    Duration(minutes: 5),
  ];

  /// 挂载到引擎绑定以接收前后台事件（bootstrap 调用一次）。
  void attach() => WidgetsBinding.instance.addObserver(this);

  void detach() => WidgetsBinding.instance.removeObserver(this);

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Android：切后台/息屏/锁屏均走 paused；inactive 的瞬态不销毁。
    if (state == AppLifecycleState.paused) expireAllSessions();
  }

  /// 通道当前有效级别：有会话取会话级（受通道上限夹取），
  /// 否则取通道起始级别。
  ControlLevel effectiveLevel(ControlChannel channel) {
    final session = _sessions[channel];
    if (session == null) return channel.startLevel;
    return session.value <= channel.maxLevel.value
        ? session
        : channel.maxLevel;
  }

  bool isUnlocked(ControlChannel channel) => _sessions.containsKey(channel);

  /// 总线裁决（含 3 级 `--confirm`）。
  @override
  ControlException? check(
    CommandSpec spec,
    ControlChannel channel, {
    required bool confirmed,
  }) {
    // auth.set-pin 自带首装/旧 PIN 双路径校验（处理函数内裁决），
    // 总线级放行；其 --confirm 也由二次输入 PIN 承担。
    if (spec.name == 'auth.set-pin') return null;

    if (spec.level.value > effectiveLevel(channel).value) {
      return ControlException(
        ControlErrorCode.authRequired,
        '${spec.name} 需要 ${spec.level.value} 级权限，请先解锁',
        need: spec.level.value,
        elevate: 'auth.unlock',
      );
    }
    if (spec.requiresConfirm && !confirmed) {
      return ControlException(
        ControlErrorCode.confirmRequired,
        '${spec.name} 是 3 级命令，必须显式追加 --confirm 才会执行',
      );
    }
    return null;
  }

  /// `auth.unlock`：校验 PIN、管理失败退避、颁发会话。
  /// 成功返回 null；失败返回错误信封数据（并写审计）。
  Future<ControlException?> requestUnlock(
    ControlChannel channel,
    String pin,
  ) async {
    if (channel.maxLevel.value < ControlLevel.admin.value) {
      // MCP 只读铁律：写级别永不向网络通道颁发。
      return _deny(
        channel,
        ControlException(
          ControlErrorCode.authDenied,
          '该通道只读，不能解锁到写级别',
        ),
      );
    }

    final cooldown = _cooldownUntil[channel];
    if (cooldown != null && cooldown.isAfter(nowFn())) {
      final retryMs = cooldown.difference(nowFn()).inMilliseconds;
      final error = ControlException(
        ControlErrorCode.authCooldown,
        'PIN 错误过多，请稍后再试',
        retryAfterMs: retryMs,
      );
      auditLog.record(_event(channel, 'auth.unlock', false,
          error: error.code.wire));
      return error;
    }

    if (!await pins.isPinSet()) {
      return _deny(
        channel,
        const ControlException(
          ControlErrorCode.pinNotSet,
          '尚未设置 PIN；debug 包可经 adb 执行 auth.set-pin 首次初始化',
          elevate: 'auth.set-pin',
        ),
      );
    }

    if (await pins.verifyPin(pin)) {
      _failures.remove(channel);
      _cooldownUntil.remove(channel);
      _sessions[channel] = ControlLevel.admin;
      auditLog.record(_event(channel, 'auth.unlock', true));
      return null;
    }

    final failures = (_failures[channel] ?? 0) + 1;
    _failures[channel] = failures;
    if (failures >= failuresThreshold && failures % failuresThreshold == 0) {
      final step = ((failures ~/ failuresThreshold) - 1)
          .clamp(0, _backoff.length - 1);
      _cooldownUntil[channel] = nowFn().add(_backoff[step]);
    }
    return _deny(
      channel,
      const ControlException(ControlErrorCode.authDenied, 'PIN 不正确'),
    );
  }

  /// `auth.lock`：立即销毁当前通道会话。
  void lock(ControlChannel channel) {
    if (_sessions.remove(channel) != null) {
      auditLog.record(_event(channel, 'auth.lock', true));
    }
  }

  /// 前后台切换：销毁全部会话（息屏/切后台即时生效）。
  void expireAllSessions() {
    if (_sessions.isEmpty) return;
    final channels = _sessions.keys.map((c) => c.wire).toList();
    _sessions.clear();
    auditLog.record(AuditEntry(
      time: nowFn(),
      channel: channels.join(','),
      cmd: 'auth.session-expired',
      paramSummary: {'reason': 'app-backgrounded'},
      ok: true,
    ));
  }

  /// `auth.status` 的机读视图。
  Future<Map<String, Object?>> status(ControlChannel channel) async {
    return {
      'pinSet': await pins.isPinSet(),
      'unlocked': isUnlocked(channel),
      'level': effectiveLevel(channel).value,
      'channel': channel.wire,
      'expiresOnBackground': true,
    };
  }

  ControlException _deny(ControlChannel channel, ControlException error) {
    auditLog.record(_event(channel, 'auth.unlock', false,
        error: error.code.wire));
    return error;
  }

  AuditEntry _event(
    ControlChannel channel,
    String cmd,
    bool ok, {
    String? error,
  }) {
    return AuditEntry(
      time: nowFn(),
      channel: channel.wire,
      cmd: cmd,
      paramSummary: const {}, // PIN 永不入审计
      ok: ok,
      errorCode: error,
    );
  }
}
