import 'control_error.dart';

/// ECP 统一返回信封（设计 §8）：所有通道同一份 JSON 形状。
///
/// 成功：`{ok, cmd, ms, result}`；失败：`{ok, cmd, ms, error}`。
/// [nonce] 是 adb 通道的传输层回响（logcat 结果匹配用），仅在该
/// 通道出现，不属于业务契约。
class ControlEnvelope {
  const ControlEnvelope({
    required this.ok,
    required this.cmd,
    required this.ms,
    this.result,
    this.error,
    this.nonce,
  });

  /// 失败信封的便捷构造。
  factory ControlEnvelope.failure(
    String cmd,
    int ms,
    ControlException error, {
    String? nonce,
  }) {
    return ControlEnvelope(
      ok: false,
      cmd: cmd,
      ms: ms,
      error: error,
      nonce: nonce,
    );
  }

  final bool ok;
  final String cmd;

  /// 处理耗时（毫秒，总线计时；含参数校验与鉴权）。
  final int ms;
  final Map<String, Object?>? result;
  final ControlException? error;

  /// adb 通道逐请求回响（其他通道为 null）。
  final String? nonce;

  /// 失败时的进程退出码（成功 0）；供 adb 接收器与包装脚本使用。
  int get exitCode => ok ? 0 : error!.code.exitCode;

  Map<String, Object?> toJson() => {
    'ok': ok,
    'cmd': cmd,
    'ms': ms,
    if (ok) 'result': result,
    if (!ok) 'error': error!.toJson(),
    if (nonce != null) 'nonce': nonce,
  };
}
