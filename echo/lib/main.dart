import 'package:flutter/material.dart';

import 'src/app/echo_app.dart';
import 'src/control/bootstrap.dart';

/// 应用入口：先装配 ECP 控制面（PIN 存储需在首条广播前就绪），
/// 再挂载 Echo 根组件。
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await ControlBootstrap.init();
  runApp(const EchoApp());
}
