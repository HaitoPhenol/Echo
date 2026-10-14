import 'package:flutter/foundation.dart';

import '../protocol/command_spec.dart';

/// ECP P4 事件流的一条事件（设计 §10：状态变更 / 导出完成 / 审计事件）。
///
/// 不可变值对象：[ControlEventBus.emit] 统一分配 [seq]（从 1 起单调
/// 递增）与 [time]；订阅者不得自行构造事件，`const` 构造仅供总线
/// 内部与测试使用。载荷 [data] 必须是 JSON 兼容 Map，并与审计流水
/// 遵守同一脱敏纪律——绝不放 PIN、不放无授权的正文全文（各发射点
/// 在 G2 接线时负责脱敏，事件核心不做二次过滤）。
@immutable
class ControlEvent {
  const ControlEvent({
    required this.seq,
    required this.time,
    required this.type,
    required this.level,
    required this.data,
  });

  /// 单调递增序号（从 1 起）。环形缓冲淘汰旧事件时 seq **不回收**，
  /// 订阅者可能观察到空洞（`poll(since:)` 只承诺返回现存事件）。
  final int seq;

  /// 发射时刻（总线进程本地墙钟）。
  final DateTime time;

  /// 点号命名事件类型，如 `audit.entry`。本期冻结五种（交接单 §G2
  /// 事件表），由接线层以字符串常量登记，核心不内置枚举白名单。
  final String type;

  /// 敏感度：订阅该事件所需的最低 [ControlLevel]，越敏感级别越高。
  /// 订阅 ceiling 低于本级别时，该事件在结果中**物理消失**
  /// （不是打码；seq 空洞允许调用方感知「有事件但无权看」）。
  final ControlLevel level;

  /// JSON 兼容结构化载荷；emit 时做浅不可变，调用方不应再修改。
  final Map<String, Object?> data;

  /// 线传形状（sys.events 的 events 数组元素 / 未来 MCP 同形）：
  /// `{seq,time,type,level,data}`，level 取级别数值。
  Map<String, Object?> toJson() => {
    'seq': seq,
    'time': time.toIso8601String(),
    'type': type,
    'level': level.value,
    'data': data,
  };
}
