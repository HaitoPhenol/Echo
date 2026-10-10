import 'package:flutter/material.dart';

import '../data/diary_repository.dart';
import '../data/in_memory_diary_repository.dart';
import 'browser/year_list_page.dart';

/// 日记模块根页：内嵌一个 Navigator 承载 年→月→日→编辑器 四级栈，
/// 系统返回键由 [PopScope] 收口到内层栈；栈底时不拦截，交给系统
/// （与外层横向翻页互不干扰——内层路由无边缘手势，见 DiarySlideRoute）。
///
/// 仓储在本页 State 创建并经 [DiaryRepositoryScope] 下发：
/// 页面在外层导航轨道中常驻不销毁，仓储生命周期随之。
/// M5 只需把 [InMemoryDiaryRepository] 换成文件/数据库实现。
class DiaryPage extends StatefulWidget {
  const DiaryPage({super.key});

  @override
  State<DiaryPage> createState() => _DiaryPageState();
}

class _DiaryPageState extends State<DiaryPage> {
  final GlobalKey<NavigatorState> _navigatorKey = GlobalKey<NavigatorState>();
  late final DiaryRepository _repository = InMemoryDiaryRepository();
  bool _canPopNested = false;

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
    return DiaryRepositoryScope(
      repository: _repository,
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
