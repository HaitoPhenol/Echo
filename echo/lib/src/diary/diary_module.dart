import 'dart:io';

import 'package:path_provider/path_provider.dart';

import '../common/domain_event_bus.dart';
import '../control/bootstrap.dart';
import 'data/diary_clock.dart';
import 'data/diary_data_provider.dart';
import 'data/diary_repository.dart';
import 'data/persistent_diary_repository.dart';
import 'diary_navigator.dart';
import 'export/diary_export_service.dart';
import 'template/daily_default_template.dart';
import 'template/diary_composer.dart';

/// 日记模块装配体：把「存储根目录 → 仓储 → 模板 → 成稿器 → 导出服务」
/// 的构造与 ECP 注册从 UI 层移出。
///
/// 界面只消费本模块产出的实例（经 [DiaryRepositoryScope] 等注入），
/// 不再直接获取应用文档目录，也不直接打开 sqflite——「UI 不碰存储」
/// 的底线由本类兜住。
///
/// 同时承担日记领域的**事件发布者**：仓储任何变更都在 [domainEvents]
/// 上广播 [DiaryChangedEvent]。发布者不持有任何订阅者引用，订阅方
/// （如导航锚点同步）由装配处自行接入。
///
/// 测试注入缝保持不变：时钟/数据源/仓储/导出服务均可由调用方替换，
/// 未注入的部件在这里按生产口径装配。
class DiaryModule {
  DiaryModule._({
    required this.clock,
    required this.dataProvider,
    required this.repository,
    required this.composer,
    required this.exportService,
    required this.ownsRepository,
    this.storageRoot,
  }) : domainEvents = DomainEventBus();

  final DiaryClock clock;
  final DiaryDataProvider dataProvider;
  final DiaryRepository repository;
  final DiaryComposer composer;
  final DiaryExportService exportService;

  /// 日记领域事件总线（模块终身持有，随 [dispose] 关闭）。
  final DomainEventBus domainEvents;

  /// 仓储是否由本模块打开（生产持久仓储）。外部注入的仓储由调用方
  /// 负责释放，本模块 dispose 不越权关闭。
  final bool ownsRepository;

  /// 生产仓储的根目录 `<应用文档目录>/echo_diary`；
  /// 注入仓储（测试/预览）时为 null，ECP 的 `sys.info` 不上报路径。
  final Directory? storageRoot;

  bool _disposed = false;

  /// 装配并打开日记模块。
  ///
  /// [seedDebugData] 仅在 debug 首装时灌入演示数据（release 空仓）。
  static Future<DiaryModule> open({
    DiaryClock? clock,
    DiaryDataProvider? dataProvider,
    DiaryRepository? repository,
    DiaryExportService? exportService,
    bool seedDebugData = false,
  }) async {
    final resolvedClock = clock ?? DiaryClock();
    final resolvedProvider = dataProvider ?? FakeDiaryDataProvider();
    final root = repository == null ? await _resolveStorageRoot() : null;
    final resolvedRepository =
        repository ??
        await PersistentDiaryRepository.open(
          root: root!,
          clock: resolvedClock,
          seedDebugData: seedDebugData,
        );
    final template = await DailyDefaultTemplate.loadAsset();
    final composer = DiaryComposer(
      template: template,
      provider: resolvedProvider,
      idGenerator: resolvedRepository.idGenerator,
      // 显式走日记日时钟：ECP sys.clock.set 拨钟后，成稿时间戳与
      // 「今天」判定随之同步（同一实例，同路原则）。
      now: resolvedClock.now,
    );
    final module = DiaryModule._(
      clock: resolvedClock,
      dataProvider: resolvedProvider,
      repository: resolvedRepository,
      composer: composer,
      exportService:
          exportService ?? DiaryExportService(repository: resolvedRepository),
      ownsRepository: repository == null,
      storageRoot: root,
    );
    module._registerWithControl();
    module._watchRepository();
    return module;
  }

  /// 仓储变更 → 领域事件。发布者只广播事实，不知道谁在听。
  void _watchRepository() => repository.addListener(_onRepositoryChanged);

  void _onRepositoryChanged() =>
      domainEvents.publish(const DiaryChangedEvent());

  /// ECP 接线：把与 UI 完全同源的实例注册给控制面
  /// （widget 测试未走 ControlBootstrap.init 时 instance 为 null，静默跳过）。
  ///
  /// 同路原则：命令调的就是界面正在用的同一个时钟/仓储/成稿器/导出服务。
  void _registerWithControl() {
    final control = ControlBootstrap.instance;
    if (control == null) return;
    control.paths.diaryRoot = storageRoot;
    control.registry
      ..set(clock)
      ..set(repository)
      ..set(composer)
      ..set(exportService);
  }

  /// 注册内层路由控制器（`diary.goto` 入口）。
  ///
  /// 由日记页在拿到导航状态后调用——控制器就是页面 State 本身，
  /// 不属于模块可自建的部分。
  void registerNavigator(DiaryNavigatorController controller) {
    ControlBootstrap.instance?.registry.set<DiaryNavigatorController>(
      controller,
    );
  }

  /// 释放模块：解除 ControlRegistry 上的同源实例、关闭自有仓储。
  ///
  /// 幂等；外部注入的仓储不关闭（由注入方负责）。调用时机由装配根
  /// （[AppServices] / 自装配的日记页）决定。
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;

    this.repository.removeListener(_onRepositoryChanged);
    await domainEvents.dispose();

    final control = ControlBootstrap.instance;
    final registry = control?.registry;
    registry
      ?..unset<DiaryClock>()
      ..unset<DiaryRepository>()
      ..unset<DiaryComposer>()
      ..unset<DiaryExportService>()
      ..unset<DiaryNavigatorController>();
    if (storageRoot != null) control?.paths.diaryRoot = null;

    if (!ownsRepository) return;
    final repository = this.repository;
    if (repository is PersistentDiaryRepository) {
      await repository.close();
    }
    repository.dispose();
  }

  /// 仓储根目录：`<应用文档目录>/echo_diary`（open 内负责创建）。
  static Future<Directory> _resolveStorageRoot() async {
    final docs = await getApplicationDocumentsDirectory();
    return Directory('${docs.path}/echo_diary');
  }
}
