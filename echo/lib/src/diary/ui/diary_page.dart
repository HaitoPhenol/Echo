import 'dart:async';

import 'package:flutter/material.dart';

import '../data/diary_clock.dart';
import '../data/diary_data_provider.dart';
import '../data/diary_repository.dart';
import '../data/in_memory_diary_repository.dart';
import '../template/daily_default_template.dart';
import '../template/diary_composer.dart';
import 'browser/year_list_page.dart';
import 'diary_composer_scope.dart';

/// 日记模块根页：内嵌一个 Navigator 承载 年→月→日→编辑器 四级栈，
/// 系统返回键由 [PopScope] 收口到内层栈；栈底时不拦截，交给系统
/// （与外层横向翻页互不干扰——内层路由无边缘手势，见 DiarySlideRoute）。
///
/// 仓储/时钟/数据源/composer 均在本页 State 创建并随页面常驻：
/// 首帧前从 assets 加载默认模板，装配完成后 fire-and-forget 执行
/// 「今天自动成稿 + 早于今天的空草稿清理」（§5.2 硬裁定 2/4）。
/// M5 只需把 [InMemoryDiaryRepository] 换成持久实现。
class DiaryPage extends StatefulWidget {
  const DiaryPage({
    super.key,
    this.clock,
    this.dataProvider,
    this.repository,
  });

  /// 测试注入缝：固定时钟/数据源/仓储；生产环境全部走真实装配。
  final DiaryClock? clock;
  final DiaryDataProvider? dataProvider;
  final InMemoryDiaryRepository? repository;

  @override
  State<DiaryPage> createState() => _DiaryPageState();
}

class _DiaryPageState extends State<DiaryPage> {
  final GlobalKey<NavigatorState> _navigatorKey = GlobalKey<NavigatorState>();

  late final DiaryClock _clock = widget.clock ?? DiaryClock();
  late final InMemoryDiaryRepository _repository =
      widget.repository ?? InMemoryDiaryRepository(clock: _clock);
  late final DiaryDataProvider _dataProvider =
      widget.dataProvider ?? FakeDiaryDataProvider();

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
      final template = await DailyDefaultTemplate.loadAsset();
      final composer = DiaryComposer(
        template: template,
        provider: _dataProvider,
        idGenerator: _repository.idGenerator,
      );
      if (!mounted) return;
      setState(() => _composer = composer);
      // 进模块即自动成稿今天；并发点进由 ensureDay 的 in-flight 去重兜底。
      unawaited(composer.ensureDay(_clock.today(), _repository));
      // 顺手清掉此前所有「什么都没写」的跨天空稿；今天的空稿保留。
      unawaited(
        _repository.pruneEmptyBefore(_clock.today(), composer.isUserEmpty),
      );
    } catch (error) {
      if (mounted) setState(() => _loadError = error);
    }
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
    final composer = _composer;
    return DiaryRepositoryScope(
      repository: _repository,
      child: composer == null
          ? Center(
              child: _loadError != null
                  ? Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text(
                        '日记模板加载失败：$_loadError',
                        style: const TextStyle(color: Colors.white70),
                      ),
                    )
                  : const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
            )
          : DiaryComposerScope(
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
