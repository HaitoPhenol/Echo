import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

import 'auth/audit_log.dart';
import 'auth/auth_session.dart';
import 'auth/pin_store.dart';
import 'channels/adb_control_channel.dart';
import 'commands/auth_commands.dart';
import 'commands/diary_commands.dart';
import 'commands/nav_commands.dart';
import 'commands/sys_commands.dart';
import 'control_app_state.dart';
import 'control_bus.dart';
import 'control_registry.dart';
import 'protocol/command_spec.dart';

/// ECP 控制面装配根（设计 §3.3）。
///
/// 生命周期独立于 widget 树（adb 广播在树外到达）：App 启动时
/// [init] 一次，业务页（DiaryPage / SmartNavScreen）在自身
/// bootstrap 完成后把**与 UI 同源的实例**注册进 [registry]。
/// release 构建不挂载任何外部通道（[AdbControlChannel] 仅 debug
/// 挂载，debug-only 命令在 [ControlBus] 注册期物理跳过）。
class ControlBootstrap with WidgetsBindingObserver {
  // 构造仅本文件 [init] 使用，故字段可直接用私有初始化形式参数。
  ControlBootstrap._({
    required this.registry,
    required this.bus,
    required this.auth,
    required this.paths,
    required this.appState,
    required this.audit,
    // 字段私有而命名参数不允许下划线开头，这里保留显式赋值。
    AdbControlChannel? adb,
    // ignore: prefer_initializing_formals
  }) : _adb = adb;

  /// 单例：树外的业务页（DiaryPage 等）通过它注册同源服务。
  static ControlBootstrap? instance;

  final ControlRegistry registry;
  final ControlBus bus;
  final AuthManager auth;
  final ControlPaths paths;
  final ControlAppState appState;
  final AuditLog audit;
  final AdbControlChannel? _adb;

  /// 装配总线并挂载通道；必须在 [runApp] 前 await（确保首条
  /// 冷启动广播到达时 PIN 存储已可读）。
  static Future<ControlBootstrap> init() async {
    final docs = await getApplicationDocumentsDirectory();
    final paths = ControlPaths(
      controlRoot: Directory('${docs.path}/echo_control'),
    );
    await paths.controlRoot!.create(recursive: true);

    final registry = ControlRegistry();
    final audit = AuditLog();
    final pinStore = PinStore(directory: paths.controlRoot!);
    final appState = ControlAppState();
    registry
      ..set(paths)
      ..set(audit)
      ..set(pinStore)
      ..set(appState)
      ..set(ControlDeviceInfo(_readDeviceSnapshot));

    final auth = AuthManager(pins: pinStore, auditLog: audit);
    auth.attach(); // 息屏/切后台立即销毁会话
    registry.set(auth);

    final bus = ControlBus(
      buildMode: kDebugMode
          ? ControlBuildMode.debug
          : ControlBuildMode.release,
      services: registry,
      authorizer: auth,
      auditLog: audit,
    );
    bus.registerAll([
      ...buildSysCommands(),
      ...buildAuthCommands(),
      ...buildNavCommands(),
      ...buildDiaryCommands(),
    ]);

    // adb 物理入口仅 debug 包挂载；release 的 MethodChannel 上
    // 不存在 exec handler，广播接收器也只在 debug 源集注册。
    AdbControlChannel? adb;
    if (kDebugMode) {
      adb = AdbControlChannel(bus: bus)..attach();
    }

    final bootstrap = ControlBootstrap._(
      registry: registry,
      bus: bus,
      auth: auth,
      paths: paths,
      appState: appState,
      audit: audit,
      adb: adb,
    );
    WidgetsBinding.instance.addObserver(bootstrap);
    instance = bootstrap;
    return bootstrap;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    appState.lifecycle = switch (state) {
      AppLifecycleState.paused => 'background',
      _ => 'foreground',
    };
  }

  /// 复用既有 `echo/device_stats` 通道（MainActivity.readDeviceStats），
  /// sys.info 不另造读数；通道异常时退回空快照，命令仍返回版本字段
  /// 以外的最小现场（设备信息缺失不影响链路自检）。
  static Future<Map<String, Object?>> _readDeviceSnapshot() async {
    try {
      final raw = await const MethodChannel('echo/device_stats')
          .invokeMethod<Map>('snapshot');
      return raw?.cast<String, Object?>() ?? const {};
    } on PlatformException {
      return const {};
    } on MissingPluginException {
      return const {};
    }
  }

  /// 测试/热卸载用：摘除监听与通道（生产进程内不调用）。
  Future<void> dispose() async {
    WidgetsBinding.instance.removeObserver(this);
    auth.detach();
    _adb?.detach();
    instance = null;
  }
}
