import 'dart:collection';

import '../protocol/command_spec.dart';
import '../protocol/control_envelope.dart';

/// 一条异步作业（P4-G1：adb 通道 slow 命令的后台执行）。
///
/// 作业由 [ControlJobStore.start] 创建（running），后台执行收口后
/// [ControlJobStore.complete] 写入最终信封（done）。终态信封就是普通
/// [ControlEnvelope]（含原 nonce、ms、result/error），轮询者拿到后
/// 与同步调用逐字同形。
class ControlJob {
  ControlJob({
    required this.id,
    required this.channel,
    required this.spec,
    required this.confirmed,
    required this.startedAt,
  });

  /// 作业 id：adb 侧等于调用 nonce（接收器 9s 超时后仍可用已知 nonce
  /// 轮询，E4 兜底语义）；无 nonce 时由作业表生成 `job-<n>`。
  final String id;

  /// 起作业的通道；轮询强制同通道（跨通道隔离）。
  final ControlChannel channel;

  /// 原命令规格：轮询取结果时在当前通道重新过鉴权用。
  final CommandSpec spec;

  /// 起作业时的确认位：重鉴权沿用（确认在起作业时已显式给过，
  /// 轮询不重复要求 --confirm；级别不足仍会先被 AUTH_REQUIRED 挡）。
  final bool confirmed;

  final DateTime startedAt;

  /// 终态信封；null ＝ 仍在跑。仅 [ControlJobStore.complete] 可写。
  ControlEnvelope? envelope;

  bool get isDone => envelope != null;
}

/// 异步作业表（内存环形，P4 不持久化）。
///
/// 容量 32：slow 命令（当前仅 diary.export 与 debug 的 sys.delay）
/// 极低频，超容量淘汰最旧（running 也可能被淘汰——其后台 future
/// 收口时写入的对象已离表，结果自然不可达，与「超时丢作业」同语义）。
/// id 被淘汰后允许复用（调用方 nonce 撞表时退化为 `job-<n>`）。
class ControlJobStore {
  ControlJobStore({this.capacity = 32}) : assert(capacity >= 32, '作业环容量下限 32');

  final int capacity;
  final Queue<ControlJob> _ring = Queue<ControlJob>();
  final Map<String, ControlJob> _byId = <String, ControlJob>{};

  /// 自增作业号（无 nonce / nonce 撞表时生成 `job-<n>`）。
  int _generated = 0;

  /// 当前在表作业数（测试用）。
  int get length => _ring.length;

  /// 登记一条 running 作业。[preferredId] 取调用 nonce；为空或与在表
  /// 作业撞 id（同一 nonce 重发）时退化为生成 id，绝不覆盖旧作业。
  ControlJob start({
    required CommandSpec spec,
    required ControlChannel channel,
    required bool confirmed,
    String? preferredId,
    DateTime? startedAt,
  }) {
    var id = (preferredId != null && preferredId.isNotEmpty)
        ? preferredId
        : _nextGenerated();
    if (_byId.containsKey(id)) {
      id = _nextGenerated();
    }
    final job = ControlJob(
      id: id,
      channel: channel,
      spec: spec,
      confirmed: confirmed,
      startedAt: startedAt ?? DateTime.now(),
    );
    _ring.addLast(job);
    _byId[job.id] = job;
    while (_ring.length > capacity) {
      final oldest = _ring.removeFirst();
      // 只在映射仍指向同一对象时移除（淘汰后 id 复用不被误删）。
      if (identical(_byId[oldest.id], oldest)) {
        _byId.remove(oldest.id);
      }
    }
    return job;
  }

  /// 按 id + 通道取作业：他通道/不存在/已淘汰一律返回 null
  /// （命令层统一翻 NOT_FOUND，不向调用方区分「不存在」与「无权跨
  /// 通道看」）。
  ControlJob? lookup({required String id, required ControlChannel channel}) {
    final job = _byId[id];
    if (job == null || job.channel != channel) return null;
    return job;
  }

  /// 后台执行收口：写入终态信封。作业已被环淘汰时是空操作
  /// （对象离表，无人可达）。
  void complete(ControlJob job, ControlEnvelope envelope) {
    if (!identical(_byId[job.id], job)) return;
    job.envelope = envelope;
  }

  String _nextGenerated() {
    String id;
    do {
      id = 'job-${++_generated}';
    } while (_byId.containsKey(id));
    return id;
  }
}
