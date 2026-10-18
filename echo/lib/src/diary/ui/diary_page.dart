import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

import '../data/diary_clock.dart';
import '../data/diary_data_provider.dart';
import '../data/diary_repository.dart';
import '../data/persistent_diary_repository.dart';
import '../export/diary_export_service.dart';
import '../template/daily_default_template.dart';
import '../template/diary_composer.dart';
import '../../control/bootstrap.dart';
import '../../services/nav_badge_service.dart';
import 'browser/day_editor_page.dart';
import 'browser/month_list_page.dart';
import 'browser/year_list_page.dart';
import 'diary_composer_scope.dart';
import 'diary_export_scope.dart';
import 'diary_route.dart';

/// 日记模块根页：内嵌一个 Navigator 承载 年→月→日→编辑器 四级栈，
/// 系统返回键由 [PopScope] 收口到内层栈；栈底时不拦截，交给系统
/// （与外层横向翻页互不干扰——内层路由无边缘手势，见 DiarySlideRoute）。
///
/// 仓储/时钟/数据源/composer 均在本页 State 创建并随页面常驻：
/// M5 起生产仓储异步开库（sqflite meta + 应用目录 .sy），随后加载
/// 默认模板，装配完成后 fire-and-forget 执行「今天自动成稿 +
/// 早于今天的空草稿清理」（§5.2 硬裁定 2/4）。
class DiaryPage extends StatefulWidget {
  const DiaryPage({
    super.key,
    this.clock,
    this.dataProvider,
    this.repository,
    this.exportService,
    this.preEnterToday = false,
    this.badgeDestinationId = 'notes',
  });

  /// 测试注入缝：固定时钟/数据源/仓储/导出服务；生产环境全部走真实装配。
  final DiaryClock? clock;
  final DiaryDataProvider? dataProvider;
  final DiaryRepository? repository;
  final DiaryExportService? exportService;

  /// 本页在导航锚点服务中的目的地 id（由 `nav_destination.dart` 的
  /// notes 分支注入 `spec.id`）：导出提醒据此上报红锚点。
  ///
  /// 由外部注入而非本页硬编码页名，页序/页名调整时不会失真。
  final String badgeDestinationId;

  /// 开屏预进今日编辑页：为 true 时内层路由栈首帧即
  /// 「年列表 → 今日编辑页」两层（初始路由一次性建好、无入场动画）。
  ///
  /// 日记页在生产里随导航页面轨道**离屏常驻**（见 nav_destination.dart），
  /// app 一启动本页就 bootstrap 完成，故此处预进发生在用户尚未切到笔记页时
  /// ——「后台直接进入今日日记」；用户横滑到笔记页即落在今日编辑页，无需再
  /// 点 年→月→日。返回语义不变：返回仍回到年列表（栈形态与手动进入一致）。
  ///
  /// 只在 app 打开（进程首启）时发生一次：从后台恢复不会重跑 bootstrap，
  /// 不会把用户已经导航到的位置顶掉。
  ///
  /// 仅生产环境打开（`nav_destination.dart` 按「无测试注入仓储」判定）；
  /// 测试默认关闭，保持从年列表开始的既有断言基线。
  final bool preEnterToday;

  @override
  State<DiaryPage> createState() => DiaryPageState();
}

/// 公开 State：供导航屏用 [GlobalKey] 调 [openTodayEditor]（把手竖单的
/// 「今日日记」快捷入口），与本屏 `_handleMenuKey` / `_aiDialogKey` 同一做法。
class DiaryPageState extends State<DiaryPage> {
  final GlobalKey<NavigatorState> _navigatorKey = GlobalKey<NavigatorState>();

  late final DiaryClock _clock = widget.clock ?? DiaryClock();
  late final DiaryDataProvider _dataProvider =
      widget.dataProvider ?? FakeDiaryDataProvider();

  DiaryRepository? _repository;
  DiaryComposer? _composer;
  DiaryExportService? _exportService;
  Object? _loadError;
  bool _canPopNested = false;

  /// 内层栈顶路由名（由 [_DiaryStackObserver] 同步；不触发重建）。
  String? _topRouteName;

  /// 导航锚点服务（页面在 `NavBadgeScope` 子树内；脱离时为 null）。
  NavBadgeService? _badges;

  /// 本进程是否已被导航屏请求过弹导出提醒（每次冷启动仅一次）。
  bool _reminderRequested = false;

  /// 本进程是否已真正弹出过提醒对话框（防重复）。
  bool _reminderShown = false;

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final badges = NavBadgeScope.maybeOf(context);
    if (!identical(badges, _badges)) {
      _badges = badges;
      // 捕获（或更换）锚点服务后立即按当前数据同步一次红锚点。
      _syncExportReminder();
    }
  }

  @override
  void dispose() {
    _repository?.removeListener(_syncExportReminder);
    super.dispose();
  }

  Future<void> _bootstrap() async {
    try {
      // 测试注入直接用；生产打开应用文档目录下的持久仓储
      //（debug 首装种子，release 空仓）。
      final repository =
          widget.repository ??
          await PersistentDiaryRepository.open(
            root: await _storageRoot(),
            clock: _clock,
            seedDebugData: kDebugMode,
          );
      final template = await DailyDefaultTemplate.loadAsset();
      final composer = DiaryComposer(
        template: template,
        provider: _dataProvider,
        idGenerator: repository.idGenerator,
        // 显式走日记日时钟：ECP sys.clock.set 拨钟后，成稿时间戳与
        // 「今天」判定随之同步（同一实例，同路原则）。
        now: _clock.now,
      );
      final exportService =
          widget.exportService ?? DiaryExportService(repository: repository);

      // ECP 接线：把与 UI 完全同源的实例注册给控制面（widget 测试
      // 未走 ControlBootstrap.init 时 instance 为 null，静默跳过）。
      // 同路原则：命令调的就是本页正在用的同一个时钟/仓储/composer。
      final control = ControlBootstrap.instance;
      if (control != null) {
        control.paths.diaryRoot = widget.repository == null
            ? await _storageRoot()
            : null;
        control.registry
          ..set(_clock)
          ..set(repository)
          ..set(composer)
          ..set(exportService);
      }

      if (!mounted) return;
      setState(() {
        _repository = repository;
        _composer = composer;
        _exportService = exportService;
      });
      // 数据驱动红锚点：仓储任何变更（成稿 / 导出迁移）都重算一次。
      repository.addListener(_syncExportReminder);
      unawaited(_syncExportReminder());
      // 导航屏在 bootstrap 完成前请求过提醒（如冷启动即切到笔记页）：
      // 此时仓储才就绪，补弹一次。
      if (_reminderRequested) unawaited(maybeShowExportReminder());
      // 进模块即自动成稿今天；并发点进由 ensureDay 的 in-flight 去重兜底。
      unawaited(composer.ensureDay(_clock.today(), repository));
      // 顺手清掉此前所有「什么都没写」的跨天空稿；今天的空稿保留。
      unawaited(
        repository.pruneEmptyBefore(_clock.today(), composer.isUserEmpty),
      );
    } catch (error) {
      if (mounted) setState(() => _loadError = error);
    }
  }

  /// 仓储根目录：`<应用文档目录>/echo_diary`（open 内负责创建）。
  Future<Directory> _storageRoot() async {
    final docs = await getApplicationDocumentsDirectory();
    return Directory('${docs.path}/echo_diary');
  }

  /// [DiaryPage.preEnterToday] 的初始路由栈：年列表在下、今日编辑页在上。
  ///
  /// 与用户手动「年→月→日」进入后的栈形态完全一致（返回回到年列表）；
  /// 「今天」取日记日时钟（04:00 日界），与自动成稿、日页判定同源。
  List<Route<dynamic>> _initialRoutesWithTodayEditor(
    NavigatorState navigator,
    String initialRoute,
  ) {
    return [
      MaterialPageRoute<void>(builder: (_) => const YearListPage()),
      _todayEditorRoute(),
    ];
  }

  /// 今日编辑页路由（[预进][DiaryPage.preEnterToday] 与「今日日记」快捷共用）。
  DiarySlideRoute<void> _todayEditorRoute() {
    final today = _clock.today();
    return DiarySlideRoute<void>(
      builder: (_) =>
          DayEditorPage(year: today.year, month: today.month, day: today.day),
      settings: RouteSettings(name: _todayEditorRouteName()),
    );
  }

  /// 今日编辑页的路由名（栈顶比对用）。
  String _todayEditorRouteName() {
    final today = _clock.today();
    return '/day/${today.year}/${today.month}/${today.day}';
  }

  /// 把手竖单「今日日记」快捷：把日记内层栈带到今日编辑页。
  ///
  /// 已在今日编辑页时静默返回（不重建、不打断正在进行的编辑）；否则
  /// 按标准滑入动画压入今日编辑页——返回仍回到跳转前所在的那一层。
  void openTodayEditor() {
    final navigator = _navigatorKey.currentState;
    if (navigator == null) return;
    if (_topRouteName == _todayEditorRouteName()) return;
    navigator.push(_todayEditorRoute());
  }

  /// 导出提醒 · 锚点：按「是否仍有已结束月份存在未导出草稿」上报红锚点。
  ///
  /// 判定口径统一为 [DiaryRepository.oldestDraftBefore]（cutoff = 本月
  /// 1 日）：非空 → `reportException`（红闪烁），为空 → `resolveException`
  /// 自动解除。exception 级不受 `markViewed` 影响，天然满足「到真正完成
  /// 有效导出才消」，且消除时机完全由数据驱动、接口干净。
  ///
  /// 由仓储变更通知（成稿 / 导出迁移）与锚点服务捕获时触发。
  Future<void> _syncExportReminder() async {
    final repository = _repository;
    final badges = _badges;
    if (repository == null || badges == null) return;
    final today = repository.today();
    final oldest = await repository.oldestDraftBefore(
      DateTime(today.year, today.month, 1),
    );
    if (!mounted) return;
    if (oldest == null) {
      badges.resolveException(widget.badgeDestinationId);
    } else {
      badges.reportException(widget.badgeDestinationId);
    }
  }

  /// 导出提醒 · 对话框：每次冷启动**首次进入笔记页**时调用一次。
  ///
  /// 导航屏只请求一次（`_reminderRequested`）；若请求时仓储尚未就绪
  /// （bootstrap 在途），本方法会先记下请求，待装配完成后由 [_bootstrap]
  /// 补弹。无待导出 / 本进程已弹过则直接返回。
  ///
  /// 「去导出」只负责跳转到最早待导出月份所在的月列表（用户在其中点
  /// 月行导出按钮触发实际导出），不代替用户执行导出。
  Future<void> maybeShowExportReminder() async {
    _reminderRequested = true;
    if (_reminderShown) return;
    final repository = _repository;
    if (repository == null) return; // 仓储未就绪：bootstrap 完成后补弹
    final today = repository.today();
    final oldest = await repository.oldestDraftBefore(
      DateTime(today.year, today.month, 1),
    );
    if (oldest == null || !mounted) return;

    _reminderShown = true;
    final goExport = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('日记还没导出'),
        content: Text(
          '按月导出更稳妥：还有 ${oldest.year} 年 ${oldest.month} 月的日记'
          '未导出，建议尽快分享到思源归档。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('稍后'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('去导出'),
          ),
        ],
      ),
    );
    if (goExport != true || !mounted) return;

    // 把内层栈变成 [年列表, 最早待导出月份的月列表]：返回仍回年列表。
    final navigator = _navigatorKey.currentState;
    if (navigator == null) return;
    navigator.pushAndRemoveUntil(
      DiarySlideRoute<void>(
        builder: (_) => MonthListPage(year: oldest.year),
        settings: RouteSettings(name: '/year/${oldest.year}'),
      ),
      (route) => route.isFirst,
    );
  }

  void _syncCanPop() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final canPop = _navigatorKey.currentState?.canPop() ?? false;
      if (canPop != _canPopNested && mounted) {
        setState(() => _canPopNested = canPop);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final repository = _repository;
    final composer = _composer;
    final exportService = _exportService;
    if (repository == null || composer == null || exportService == null) {
      return Center(
        child: _loadError != null
            ? Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  '日记数据打开失败：$_loadError',
                  style: const TextStyle(color: Colors.white70),
                ),
              )
            : const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
      );
    }
    return DiaryRepositoryScope(
      repository: repository,
      child: DiaryComposerScope(
        clock: _clock,
        dataProvider: _dataProvider,
        composer: composer,
        child: DiaryExportServiceScope(
          service: exportService,
          child: PopScope(
            canPop: !_canPopNested,
            onPopInvokedWithResult: (didPop, _) {
              if (!didPop) _navigatorKey.currentState?.maybePop();
            },
            child: Navigator(
              key: _navigatorKey,
              observers: [
                _DiaryStackObserver(
                  onChanged: _syncCanPop,
                  onTopRoute: (name) => _topRouteName = name,
                ),
              ],
              // 首帧路由栈：默认只有年列表；[preEnterToday] 时一次性建好
              // 「年列表 + 今日编辑页」两层（初始路由无转场动画，此时日记页
              // 还在页面轨道上离屏，用户不可见）。
              onGenerateInitialRoutes: widget.preEnterToday
                  ? _initialRoutesWithTodayEditor
                  : Navigator.defaultGenerateInitialRoutes,
              onGenerateRoute: (settings) {
                return MaterialPageRoute<void>(
                  settings: settings,
                  fullscreenDialog: false,
                  // 根页也半透明：让页面共用的机械背景透上来。
                  builder: (_) => const YearListPage(),
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}

/// 内层路由栈变化时：同步「是否可返回」给 PopScope，并记录栈顶路由名
/// （供 [DiaryPageState.openTodayEditor] 判断当前是否已在今日编辑页）。
class _DiaryStackObserver extends NavigatorObserver {
  _DiaryStackObserver({required this.onChanged, required this.onTopRoute});

  final VoidCallback onChanged;
  final ValueChanged<String?> onTopRoute;

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    super.didPush(route, previousRoute);
    onChanged();
    onTopRoute(route.settings.name);
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    super.didPop(route, previousRoute);
    onChanged();
    onTopRoute(previousRoute?.settings.name);
  }

  @override
  void didRemove(Route<dynamic> route, Route<dynamic>? previousRoute) {
    super.didRemove(route, previousRoute);
    onChanged();
    onTopRoute(previousRoute?.settings.name);
  }

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) {
    super.didReplace(newRoute: newRoute, oldRoute: oldRoute);
    onTopRoute(newRoute?.settings.name);
  }
}
