import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'src/app/echo_app.dart';
import 'src/control/bootstrap.dart';

/// 应用入口：先装配 ECP 控制面（PIN 存储需在首条广播前就绪），
/// 再挂载 Echo 根组件。
///
/// MCP stdio 适配器不默认启动：仅 debug 构建且启动参数含 `--mcp`
/// 时挂载（桌面/调试宿主；移动端无标准输入，保持不挂载）。release
/// 构建 `kDebugMode` 恒 false，物理不创建 server/transport。
///
/// 崩溃钩子（G8）：启动与运行放进 [runZonedGuarded]，并接管
/// [FlutterError.onError]，让框架错误与 zone 内未捕获的异步错误都被
/// 记录而非静默丢失。当前无远端上报后端，统一走 debugPrint。
Future<void> main(List<String> args) async {
  await runZonedGuarded(
    () async {
      WidgetsFlutterBinding.ensureInitialized();

      final previousOnError = FlutterError.onError;
      FlutterError.onError = (details) {
        previousOnError?.call(details); // 保留默认控制台输出
        // 崩溃上报入口：接入后端时在此发送（当前仅记录）。
        debugPrint('[crash] FlutterError: ${details.exceptionAsString()}');
      };

      await ControlBootstrap.init(
        // 显式开关：默认关闭；release 分支由 kDebugMode 物理挡住。
        enableMcp: kDebugMode && args.contains('--mcp'),
      );
      runApp(const EchoApp());
    },
    (error, stack) {
      // zone 内未被 Flutter 框架捕获的异步错误（如平台通道 Future 异常）。
      debugPrint('[crash] uncaught async: $error\n$stack');
    },
  );
}
