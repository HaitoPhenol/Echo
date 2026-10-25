import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:path_provider/path_provider.dart';

import 'auth/audit_log.dart';
import 'auth/auth_session.dart';
import 'auth/pin_store.dart';
import 'channels/adb_control_channel.dart';
import 'commands/auth_commands.dart';
import 'commands/badge_commands.dart';
import 'commands/chat_commands.dart';
import 'commands/console_commands.dart';
import 'commands/diary_commands.dart';
import 'commands/nav_commands.dart';
import 'commands/sys_commands.dart';
import 'control_app_state.dart';
import 'control_bus.dart';
import 'control_registry.dart';
import 'events/event_bus.dart';
import 'events/event_types.dart';
import 'jobs/job_store.dart';
import 'mcp/mcp_server.dart';
import 'mcp/mcp_stdio.dart';
import 'protocol/command_spec.dart';
import '../services/console_stats_service.dart';

/// ECP 控制面装配根（设计 §3.3）。
///
/// 生命周期独立于 widget 树（adb 广播在树外到达）：App 启动时
/// [init] 一次，装配根（`AppServices`/`DiaryModule`）与业务页
/// （`SmartNavScreen`）在各自装配完成后把**与 UI 同源的实例**注册进
/// [registry]。
/// release 构建不挂载任何外部通道（[AdbControlChannel] 仅 debug
/// 挂载，debug-only 命令在 [ControlBus] 注册期物理跳过）。
/// MCP stdio 适配器同样只在 debug 构建且显式带 `--mcp` 时挂载；
/// release 不创建 server/transport（见 [createMcpTransport]）。
class ControlBootstrap with WidgetsBindingObserver {
  // 构造仅本文件 [init] 使用，故字段可直接用私有初始化形式参数
  // （私有命名参数对调用方仍暴露为 adb/mcp）。
  ControlBootstrap._({
    required this.registry,
    required this.bus,
    required this.auth,
    required this.paths,
    required this.appState,
    required this.audit,
    required this.consoleStats,
    required this.events,
    this._adb,
    this._mcp,
  });

  /// 单例：树外的业务页（DiaryPage 等）通过它注册同源服务。
  static ControlBootstrap? instance;

  final ControlRegistry registry;
  final ControlBus bus;
  final AuthManager auth;
  final ControlPaths paths;
  final ControlAppState appState;
  final AuditLog audit;
  final ConsoleStatsService consoleStats;

  /// P4 事件中心（sys.events 经 registry 取用；UiEventBridge 装配
  /// 时也取这同一实例）。
  final ControlEventBus events;

  final AdbControlChannel? _adb;

  /// MCP stdio 适配器：默认 null；仅 debug + `--mcp` 显式挂载。
  final McpStdioTransport? _mcp;

  /// 当前进程是否挂载了 MCP（默认 false；release 恒 false）。
  bool get mcpMounted => _mcp != null;

  /// 挂载的 MCP server（未挂载为 null），测试/诊断用。
  McpServer? get mcpServer => _mcp?.server;

  /// MCP 挂载闸门：仅 debug 构建且显式请求时创建传输。
  ///
  /// 开关是 `main` 传入的 `--mcp` 启动参数；release 构建
  /// [kDebugMode] 恒 false，故 server/transport 物理不创建。
  /// 桌面/调试宿主有 stdin/stdout；移动端不适用，保持默认关闭。
  static McpStdioTransport? createMcpTransport({
    required ControlBus bus,
    required bool requested,
    bool debugMode = kDebugMode,
  }) {
    if (!debugMode || !requested) return null;
    return McpStdioTransport(server: McpServer(bus: bus));
  }

  /// 装配总线并挂载通道；必须在 [runApp] 前 await（确保首条
  /// 冷启动广播到达时 PIN 存储已可读）。
  ///
  /// [enableMcp] 由 `main` 按 `kDebugMode && args.contains('--mcp')`
  /// 传入；默认 false，不创建 MCP server/transport。
  static Future<ControlBootstrap> init({bool enableMcp = false}) async {
    final docs = await getApplicationDocumentsDirectory();
    final paths = ControlPaths(
      controlRoot: Directory('${docs.path}/echo_control'),
    );
    await paths.controlRoot!.create(recursive: true);

    // 事件中心先于审计创建：审计经 onRecord 回调把每条审计转发为
    // audit.entry 事件（auth 层不 import 事件，方向不反转）。
    // tryEmit：关停途中（events 已 close）落审计不再抛错，遥测
    // 安静丢弃，审计本身照常落环。
    final events = ControlEventBus();
    final registry = ControlRegistry();
    final audit = AuditLog(
      onRecord: (entry) => events.tryEmit(
        type: ControlEventType.auditEntry,
        level: ControlLevel.owner,
        data: entry.toJson(),
      ),
    );
    final pinStore = PinStore(directory: paths.controlRoot!);
    final appState = ControlAppState();
    // 读数服务在 runApp 前创建：冷启动 sys.info/console 命令与 UI
    // 读数条同源（设计 §9.3）；sys.info 经 readRaw 取含版本号的
    // 原始字段，console.refresh/UI 走解析后的快照。
    final consoleStats = ConsoleStatsService();
    registry
      ..set(paths)
      ..set(audit)
      ..set(pinStore)
      ..set(appState)
      ..set(consoleStats)
      ..set(ControlDeviceInfo(consoleStats.readRaw));

    final auth = AuthManager(pins: pinStore, auditLog: audit);
    auth.attach(); // 息屏/切后台立即销毁会话
    registry.set(auth);

    // P4：slow 命令后台作业表（sys.job.get 经注册表按类型取用）。
    final jobs = ControlJobStore();
    registry
      ..set(jobs)
      // sys.events 与域命令 emitEvent 各取所需（命令经 bus 句柄）。
      ..set(events);

    final bus = ControlBus(
      buildMode: kDebugMode ? ControlBuildMode.debug : ControlBuildMode.release,
      services: registry,
      authorizer: auth,
      auditLog: audit,
      jobs: jobs,
      events: events,
    );
    bus.registerAll([
      ...buildSysCommands(),
      ...buildAuthCommands(),
      ...buildNavCommands(),
      ...buildDiaryCommands(),
      // P2：chat/console/badge 三域。其 UI 同源服务中，
      // ChatStore/ChatSessionController 由装配根 AppServices 创建并注册，
      // NavBadgeService 由 SmartNavScreen 注册；ConsoleStatsService 已在
      // 上方 runApp 前注册。
      ...buildChatCommands(),
      ...buildConsoleCommands(),
      ...buildBadgeCommands(),
    ]);

    // adb 物理入口仅 debug 包挂载；release 的 MethodChannel 上
    // 不存在 exec handler，广播接收器也只在 debug 源集注册。
    AdbControlChannel? adb;
    if (kDebugMode) {
      adb = AdbControlChannel(bus: bus)..attach();
    }

    // MCP stdio：默认不创建（enableMcp 由 main 的 --mcp 决定）；
    // release 构建 kDebugMode 恒 false，物理不挂载。
    final mcp = createMcpTransport(bus: bus, requested: enableMcp);
    mcp?.attach();

    final bootstrap = ControlBootstrap._(
      registry: registry,
      bus: bus,
      auth: auth,
      paths: paths,
      appState: appState,
      audit: audit,
      consoleStats: consoleStats,
      events: events,
      adb: adb,
      mcp: mcp,
    );
    WidgetsBinding.instance.addObserver(bootstrap);
    instance = bootstrap;
    return bootstrap;
  }

  /// 测试缝：用测试夹具已装配的总线/服务构造实例并置为 [instance]，
  /// 供读取 `ControlBootstrap.instance` 的宿主（AppServices/
  /// SmartNavScreen）在 widget 测试中整树挂载。生产路径只走 [init]。
  @visibleForTesting
  static ControlBootstrap attachTestInstance({
    required ControlRegistry registry,
    required ControlBus bus,
    required AuthManager auth,
    required ControlPaths paths,
    required ControlAppState appState,
    required AuditLog audit,
    required ConsoleStatsService consoleStats,
    ControlEventBus? events,
  }) {
    final bootstrap = ControlBootstrap._(
      registry: registry,
      bus: bus,
      auth: auth,
      paths: paths,
      appState: appState,
      audit: audit,
      consoleStats: consoleStats,
      // widget 测试不断言事件：给独立空实例即可，不碰夹具事件中心。
      events: events ?? ControlEventBus(),
    );
    instance = bootstrap;
    return bootstrap;
  }

  /// 测试缝：摘除测试实例（不触碰观察者/通道，夹具各自 dispose）。
  @visibleForTesting
  static void detachTestInstance() {
    instance = null;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    appState.lifecycle = switch (state) {
      AppLifecycleState.paused => 'background',
      _ => 'foreground',
    };
  }

  /// 测试/热卸载用：摘除监听与通道（生产进程内不调用）。
  Future<void> dispose() async {
    WidgetsBinding.instance.removeObserver(this);
    auth.detach();
    _adb?.detach();
    await _mcp?.detach();
    consoleStats.dispose();
    // 关事件中心：在飞 sys.events 长轮询以空集结束。UI 事件适配器
    // 由 SmartNavScreen 随其服务自行拆除（生命周期归屏幕）。
    events.close();
    instance = null;
  }
}
