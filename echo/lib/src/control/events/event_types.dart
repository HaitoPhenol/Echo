import '../protocol/command_spec.dart';

/// P4 冻结事件类型与敏感度登记（命令手册 §1.5）。
///
/// 本期冻结五种；**新增类型＝协议变更**：先改手册 §1.5 表格与
/// `sys.events --types` 契约，再在此登记。接线层（总线收口 /
/// AuditLog 回调 / 装配适配器）只能发射本表内的类型，
/// `sys.events --types` 的白名单校验也以本表为准。
///
/// 级别含义与命令级别同构：订阅通道的有效级别低于事件级别时，
/// 事件在结果中**物理消失**（见 [ControlEvent] 注释）。
abstract final class ControlEventType {
  /// AuditLog 每落一条审计（≥2 级命令成败、解锁事件、PIN 变更等）。
  /// data＝AuditEntry 脱敏后的 JSON。
  static const String auditEntry = 'audit.entry';

  /// 总线执行收口每跑完一条**已通过裁决**的命令（成功/业务失败/
  /// 超时，含后台作业终态）。USAGE/未知命令/鉴权拒绝不发。
  /// data＝cmd/ok/error?/ms/nonce?/jobId?。
  static const String commandFinished = 'command.finished';

  /// diary.export handler 成功产出 .sy.zip。
  /// data＝path/entries/sizeBytes/notebook。
  static const String diaryExportCompleted = 'diary.export.completed';

  /// ChatStore.addIncoming 经装配适配器转发。
  /// data＝id/nickname/preview/text（首条正文，owner 可读）。
  static const String chatIncoming = 'chat.incoming';

  /// 导航页切换（装配适配器页号 diff 后）。data＝index/page。
  static const String navChanged = 'nav.changed';

  /// 冻结类型 → 订阅所需最低级别（敏感度）。
  static const Map<String, ControlLevel> levelOf = {
    auditEntry: ControlLevel.owner,
    commandFinished: ControlLevel.owner,
    diaryExportCompleted: ControlLevel.user,
    chatIncoming: ControlLevel.owner,
    navChanged: ControlLevel.guest,
  };

  /// 全部冻结类型（手册一致性/帮助信息备用）。
  static Set<String> get all => levelOf.keys.toSet();
}
