import 'dart:async';
import 'dart:collection';

import '../protocol/command_spec.dart';
import '../protocol/control_error.dart';
import 'event.dart';

/// ECP P4 事件中心：内存环形事件流（设计 §10）。
///
/// 两条消费路径，职责严格分开：
/// - [poll]：游标式拉取（`since` + 长轮询），给 adb 一问一答通道与
///   `sys.events` 用，**历史补放只走这一条路**；
/// - [stream]：进程内广播流，给未来 MCP / 内置 agent 的常驻消费者用，
///   **不补历史**，订阅之前的事件只能凭游标回 poll。
///
/// 可见性：每个事件带敏感度 [ControlLevel]，消费者声明自己的 ceiling
/// （通道当前级别），超级别事件在两条路径上都物理过滤掉。
///
/// 纯 Dart 核心：只允许依赖 flutter/foundation（@immutable 等），零
/// Widget import——与 slash 核心同纪律，源码正则接缝测试钉死。
class ControlEventBus {
  ControlEventBus({this.capacity = 256})
    : assert(capacity >= 256, '事件环容量下限 256（P4 交接单 §G0）');

  /// 长轮询等待上限：必须小于 adb 接收器 9s 预算（交接单 §G0），
  /// `sys.events --wait-ms` 直接透传本上限做 USAGE 校验。
  static const Duration maxWait = Duration(milliseconds: 8000);

  /// 环形缓冲容量；超容量丢最旧，seq 不回收（允许出现空洞）。
  final int capacity;

  final Queue<ControlEvent> _ring = Queue<ControlEvent>();

  /// 下一个待分配 seq；[lastSeq] = 已分配最大序号（无事件时为 0）。
  int _nextSeq = 1;

  /// 单条广播管道：poll 的等待者与 stream 的订阅者都听它。
  /// broadcast 流不缓存事件，天然保证 stream 不补历史。
  final StreamController<ControlEvent> _controller =
      StreamController<ControlEvent>.broadcast();

  bool _closed = false;

  /// 当前尾序号（无事件时 0）；`sys.events` 缺省 since 用它实现
  /// 「不补历史」。
  int get lastSeq => _nextSeq - 1;

  /// 当前缓冲条数（淘汰断言/测试用）。
  int get length => _ring.length;

  /// 发射一条事件：分配 seq/time、入环（超容量淘汰最旧）、唤醒所有
  /// poll 等待者与广播订阅者。返回落库后的不可变事件。
  ///
  /// [data] 做浅不可变拷贝；事件内容的脱敏由发射点负责。
  ControlEvent emit({
    required String type,
    required ControlLevel level,
    Map<String, Object?> data = const {},
  }) {
    if (_closed) throw StateError('ControlEventBus 已 close，禁止再发射');
    final event = ControlEvent(
      seq: _nextSeq++,
      time: DateTime.now(),
      type: type,
      level: level,
      data: Map<String, Object?>.unmodifiable(data),
    );
    _ring.addLast(event);
    while (_ring.length > capacity) {
      _ring.removeFirst();
    }
    _controller.add(event);
    return event;
  }

  /// 游标拉取：返回现存事件中 `seq > since`、`level ≤ ceiling`、
  /// 类型命中 [types]（null ＝ 全部类型）的前 [limit] 条（按 seq
  /// 升序）。[since] 允许落在环内空洞之前——只返回还活着的事件。
  ///
  /// 无命中且 [wait] 非空非零时挂起，直到出现命中事件或等待截止
  /// （截止返回空列表）；任何新事件都会触发一次重新评估，未命中不
  /// 提前返回空。[wait] 超过 [maxWait] 抛 USAGE（必须小于接收器
  /// 9s 预算，由调用方原样透传给脚本侧）。
  Future<List<ControlEvent>> poll({
    required int since,
    required ControlLevel ceiling,
    Set<String>? types,
    int limit = 50,
    Duration? wait,
  }) async {
    if (since < 0) {
      throw ArgumentError.value(since, 'since', '游标不能为负');
    }
    if (limit < 1) {
      throw ArgumentError.value(limit, 'limit', '至少返回 1 条');
    }
    if (wait != null && wait > maxWait) {
      throw const ControlException(
        ControlErrorCode.usage,
        '事件长轮询 wait 上限 8000ms（adb 接收器预算 9s）',
      );
    }

    var matched = _match(since, ceiling, types, limit);
    if (matched.isNotEmpty || wait == null || wait == Duration.zero) {
      return matched;
    }

    final deadline = DateTime.now().add(wait);
    while (true) {
      final remaining = deadline.difference(DateTime.now());
      if (remaining <= Duration.zero) {
        return const <ControlEvent>[];
      }
      try {
        // 听「任意」新事件：新事件可能改变可见集（如高敏事件先到、
        // 命中事件后到），是否返回由 _match 重新裁决，这里不过滤。
        await _controller.stream.first.timeout(remaining);
      } on TimeoutException {
        return const <ControlEvent>[];
      }
      matched = _match(since, ceiling, types, limit);
      if (matched.isNotEmpty) return matched;
      // 新事件未命中（高级别/类型不符/环内旧游标）：继续等至截止。
    }
  }

  /// 进程内广播流：按 [ceiling] / [types] 过滤（语义同 poll），
  /// **不补历史**——订阅时刻之前的事件不会重放。给未来 MCP /
  /// 内置 agent 的常驻消费者使用（P4 交付接缝，G4 负向测试即消费者）。
  Stream<ControlEvent> stream({
    required ControlLevel ceiling,
    Set<String>? types,
  }) {
    return _controller.stream.where(
      (event) =>
          event.level.value <= ceiling.value &&
          (types == null || types.contains(event.type)),
    );
  }

  /// 环内一次性过滤（poll 初判与唤醒后复判共用）。
  List<ControlEvent> _match(
    int since,
    ControlLevel ceiling,
    Set<String>? types,
    int limit,
  ) {
    return _ring
        .where(
          (event) =>
              event.seq > since &&
              event.level.value <= ceiling.value &&
              (types == null || types.contains(event.type)),
        )
        .take(limit)
        .toList(growable: false);
  }

  /// 宿主停机时关闭广播管道；关闭后 [emit] 抛 StateError。
  void close() {
    if (_closed) return;
    _closed = true;
    _controller.close();
  }
}
