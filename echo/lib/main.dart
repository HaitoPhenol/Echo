import 'dart:async';

import 'package:flutter/material.dart';

import 'src/app/echo_app.dart';
import 'src/control/bootstrap.dart';

/// 应用入口：先装配 ECP 控制面（PIN 存储需在首条广播前就绪），
/// 再挂载 Echo 根组件。
///
/// 崩溃钩子（G8）：启动与运行放进 [runZonedGuarded]，并接管
/// [FlutterError.onError]，让框架错误与 zone 内未捕获的异步错误都被
/// 记录而非静默丢失。当前无远端上报后端，统一走 debugPrint。
Future<void> main() async {
  await runZonedGuarded(() async {
    WidgetsFlutterBinding.ensureInitialized();

    final previousOnError = FlutterError.onError;
    FlutterError.onError = (details) {
      previousOnError?.call(details); // 保留默认控制台输出
      // 崩溃上报入口：接入后端时在此发送（当前仅记录）。
      debugPrint('[crash] FlutterError: ${details.exceptionAsString()}');
    };

    await ControlBootstrap.init();
    runApp(const EchoApp());
  }, (error, stack) {
    // zone 内未被 Flutter 框架捕获的异步错误（如平台通道 Future 异常）。
    debugPrint('[crash] uncaught async: $error\n$stack');
  });
}
