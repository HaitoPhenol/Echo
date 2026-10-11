/// ECP 统一错误码与进程退出码（设计文档 §8）。
///
/// 错误码是跨通道契约（adb / slash / 未来 MCP 共用），名称一经发布
/// 同样冻结；新增只追加、不改既有码的语义。
enum ControlErrorCode {
  /// 未知命令（manifest 中不存在，或当前构建不可见）。退出码 127。
  unknownCommand('UNKNOWN_COMMAND', 127),

  /// 用法错误：参数缺失 / 类型不符 / 未知参数。退出码 2。
  usage('USAGE', 2),

  /// 需要提权：当前通道会话级别不足。退出码 3。
  authRequired('AUTH_REQUIRED', 3),

  /// 凭据错误：PIN 校验失败。退出码 3。
  authDenied('AUTH_DENIED', 3),

  /// 连续失败触发冷却，需等待。退出码 3。
  authCooldown('AUTH_COOLDOWN', 3),

  /// 尚未设置 PIN（引导首次初始化）。退出码 3。
  pinNotSet('PIN_NOT_SET', 3),

  /// 3 级命令缺少 `--confirm` 显式确认。退出码 4。
  confirmRequired('CONFIRM_REQUIRED', 4),

  /// 状态冲突：非法状态迁移 / 重复操作 / 服务尚未就绪等。退出码 4。
  conflict('CONFLICT', 4),

  /// 目标不存在。退出码 5。
  notFound('NOT_FOUND', 5),

  /// 没有可导出的 draft（业务失败而非冲突）。退出码 1。
  exportEmpty('EXPORT_EMPTY', 1),

  /// 执行超时。退出码 124。
  timeout('TIMEOUT', 124),

  /// 其他业务异常（兜底）。退出码 1。
  business('BUSINESS', 1);

  const ControlErrorCode(this.wire, this.exitCode);

  /// 信封 `error.code` 中使用的有线名称。
  final String wire;

  /// `scripts/echo-cmd` 的进程退出码。
  final int exitCode;
}

/// 命令执行失败的统一异常：各域适配器只抛本类型（或 [ArgumentError]/
/// [StateError] 等约定内建异常，由总线映射），不直接拼装错误信封。
class ControlException implements Exception {
  const ControlException(
    this.code,
    this.message, {
    this.need,
    this.elevate,
    this.retryAfterMs,
  });

  final ControlErrorCode code;
  final String message;

  /// AUTH_REQUIRED 时携带：所需级别与提权命令名。
  final int? need;
  final String? elevate;

  /// AUTH_COOLDOWN 时携带：剩余冷却毫秒。
  final int? retryAfterMs;

  /// 序列化为信封 `error` 对象。
  Map<String, Object?> toJson() => {
        'code': code.wire,
        'message': message,
        if (need != null) 'need': need,
        if (elevate != null) 'elevate': elevate,
        if (retryAfterMs != null) 'retryAfterMs': retryAfterMs,
      };

  @override
  String toString() => '${code.wire}: $message';
}
