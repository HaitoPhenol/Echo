import 'dart:io';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';

import 'package:echo/src/control/auth/audit_log.dart';
import 'package:echo/src/control/auth/auth_session.dart';
import 'package:echo/src/control/auth/pin_store.dart';
import 'package:echo/src/control/commands/auth_commands.dart';
import 'package:echo/src/control/commands/badge_commands.dart';
import 'package:echo/src/control/commands/chat_commands.dart';
import 'package:echo/src/control/commands/console_commands.dart';
import 'package:echo/src/control/commands/diary_commands.dart';
import 'package:echo/src/control/commands/nav_commands.dart';
import 'package:echo/src/control/commands/sys_commands.dart';
import 'package:echo/src/control/control_app_state.dart';
import 'package:echo/src/control/control_bus.dart';
import 'package:echo/src/control/control_registry.dart';
import 'package:echo/src/control/protocol/command_spec.dart';
import 'package:echo/src/control/protocol/control_envelope.dart';
import 'package:echo/src/services/chat_session_controller.dart';
import 'package:echo/src/services/chat_store.dart';
import 'package:echo/src/services/console_stats_service.dart';
import 'package:echo/src/services/nav_badge_service.dart';
import 'package:echo/src/diary/data/diary_clock.dart';
import 'package:echo/src/diary/data/diary_data_provider.dart';
import 'package:echo/src/diary/data/diary_repository.dart';
import 'package:echo/src/diary/data/in_memory_diary_repository.dart';
import 'package:echo/src/diary/export/diary_export_service.dart';
import 'package:echo/src/diary/sy/sy_id.dart';
import 'package:echo/src/diary/template/daily_default_template.dart';
import 'package:echo/src/diary/template/diary_composer.dart';

/// ECP 协议/命令测试共用夹具：内存日记三件套（时钟/仓储/composer）
/// + 导出服务（落临时目录）+ 完整总线（四域命令全注册）。
///
/// 与生产唯一差别：PIN 迭代数调小（PBKDF2 语义不变，测试快）、
/// 导出分享通道是假的（命令路径本就不调用分享）、设备快照留空。
class ControlHarness {
  ControlHarness._({
    required this.tempDir,
    required this.paths,
    required this.registry,
    required this.audit,
    required this.pins,
    required this.auth,
    required this.bus,
    required this.clock,
    required this.repo,
    required this.composer,
    required this.exporter,
    required this.appState,
    required this.chatStore,
    required this.chatSession,
    required this.badges,
    required this.consoleStats,
  });

  final Directory tempDir;
  final ControlPaths paths;
  final ControlRegistry registry;
  final AuditLog audit;
  final PinStore pins;
  final AuthManager auth;
  final ControlBus bus;
  final DiaryClock clock;
  final InMemoryDiaryRepository repo;
  final DiaryComposer composer;
  final DiaryExportService exporter;
  final ControlAppState appState;

  /// P2 UI 同源服务（chat.* / badge.* / console.* 命令操作的实例）。
  final ChatStore chatStore;
  final ChatSessionController chatSession;
  final NavBadgeService badges;
  final ConsoleStatsService consoleStats;

  /// 可变墙钟（拨钟测试直接改）；未 override 时 [DiaryClock.now] 读它。
  late DateTime wallTime;

  static Future<ControlHarness> create({
    ControlBuildMode buildMode = ControlBuildMode.debug,
    DateTime? startTime,
  }) async {
    TestWidgetsFlutterBinding.ensureInitialized();
    final tempDir = await Directory.systemTemp.createTemp('echo-ecp-test');

    final wall = startTime ?? DateTime(2026, 10, 12, 10, 0);
    final paths = ControlPaths(
      diaryRoot: Directory('${tempDir.path}/echo_diary')
        ..createSync(recursive: true),
      controlRoot: Directory('${tempDir.path}/echo_control')
        ..createSync(recursive: true),
    );
    final registry = ControlRegistry();
    final audit = AuditLog();
    final pins = PinStore(
      directory: paths.controlRoot!,
      // 迭代数不影响正确性（记录自带 rounds），测试取小值加速。
      iterations: 1000,
    );
    final appState = ControlAppState();

    late final ControlHarness h;
    final clock = DiaryClock(now: () => h.wallTime);
    final repo = InMemoryDiaryRepository(clock: clock, seedDebugData: false);
    final template = await DailyDefaultTemplate.loadAsset();
    final composer = DiaryComposer(
      template: template,
      // 生产同款 Fake provider：取不到快照时返回 null，
      // composer 容忍，命令路径只验证结构不验证快照内容。
      provider: FakeDiaryDataProvider(),
      idGenerator: SyIdGenerator(random: Random(0xEC0)),
      now: clock.now,
    );
    final exporter = DiaryExportService(
      repository: repo,
      shareChannel: (_) async {}, // ECP 导出只打包，不分享。
      tempDirectory: () async => tempDir,
      now: clock.now,
    );

    // P2 服务（与生产 SmartNavScreen/bootstrap 同源的实例类型）：
    // 读数服务关闭自动轮询（假环境无 Timer 泄漏），reader 同时充当
    // sys.info 的设备信息来源；聊天/锚点服务页规模与四目的地一致。
    final consoleStats = ConsoleStatsService(
      autoStart: false,
      reader: () async => <String, Object?>{
        'model': 'test-phone',
        'osVersion': 'T1',
        'version': '0.9.0',
        'buildNumber': 34,
        'tempC': 31.0,
        'powerW': 2.5,
      },
    );
    final chatStore = ChatStore(now: () => h.wallTime);
    final chatSession = ChatSessionController(chatStore);
    final badges = InMemoryNavBadgeService(pageCount: 4);

    registry
      ..set(paths)
      ..set(audit)
      ..set(pins)
      ..set(appState)
      ..set(clock)
      // 命令按抽象类型 DiaryRepository 解析；生产端 diary_page 同样以
      // 抽象类型注册，替换为持久化仓储时命令零改动。
      ..set<DiaryRepository>(repo)
      ..set(composer)
      ..set(exporter)
      ..set(consoleStats)
      ..set(ControlDeviceInfo(consoleStats.readRaw))
      ..set(chatStore)
      ..set(chatSession)
      ..set<NavBadgeService>(badges);

    final auth = AuthManager(
      pins: pins,
      auditLog: audit,
      now: () => h.wallTime,
    );
    auth.attach();
    registry.set(auth);

    final bus =
        ControlBus(
            buildMode: buildMode,
            services: registry,
            authorizer: auth,
            auditLog: audit,
          )
          ..registerAll(buildSysCommands())
          ..registerAll(buildAuthCommands())
          ..registerAll(buildNavCommands())
          ..registerAll(buildDiaryCommands())
          ..registerAll(buildChatCommands())
          ..registerAll(buildConsoleCommands())
          ..registerAll(buildBadgeCommands());

    h = ControlHarness._(
      tempDir: tempDir,
      paths: paths,
      registry: registry,
      audit: audit,
      pins: pins,
      auth: auth,
      bus: bus,
      clock: clock,
      repo: repo,
      composer: composer,
      exporter: exporter,
      appState: appState,
      chatStore: chatStore,
      chatSession: chatSession,
      badges: badges,
      consoleStats: consoleStats,
    )..wallTime = wall;
    return h;
  }

  /// 便捷执行（参数已按线格式构造时用）。
  Future<ControlEnvelope> exec(
    String cmd, {
    ControlChannel channel = ControlChannel.adb,
    Map<String, Object?>? args,
    bool confirmed = false,
  }) => bus.execute(
    channel: channel,
    cmd: cmd,
    rawArgs: args,
    confirmed: confirmed,
    nonce: 'n',
  );

  /// 成功结果断言便捷器。
  Future<Map<String, Object?>> execResult(
    String cmd, {
    ControlChannel channel = ControlChannel.adb,
    Map<String, Object?>? args,
    bool confirmed = false,
  }) async {
    final env = await exec(
      cmd,
      channel: channel,
      args: args,
      confirmed: confirmed,
    );
    expect(env.ok, isTrue, reason: env.error?.toString());
    return env.result!;
  }

  Future<void> dispose() async {
    auth.detach();
    chatSession.dispose();
    chatStore.dispose();
    badges.dispose();
    consoleStats.dispose();
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  }
}
