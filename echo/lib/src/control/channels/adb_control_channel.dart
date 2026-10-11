import 'dart:convert';

import 'package:flutter/services.dart';

import '../control_bus.dart';
import '../protocol/command_spec.dart';
import '../protocol/control_envelope.dart';

/// adb 通道适配（设计 §3.2/§7）：唯一的物理入口是
/// `echo/control` MethodChannel 的 `exec` 方法，由 debug 源集的
/// `DebugControlReceiver` 把广播参数转发过来。
///
/// 通道层不做业务判断：只负责 JSON 解码、调用 [ControlBus.execute]、
/// 回传信封 JSON。P1 仅 debug 包挂载（bootstrap 用 kDebugMode 守卫）。
class AdbControlChannel {
  AdbControlChannel({required this.bus});

  static const MethodChannel _channel = MethodChannel('echo/control');

  final ControlBus bus;

  /// 挂载 `exec` 处理器（重复挂载幂等，Handler 直接覆盖）。
  void attach() => _channel.setMethodCallHandler(_handle);

  /// 摘除（热卸载/测试用）。
  void detach() => _channel.setMethodCallHandler(null);

  Future<Object?> _handle(MethodCall call) async {
    if (call.method != 'exec') {
      // 未实现的方法走平台默认 notImplemented。
      throw MissingPluginException();
    }
    final raw = call.arguments;
    if (raw is! Map) {
      throw PlatformException(
        code: 'BAD_REQUEST',
        message: 'exec 参数必须是 Map',
      );
    }

    final cmd = raw['cmd'];
    if (cmd is! String || cmd.isEmpty) {
      throw PlatformException(code: 'BAD_REQUEST', message: '缺少 cmd');
    }

    // args 两种形态都收：包装脚本传 JSON 字符串（广播 extra 只能
    // 带字符串），测试/未来直连可传 Map。
    final rawArgs = raw['args'];
    Map<String, Object?>? args;
    if (rawArgs is String && rawArgs.isNotEmpty) {
      final decoded = jsonDecode(rawArgs);
      if (decoded is! Map) {
        throw PlatformException(
          code: 'BAD_REQUEST',
          message: 'args 解码后必须是 JSON 对象',
        );
      }
      args = decoded.cast<String, Object?>();
    } else if (rawArgs is Map) {
      args = rawArgs.cast<String, Object?>();
    }

    final envelope = await bus.execute(
      channel: ControlChannel.adb,
      cmd: cmd,
      rawArgs: args,
      confirmed: raw['confirmed'] == true,
      nonce: raw['nonce'] as String?,
    );
    // 广播结果只能承载字符串（setResultData），Kotlin 侧拿到后
    // 原样回传并落 logcat；Map 经 StandardMessageCodec 虽能过
    // MethodChannel，却会让接收器报「回包不是字符串」。
    return jsonEncode(envelope.toJson());
  }
}

/// 给接收器侧文档引用的静态信息（通道名/动作名/extra 键），
/// 与 debug 源集 Kotlin 常量逐字一致，变更需两侧同改。
abstract final class AdbControlWire {
  static const String channelName = 'echo/control';
  static const String methodExec = 'exec';
  static const String action = 'com.everse.echo.CTRL';
  static const String extraCmd = 'cmd';
  static const String extraArgs = 'args';
  static const String extraConfirm = 'confirm';
  static const String extraNonce = 'nonce';

  // 抑制 unused（ControlEnvelope 类型在文档签名中引用）。
  static Type get envelopeType => ControlEnvelope;
}
