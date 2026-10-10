import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

import '../data/diary_clock.dart';
import '../data/diary_data_provider.dart';
import '../data/diary_repository.dart';
import '../data/persistent_diary_repository.dart';
import '../template/daily_default_template.dart';
import '../template/diary_composer.dart';
import 'browser/year_list_page.dart';
import 'diary_composer_scope.dart';

/// 日记模块根页：内嵌一个 Navigator 承载 年→月→日→编辑器 四级栈，
/// 系统返回键由 [PopScope] 收口到内层栈；栈底时不拦截，交给系统
/// （与外层横向翻页互不干扰——内层路由无边缘手势，见 DiarySlideRoute）。
///
/// 仓储/时钟/数据源/composer 均在本页 State 创建并随页面常驻：
/// M5 起生产仓储异步开库（sqflite meta + 应用目录 .sy），随后加载
/// 默认模板，装配完成后 fire-and-forget 执行「今天自动成稿 +
/// 早于今天的空草稿清理」（§5.2 硬裁定 2/4）。
class DiaryPage extends StatefulWidget {
  const DiaryPage({super.key, this.clock, this.dataProvider, this.repository});

  /// 测试注入缝：固定时钟/数据源/仓储；生产环境全部走真实装配。
  final DiaryClock? clock;
  final DiaryDataProvider? dataProvider;
  final DiaryRepository? repository;

  @override
  State<DiaryPage> createState() => _DiaryPageState();
}

class _DiaryPageState extends State<DiaryPage> {
  final GlobalKey<NavigatorState> _navigatorKey = GlobalKey<NavigatorState>();

  late final DiaryClock _clock = widget.clock ?? DiaryClock();
  late final DiaryDataProvider _dataProvider =
      widget.dataProvider ?? FakeDiaryDataProvider();

  DiaryRepository? _repository;
  DiaryComposer? _composer;
  Object? _loadError;
  bool _canPopNested = false;

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  Future<void> _bootstrap() async {
    try {
      // 测试注入直接用；生产打开应用文档目录下的持久仓储
      //（debug 首装种子，release 空仓）。
      final repository = widget.repository ??
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
      );
      if (!mounted) return;
      setState(() {
        _repository = repository;
        _composer = composer;
      });
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
    if (repository == null || composer == null) {
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
        child: PopScope(
          canPop: !_canPopNested,
          onPopInvokedWithResult: (didPop, _) {
            if (!didPop) _navigatorKey.currentState?.maybePop();
          },
          child: Navigator(
            key: _navigatorKey,
            observers: [_DiaryStackObserver(_syncCanPop)],
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
    );
  }
}

/// 内层路由栈变化时同步「是否可返回」状态给 PopScope。
class _DiaryStackObserver extends NavigatorObserver {
  _DiaryStackObserver(this.onChanged);

  final VoidCallback onChanged;

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    super.didPush(route, previousRoute);
    onChanged();
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    super.didPop(route, previousRoute);
    onChanged();
  }

  @override
  void didRemove(Route<dynamic> route, Route<dynamic>? previousRoute) {
    super.didRemove(route, previousRoute);
    onChanged();
  }
}
