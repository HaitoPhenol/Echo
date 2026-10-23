import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../control/bootstrap.dart';
import '../control/control_event_bridge.dart';
import '../control/slash_ui/slash_ui.dart';
import '../diary/data/diary_repository.dart';
import '../diary/ui/diary_page.dart';
import '../services/chat_session_controller.dart';
import '../services/chat_store.dart';
import '../services/console_stats_service.dart';
import '../services/haptics.dart';
import '../services/nav_badge_service.dart';
import '../services/search_service.dart';
import '../services/window_inset_refresher.dart';
import '../theme/mechanical_style.dart';
import 'dock_geometry.dart';
import 'dock_layout.dart';
import 'nav_destination.dart';
import 'nav_gesture_records.dart';
import 'nav_physics.dart';
import 'page_action.dart';
import 'quick_action.dart';
import 'widgets/ai_bar.dart';
import 'widgets/ai_dialog.dart';
import 'widgets/handle_bar.dart';
import 'widgets/handle_menu.dart';
import 'widgets/mechanical_background.dart';
import 'widgets/mechanical_coords_bar.dart';
import 'widgets/mechanical_page_drum.dart';
import 'widgets/mechanical_page_name_plate.dart';
import 'widgets/mechanical_page_number.dart';
import 'widgets/quick_action_arc.dart';
import 'widgets/search_capsule.dart';
import 'widgets/side_drawer.dart';
import 'widgets/trigger_ripple.dart';

/// 智能导航实验主屏。
///
/// 屏幕内容：
/// - 底层：横向页面轨道（聊天页为会话列表骨架，其余 3 页仍是
///   只显示标题的占位页）；
/// - 底部一整行三条（间距与屏幕留白均为 14px，几何见 [DockGeometry]）：
///   左为把手条、中为 AI 条、右为导航条整体（含两端翻页圆点）；
/// - 浮层：滚筒指示器、快捷操作弧、本页操作竖单、侧边抽屉、
///   AI 对话框、触发涟漪。
///
/// 支持的全部手势：
/// - 点按两端圆点：按下即向左/右翻一页（并振动）；
/// - 横滑导航条：翻页（慢拖精调、快甩穿越）；
/// - 竖直上甩：打开快捷操作弧，横移选择、松手触发
///   （移出全部操作项热区松手则取消，可反悔）；
/// - 双击导航条：按点击的横向位置直达对应页；
/// - 长按导航条 0.45s：展开搜索框与最近搜索，2s 倒计时结束自动收起；
/// - 点按把手条：本页操作竖单向上生长；右拖：侧边空壳抽屉跟手滑出
///   （抽屉打开后点按/拖回把手即关闭）；
/// - 长按 AI 条 0.45s：呼出 AI 对话框（不自动收起，点外部关闭）；
///   AI 条单击预留、无动作。
///
/// 竖单、抽屉、AI 对话框与搜索态互斥：唤起其一会先收起其他浮层。
/// 任一浮层打开时系统返回键只关闭浮层、不退出 App（PopScope）。
class SmartNavScreen extends StatefulWidget {
  const SmartNavScreen({super.key, this.diaryRepository});

  /// 测试注入缝：笔记页日记仓储；生产环境为 null（走持久仓储开库）。
  final DiaryRepository? diaryRepository;

  @override
  State<SmartNavScreen> createState() => _SmartNavScreenState();
}

class _SmartNavScreenState extends State<SmartNavScreen>
    with TickerProviderStateMixin {
  /// 双击判定窗口：300ms，与 AOSP ViewConfiguration 一致。
  static const Duration _doubleTapWindow = Duration(milliseconds: 300);

  /// 已读停留阈值：在同一页连续停留超过该时间才算“查看”。
  static const Duration _readDwell = Duration(milliseconds: 700);

  /// 导航目的地配置（页面轨道、滚筒、页面搜索的唯一来源）。
  late final List<NavDestination> _destinations;

  /// 快捷操作配置。
  late final List<QuickAction> _quickActions;

  /// 日记页 State key：把手竖单「今日日记」快捷入口据此调用
  /// [DiaryPageState.openTodayEditor] 驱动日记内层栈（若该页未挂载则为 null）。
  final GlobalKey<DiaryPageState> _diaryKey = GlobalKey();

  /// 搜索历史存储与搜索服务。
  late final SearchHistoryStore _searchHistory;
  late final SearchService _searchService;

  /// 导航锚点状态服务（通知/异常上报接口）。
  late final NavBadgeService _badges;

  /// 聊天会话数据服务（会话增删 / 已读未读 / 消息）。
  late final ChatStore _chatStore;

  /// 当前打开会话控制器（点按行与 chat.open 命令同源）。
  late final ChatSessionController _chatSession;

  /// 聊天目的地在页面轨道中的下标（驱动锚点联动；-1 表示未配置）。
  int _chatPageIndex = -1;

  /// 笔记（日记）目的地在页面轨道中的下标（-1 表示未配置）。
  int _notesPageIndex = -1;

  /// 本进程是否已向日记页请求过导出提醒（每次冷启动首次进笔记页弹一次）。
  bool _diaryReminderRequested = false;

  /// 当前页停留满阈值后标为已读的延迟计时器（离开页面即取消）。
  Timer? _readTimer;

  late final NavPhysicsController _nav;

  // 搜索输入相关
  final FocusNode _searchFocusNode = FocusNode();
  final TextEditingController _searchTextController = TextEditingController();

  /// ECP slash 指令态编排（P3-G2）；widget 测试未走 ControlBootstrap
  /// 时为 null，搜索栏保持纯搜索行为。
  SlashConsoleController? _slash;

  /// P4-G2 UI 服务→控制面事件适配器（chat.incoming/nav.changed）；
  /// 仅在 ControlBootstrap 存在时挂接，随本屏服务一起拆除。
  UiEventBridge? _eventBridge;

  /// 快捷操作弧组件的 key：用于调用其收起方法（仅快捷弧出现时存在，
  /// 不在冷启动首帧路径上）。
  final GlobalKey<QuickActionArcState> _quickArcKey = GlobalKey();

  /// 当前按下色态的圆点：-1 左 / 1 右。
  int? _pressedDot;

  // ---------------- 把手条 / 抽屉 / 竖单 / AI 条状态 ----------------

  /// 抽屉吸附到全开的时长（从容展开）。
  static const Duration _drawerOpenDuration = Duration(milliseconds: 420);

  /// 抽屉吸附到全关的时长（关闭要非常干脆，约为开启的 1/4）。
  static const Duration _drawerCloseDuration = Duration(milliseconds: 100);

  /// 侧边抽屉开合进度（跟手拖动写值、松手后吸附到 0/1）。
  late final AnimationController _drawerAnim;

  /// 本页操作竖单是否挂载（含收起动画播放期间）。
  bool _menuShown = false;

  /// AI 对话框是否挂载（含退场动画期间）。
  bool _aiShown = false;

  /// 竖单组件 key：用于调用其收起方法。
  final GlobalKey<HandleMenuState> _handleMenuKey = GlobalKey();

  /// AI 对话框组件 key：用于调用其收起方法（失焦 + 退场）。
  final GlobalKey<AiDialogState> _aiDialogKey = GlobalKey();

  /// 进行中的把手手势（点按竖单 / 横向拖抽屉）。
  HandleGesture? _handleGesture;

  /// 进行中的 AI 条长按。
  AiHold? _aiHold;

  /// AI 条长按 450ms 呼出对话框的计时器。
  Timer? _aiHoldTimer;

  /// AI 条是否处于按下外观（增亮 + 光晕加强）。
  bool _aiPressed = false;

  /// Scaffold body 内的 BuildContext（State 自身 context 在 Scaffold
  /// 之上，拿不到 ScaffoldMessenger；本页操作弹 SnackBar 需要它）。
  BuildContext? _bodyContext;

  /// 搜索框当前文本与结果（由 SearchService 实时计算）。
  String _searchQuery = '';
  List<SearchResult> _searchResults = const [];

  /// 当前进行中的手势（无则为 null）。
  DragGesture? _gesture;

  /// 长按 450ms 展开搜索的计时器。
  Timer? _holdTimer;

  /// 上一次单击（短按）时刻，用于 300ms 内判定双击。
  Duration? _lastTapTime;

  // 快捷操作弧状态
  bool _quickArcShown = false;
  int _quickSelection = -1;
  final List<Offset> _quickPositions = [];

  /// 本次弧的热区半径（由布局按按钮数量算出，不再是常量）。
  double _quickHotRadius =
      DockGeometry.quickArcButtonDiameter / 2 + DockGeometry.quickArcHotMargin;

  /// 当前正在播放的涟漪列表。
  final List<RippleSpec> _ripples = [];

  /// 上一次监听到的搜索态标记：搜索态翻转时需重建根树，
  /// 使 PopScope 的 canPop 及时更新（fuse 自动关闭等路径
  /// 不经过本 State 的 setState）。在 initState 中初始化。
  bool _navWasSearching = false;

  @override
  void initState() {
    super.initState();

    // 状态栏/导航栏图标保持浅色并走透明边缘到边缘布局。
    SystemChrome.setSystemUIOverlayStyle(
      const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.light,
        systemNavigationBarColor: Colors.transparent,
        systemNavigationBarIconBrightness: Brightness.light,
      ),
    );

    // G4-BUG-3：在键盘弹起前注册 IME hide 终态补帧器，建立全屏物理
    // 高基线（app 级单例，幂等；详见 WindowInsetRefresher）。
    WindowInsetRefresher.ensureRegistered();

    // ---- 组装配置与服务（依赖关系：providers → searchService）----
    _destinations = buildDefaultDestinations(
      diaryRepository: widget.diaryRepository,
      diaryPageKey: _diaryKey,
    );
    _quickActions = buildDefaultQuickActions();
    _searchHistory = InMemorySearchHistoryStore();
    _searchService = SearchService(
      history: _searchHistory,
      providers: [
        NavDestinationSearchProvider(
          destinations: _destinations,
          onDestinationSelected: _jumpToDestination,
        ),
      ],
    );

    _badges = InMemoryNavBadgeService(
      destinationIds: [for (final d in _destinations) d.id],
    );

    _chatStore = ChatStore();
    _chatSession = ChatSessionController(_chatStore);
    _chatPageIndex = _destinations.indexWhere((d) => d.id == 'chat');
    _notesPageIndex = _destinations.indexWhere((d) => d.id == 'notes');
    // 锚点联动：聊天页锚点不再由「停留 700ms」清除，而完全由
    // 会话未读数据驱动——存在未读即通知（绿呼吸），全部已读才
    // 恢复默认；左滑「设为未读」同样会重新点亮锚点。
    _chatStore.addListener(_syncChatBadge);
    _syncChatBadge();

    _nav = NavPhysicsController(
      vsync: this,
      pageCount: _destinations.length,
      onActivePageChanged: (_) => Haptics.tick(),
      // 用闭包延迟引用 _nav，避免初始化表达式中访问尚未赋值的字段。
      onSettled: () => _nav.scheduleRollerHide(),
    );

    // 抽屉开合：跟手时直接写值、松手吸附时 forward/reverse。
    _drawerAnim = AnimationController(
      vsync: this,
      duration: _drawerOpenDuration,
    )..addListener(_handleDrawerTick);

    // 激活页停留超过阈值才表示该页被查看：快速扫过、双击跳转途中
    // 经过的页面不应标为已读。独立监听而非复用 onActivePageChanged
    // ——后者在圆点翻页期间会被静音。
    int? lastViewedPage;
    _nav.addListener(() {
      final page = _nav.activePage;
      if (page != lastViewedPage) {
        lastViewedPage = page;
        _readTimer?.cancel();
        // 聊天页的通知态由会话已读数据驱动（见 _syncChatBadge），
        // 停留计时不再清除它；其余页面维持「停留即已读」。
        if (page != _chatPageIndex) {
          _readTimer = Timer(
            _readDwell,
            () => _badges.markViewed(_destinations[page].id),
          );
        }
        // 导出提醒：每次冷启动**首次**切到笔记页时请求日记页弹一次
        // 对话框（弹框/跳转编排在 DiaryPageState 内，数据驱动判定）。
        if (page == _notesPageIndex && !_diaryReminderRequested) {
          _diaryReminderRequested = true;
          _diaryKey.currentState?.maybeShowExportReminder();
        }
      }
    });

    // 搜索态翻转（长按打开 / fuse 烧完 / 失焦关闭等）时重建根树，
    // 更新 PopScope 拦截状态与 scrim 显隐。
    _navWasSearching = _nav.isSearching;
    _nav.addListener(_handleNavSearchToggled);

    _searchFocusNode.addListener(_handleFocusChange);

    // ECP 接线：nav.goto 与横滑手势共用这同一个控制器；chat.*/badge.*
    // 命令同样取这里注册的 UI 同源实例。
    //（widget 测试未走 ControlBootstrap.init 时为 null，跳过）。
    final control = ControlBootstrap.instance;
    if (control != null) {
      control.registry
        ..set(_nav)
        ..set(_chatStore)
        ..set(_chatSession)
        ..set<NavBadgeService>(_badges);
      // slash 指令态与命令执行同源总线/鉴权；写回输入框与收起面板
      // 复用搜索栏既有控制器与退出路径，不另开输入入口。
      _slash = SlashConsoleController(
        bus: control.bus,
        auth: control.auth,
        onEditText: (v) => _searchTextController.value = v,
        onRequestClose: _exitSearch,
      );

      // P4-G2：ChatStore incoming 广播 + 导航页变化经装配适配器
      // 转发为 chat.incoming/nav.changed 事件（services 层自身
      // 不 import control，反向依赖接缝测试钉死）。
      _eventBridge = UiEventBridge(
        events: control.events,
        chatStore: _chatStore,
        nav: _nav,
      )..attach();
    }
  }

  @override
  void dispose() {
    _holdTimer?.cancel();
    _readTimer?.cancel();
    _aiHoldTimer?.cancel();
    _drawerAnim.dispose();
    // 先摘事件适配器（它监听下面两个服务），再销毁服务本身。
    _eventBridge?.dispose();
    _nav.dispose();
    _chatSession.dispose();
    _chatStore.dispose();
    _badges.dispose();
    _slash?.dispose();
    _searchFocusNode.dispose();
    _searchTextController.dispose();
    super.dispose();
  }

  /// 抽屉进度帧回调：驱动遮罩/面板/把手停靠位重绘。
  void _handleDrawerTick() => setState(() {});

  /// 会话未读状态 → 聊天页导航锚点的单向同步。
  ///
  /// 存在任意未读会话：锚点进入通知态（绿呼吸）；全部已读：
  /// 通知态直接恢复默认（不经过停留计时）。异常态不受本同步影响。
  void _syncChatBadge() {
    final index = _chatPageIndex;
    if (index < 0) return;
    // 锚点服务按目的地稳定 id 索引（页序可调而不失真）。
    final chatId = _destinations[index].id;
    if (_chatStore.hasUnread) {
      _badges.postNotification(chatId);
    } else if (_badges.levelOf(chatId) == NavBadgeLevel.notification) {
      _badges.markViewed(chatId);
    }
  }

  /// 监听到搜索态翻转：重建根树（更新 PopScope.canPop 与 scrim）。
  void _handleNavSearchToggled() {
    final searching = _nav.isSearching;
    if (searching == _navWasSearching) return;
    _navWasSearching = searching;
    if (mounted) setState(() {});
  }

  /// 系统返回键（PopScope）拦截处理：浮层存在时先关浮层、不退出 App。
  ///
  /// 优先级：搜索态 → 收起搜索面板；快捷弧 → 不触发操作直接收起；
  /// 两者皆无时 PopScope.canPop 为 true，系统直接执行默认 pop。
  void _handlePopInvoked(bool didPop, Object? result) {
    if (didPop) return;
    // 一次返回只关最上层一个浮层，符合安卓逐层返回的预期。
    if (_nav.isSearching) {
      _exitSearch();
    } else if (_quickArcShown) {
      _quickArcKey.currentState?.dismiss(fire: false);
    } else if (_menuShown) {
      _handleMenuKey.currentState?.dismiss();
    } else if (_aiShown) {
      _aiDialogKey.currentState?.dismiss();
    } else if (_drawerAnim.value > 0.01) {
      _settleDrawer(open: false);
    }
  }

  // ================================================================
  //  搜索焦点处理
  // ================================================================

  void _handleFocusChange() {
    if (_searchFocusNode.hasFocus) {
      _nav.beginInput();
    } else {
      // 延时判断：从输入框切到历史胶囊等场景会先失焦再被重新聚焦。
      Timer(const Duration(milliseconds: 150), () {
        if (mounted &&
            !_searchFocusNode.hasFocus &&
            _nav.searchState == SearchState.input &&
            // slash 指令态/挂起交互期间不得据此收起：触屏 IME 点
            // 「完成」提交后会主动 hide 键盘使输入框失焦，此时确认卡/
            // PIN 面板/重放/结果流刚挂上，收起即被 hostClosed 清空
            // （G4-BUG-1）。显式退出走 _exitSearch（BACK/scrim/
            // nav.goto），不经过本定时器；普通搜索态行为不变。
            !(_slash?.retainsOnUnfocus ?? false)) {
          _nav.closeSearch();
          _resetSearchPanel();
        }
      });
    }
  }

  // ================================================================
  //  搜索面板：数据与交互
  // ================================================================

  /// 搜索结果数据源选中了某目的地：跳转到对应页面。
  void _jumpToDestination(int index) {
    _nav.snapTo(index);
  }

  /// 输入文本变化：实时查询并刷新结果（slash 指令态同步给控制台
  /// 编排，搜索结果区在指令态不挂载，多算一次开销可忽略）。
  void _handleQueryChanged(String value) {
    _slash?.onInputChanged(value);
    setState(() {
      _searchQuery = value;
      _searchResults = _searchService.searchAll(value);
    });
  }

  /// 键盘提交：slash 指令态走控制台（不入搜索历史）；其余记录到
  /// 搜索历史。
  void _handleSubmitted(String value) {
    if (_slash?.active ?? false) {
      _slash!.submit(value);
      // G4-BUG-3：触屏 IME 点「完成」提交后键盘 hide，部分 MIUI +
      // 第三方 IME 会在 surface resize 回全屏期间丢掉引擎的最终布局
      // 帧——布局/hit-test 已在最终全屏位置，画面却停在键盘动画中途
      // （确认卡/PIN 卡按钮「看着在错位处、实际命中盒在正确位置」）。
      // 打开短时补帧窗口：终态全屏 metrics 到达后强制重提一帧，让
      // 视觉追上布局。仅 slash 指令链路挂钩，普通搜索提交不触发。
      // 详见 WindowInsetRefresher。
      WindowInsetRefresher.scheduleAfterSlashSubmit();
      return;
    }
    if (value.trim().isNotEmpty) {
      _searchHistory.add(value);
    }
  }

  /// 点击历史条目：带入输入框、定位光标到末尾并立即执行搜索。
  void _handleHistoryTap(String text) {
    _searchTextController.value = TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
    );
    _searchFocusNode.requestFocus();
    _handleQueryChanged(text);
  }

  /// 点击搜索结果：执行结果动作（跳页等）、记入历史并收起面板。
  void _handleResultTap(SearchResult result) {
    result.onSelect();
    _searchHistory.add(result.title);
    _exitSearch();
  }

  /// 收起搜索面板（失焦 + 关闭 + 清空临时状态）。
  void _exitSearch() {
    _searchFocusNode.unfocus();
    _nav.closeSearch();
    _resetSearchPanel();
  }

  /// 清空输入框与结果，为下次打开做准备。
  void _resetSearchPanel() {
    // 同步复位指令态（确认卡/PIN/多行/历史指针），避免残留挂起。
    _slash?.hostClosed();
    _searchTextController.clear();
    _searchQuery = '';
    _searchResults = const [];
  }

  // ================================================================
  //  手势：按下
  // ================================================================

  /// 根 Listener 的按下处理。
  ///
  /// 搜索态的「点击外部关闭」不在此处理：由 build 中铺在胶囊之下的
  /// 全屏 scrim 负责（结果/历史/胶囊在 scrim 之上，互不干扰）。
  void _handleRootPointerDown(PointerDownEvent event) {
    // G11 单指独占：已有手势在途（导航条拖动 / 把手拖动 / AI 长按）时
    // 忽略新的 PointerDown，避免两类竞态：
    //  · 第二指劫持——覆盖 _gesture/_handleGesture/_aiHold，把先按下的
    //    手指孤立；
    //  · 穿越手势——把手 _handleGesture 与导航条 _gesture 两套记录被
    //    同帧并驱，抽屉与翻页并发。
    // 搜索态展开时 _gesture 已在胶囊长按分支内置空（见 _beginCapsuleGrab），
    // 故本守卫不会阻断下方搜索态的点击处理。
    if (_gesture != null || _handleGesture != null || _aiHold != null) {
      return;
    }

    if (_nav.isSearching) {
      // open 态点击可视胶囊本体 → 聚焦进入输入态（TextField 自身
      // 也能获得焦点，这里只补 icon 等非输入区的覆盖）。
      if (_nav.searchState == SearchState.open &&
          _searchCapsuleRect().contains(event.position)) {
        _searchFocusNode.requestFocus();
      }
      return;
    }

    // 竖单/AI 对话框/抽屉打开期间，把手以外的底部交互全部让给
    // 各浮层自己的 scrim（点外部关闭），不能误翻页/误开新浮层。
    final blockingOverlay = _menuShown || _aiShown || _drawerAnim.value > 0.01;

    // 把手条优先级最高：竖单展开时它已被竖单取代，跳过
    // （按钮与竖单 scrim 各自接管）。
    if (!_menuShown && _handleHitRect().contains(event.position)) {
      _beginHandleGrab(event);
      return;
    }

    // AI 条：长按 450ms 呼出对话框；单击预留无动作。
    if (!blockingOverlay && _aiHitRect().contains(event.position)) {
      _beginAiHold(event);
      return;
    }

    if (blockingOverlay) return;

    // 常规态：视觉上导航条与圆点只有 10px 高、难以按中，因此
    // 在不改变外观和位置的前提下，上下方向共用同一条扩大的隐形
    // 触控区（向上 32、向下 10）；横向则分别划定：
    //   · 导航条：热区 = 自身长度，不横向扩展；
    //   · 圆  点：热区 = 自身直径的 2 倍（以圆点为中心）。
    final geometry = _navGeometry();

    // 纵向共用的上下边界。
    final zoneTop = geometry.bar.top - 32;
    final zoneBottom = geometry.bar.bottom + 10;

    Rect dotZone(Rect dot) => Rect.fromCenter(
      center: dot.center,
      width: dot.width * 2,
      height: zoneBottom - zoneTop,
    );

    // 圆点优先（其热区与导航条热区仅相接、不重叠）。
    if (dotZone(geometry.leftDot).contains(event.position)) {
      _fireNavDot(-1);
      return;
    }
    if (dotZone(geometry.rightDot).contains(event.position)) {
      _fireNavDot(1);
      return;
    }

    final barHitRect = Rect.fromLTRB(
      geometry.bar.left,
      zoneTop,
      geometry.bar.right,
      zoneBottom,
    );
    if (barHitRect.contains(event.position)) {
      _beginCapsuleGrab(event);
    }
  }

  /// 端点圆点按下：立即翻一页并振动，圆点短暂呈按下色。
  void _fireNavDot(int direction) {
    Haptics.tick();
    _nav.stepPage(direction);
    setState(() => _pressedDot = direction);
    Timer(const Duration(milliseconds: 200), () {
      if (mounted && _pressedDot == direction) {
        setState(() => _pressedDot = null);
      }
    });
  }

  /// 胶囊常规态按下：开始一次手势的生命周期（方向待定）。
  void _beginCapsuleGrab(PointerDownEvent event) {
    final now = event.timeStamp;
    final isDoubleTap =
        _lastTapTime != null && now - _lastTapTime! < _doubleTapWindow;
    _lastTapTime = null;

    _nav.beginGrab();
    _gesture = DragGesture(
      pointer: event.pointer,
      x0: event.position.dx,
      y0: event.position.dy,
      doubleTap: isDoubleTap,
    );

    // 长按 450ms 且期间未移动 → 展开搜索。
    _holdTimer?.cancel();
    _holdTimer = Timer(const Duration(milliseconds: 450), () {
      final gesture = _gesture;
      if (gesture != null && !gesture.moved) {
        _gesture = null;
        Haptics.confirm();
        _resetSearchPanel();
        _nav.openSearch();
      }
    });
  }

  // ================================================================
  //  手势：把手条（单击竖单 / 横拖抽屉）与 AI 条（长按对话框）
  // ================================================================

  /// 把手条按下：开始一次手势（点竖单还是拖抽屉要等移动主方向）。
  void _beginHandleGrab(PointerDownEvent event) {
    _handleGesture = HandleGesture(
      pointer: event.pointer,
      x0: event.position.dx,
      y0: event.position.dy,
      startK: _drawerAnim.value,
    );
  }

  /// 把手手势移动：横向超 6px 且占优 → 拖抽屉；竖直上移占优 →
  /// 进入死区（把手竖直方向无动作，也不再转成单击）。
  void _updateHandleGesture(HandleGesture gesture, PointerMoveEvent event) {
    final dx = event.position.dx - gesture.x0;
    final dy = event.position.dy - gesture.y0;
    final absDx = dx.abs();
    final absDy = dy.abs();

    if (!gesture.locked) {
      if (absDx > 6 && absDx > absDy * 1.1) {
        gesture.horizontal = true;
        gesture.locked = true;
      } else if (dy < -16 && absDy > absDx * 1.1) {
        gesture.dead = true;
        gesture.locked = true;
      } else if (absDx > 28 || absDy > 28) {
        // 超出死区后按主导方向兜底归类（向下一律按横向无关处理）。
        gesture
          ..locked = true
          ..horizontal = absDx >= absDy;
        if (!gesture.horizontal) gesture.dead = true;
      } else {
        return;
      }
    }

    if (!gesture.horizontal) return;

    // 跟手：进度 = 起始进度 + 位移/抽屉宽，夹在 0..1。
    final drawerWidth = DockGeometry.drawerWidthFor(
      MediaQuery.sizeOf(context).width,
    );
    _drawerAnim.value = (gesture.startK + dx / drawerWidth).clamp(0.0, 1.0);
  }

  /// 把手手势结束：横向拖 → 就近/按速吸附；未移动点按 → 开竖单，
  /// 抽屉开着时点按 → 关抽屉；竖直死区不做任何事。
  void _releaseHandleGesture(HandleGesture gesture, {required bool cancelled}) {
    if (gesture.horizontal) {
      _settleDrawer(open: _drawerAnim.value > 0.5);
      return;
    }
    if (gesture.dead || cancelled) return;

    if (_drawerAnim.value > 0.01) {
      _settleDrawer(open: false);
    } else {
      _openPageMenu();
    }
  }

  /// AI 条按下：记录起点、进入按压外观，450ms 未移动则呼出对话框。
  void _beginAiHold(PointerDownEvent event) {
    setState(() => _aiPressed = true);
    _aiHold = AiHold(
      pointer: event.pointer,
      x0: event.position.dx,
      y0: event.position.dy,
    );
    _aiHoldTimer?.cancel();
    _aiHoldTimer = Timer(const Duration(milliseconds: 450), () {
      final hold = _aiHold;
      if (hold == null || hold.cancelled || hold.fired) return;
      hold.fired = true;
      _openAiDialog();
    });
  }

  /// AI 条移动：位移超过 8px 取消本次长按（外观松手时再复位）。
  void _updateAiHold(AiHold hold, PointerMoveEvent event) {
    if (hold.cancelled || hold.fired) return;
    final dx = event.position.dx - hold.x0;
    final dy = event.position.dy - hold.y0;
    if (dx * dx + dy * dy > 8 * 8) {
      hold.cancelled = true;
      _aiHoldTimer?.cancel();
    }
  }

  /// AI 条松手/取消：清计时器与按压外观（对话框已开则保留）。
  void _releaseAiHold() {
    _aiHoldTimer?.cancel();
    _aiHold = null;
    if (_aiPressed) setState(() => _aiPressed = false);
  }

  // ================================================================
  //  浮层：竖单 / AI 对话框 / 抽屉（互斥、PopScope 共用）
  // ================================================================

  /// 收起除调用方外的其它浮层（搜索/快捷弧/竖单/AI/抽屉）。
  void _dismissPeerOverlays() {
    if (_nav.isSearching) _exitSearch();
    if (_quickArcShown) _quickArcKey.currentState?.dismiss(fire: false);
    if (_menuShown) _handleMenuKey.currentState?.dismiss();
    if (_aiShown) _aiDialogKey.currentState?.dismiss();
    if (_drawerAnim.value > 0.01) _settleDrawer(open: false, haptic: false);
  }

  /// 打开本页操作竖单（同帧隐藏把手条，由 HandleMenu 起始帧接续）。
  void _openPageMenu() {
    _dismissPeerOverlays();
    Haptics.confirm();
    setState(() => _menuShown = true);
  }

  /// 竖单播完退场：卸载组件并让把手条回归。
  void _handleMenuDismissed() {
    if (mounted) setState(() => _menuShown = false);
  }

  /// 竖单按钮触发：执行本页操作 + 涟漪 + 收起竖单。
  void _handlePageActionFire(int index) {
    Haptics.confirm();
    final bodyContext = _bodyContext;
    if (bodyContext != null) {
      _currentPageActions()[index].onSelect(bodyContext);
    }
    setState(() {
      _ripples.add(RippleSpec(center: _pageMenuPositions()[index]));
    });
    _handleMenuKey.currentState?.dismiss();
  }

  /// 当前页的本页操作（竖单只显示**当前所在页面**的操作，各页独立）。
  ///
  /// 竖单仅在 [_menuShown] 期间挂载，打开后由其 scrim 挡住换页手势，
  /// 故「取列表 → 显示 → 按下 / 定位涟漪」期间当前页不会变化，
  /// 索引始终与 [HandleMenu.actions] 一一对应。
  List<PageAction> _currentPageActions() => buildPageActions(
    _destinations[_nav.activePage].id,
    onOpenTodayDiary: _openTodayDiary,
    onBackfill: _openBackfill,
    // 仅日编辑页多一个「插入时间戳」入口（详见 [buildPageActions]），
    // 其余页面清单不变。
    notesEditorActive: _diaryKey.currentState?.isEditorPage ?? false,
    onInsertStamp: _insertStamp,
  );

  /// 竖单「插入时间戳」：在编辑页光标所在块的下一行插入一个时间戳段。
  bool _insertStamp() =>
      _diaryKey.currentState?.insertStampBelowCursor() ?? false;

  /// 「今日日记」快捷：直接进今日日记编辑页。
  ///
  /// 用户此刻就在笔记页上（竖单按当前页取用），无需切换轨道页；
  /// 由日记页自己把内层栈带到今日编辑页（见 [DiaryPageState.openTodayEditor]）。
  void _openTodayDiary() => _diaryKey.currentState?.openTodayEditor();

  /// 「补记」快捷：弹日期选择器补录过去某天（入口自月列表页顶栏「+」迁来）。
  ///
  /// 同为笔记页常驻入口：用户此刻就在笔记页上，由日记页自己弹日期选择器并
  /// 把内层栈带到所选日期的编辑页（见 [DiaryPageState.startBackfill]）。
  void _openBackfill() => _diaryKey.currentState?.startBackfill();

  /// 打开 AI 对话框（按压外观到松手时自然复位）。
  void _openAiDialog() {
    _dismissPeerOverlays();
    Haptics.confirm();
    setState(() => _aiShown = true);
  }

  /// AI 对话框播完退场。
  void _handleAiDismissed() {
    if (mounted) setState(() => _aiShown = false);
  }

  /// 抽屉吸附到全开或全关。
  ///
  /// 跟手阶段直接写 [_drawerAnim].value、不经过时长；这里只切换
  /// 吸附时长——开启 420ms 保持从容，关闭 100ms 极快收起。
  void _settleDrawer({required bool open, bool haptic = true}) {
    if (haptic) Haptics.confirm();
    _drawerAnim.duration = open ? _drawerOpenDuration : _drawerCloseDuration;
    if (open) {
      _drawerAnim.forward();
    } else {
      _drawerAnim.reverse();
    }
  }

  /// 竖单各按钮的圆心（与 HandleMenu 内边距/间距规则一致，
  /// 供触发涟漪定位），条数按当前页的 [_currentPageActions] 长度而定。
  /// 纯计算收敛在 [DockLayout]。
  List<Offset> _pageMenuPositions() =>
      _layout.pageMenuPositionsFor(_currentPageActions().length);

  // ================================================================
  //  手势：移动（含方向锁定）
  // ================================================================

  void _handleRootPointerMove(PointerMoveEvent event) {
    final handleGesture = _handleGesture;
    if (handleGesture != null && event.pointer == handleGesture.pointer) {
      _updateHandleGesture(handleGesture, event);
      return;
    }

    final aiHold = _aiHold;
    if (aiHold != null && event.pointer == aiHold.pointer) {
      _updateAiHold(aiHold, event);
      return;
    }

    final gesture = _gesture;
    if (gesture == null || event.pointer != gesture.pointer) return;

    // 方向锁定前：根据位移主方向决定本次手势用途。
    if (!gesture.moved) {
      final dx = event.position.dx - gesture.x0;
      final dy = event.position.dy - gesture.y0;
      final absDx = dx.abs();
      final absDy = dy.abs();

      if (absDx > 8 && absDx > absDy * 1.1) {
        _lockPageDrag(gesture, event);
      } else if (dy < -16 && absDy > absDx * 2) {
        _lockQuickArc(gesture, event);
      } else if (math.sqrt(absDx * absDx + absDy * absDy) > 28) {
        // 超过死区后按主导方向归类；向下一律按翻页处理。
        if (absDx > absDy) {
          _lockPageDrag(gesture, event);
        } else if (dy < 0) {
          _lockQuickArc(gesture, event);
        } else {
          _lockPageDrag(gesture, event);
        }
      } else {
        return;
      }
    }

    if (gesture.isQuick) {
      _updateQuickSelection(event.position);
      return;
    }

    _nav.dragUpdate(event.position.dx);
  }

  /// 锁定为横向翻页拖动。
  void _lockPageDrag(DragGesture gesture, PointerMoveEvent event) {
    gesture.moved = true;
    gesture.isQuick = false;
    _holdTimer?.cancel();
    _nav.showRoller();
    _nav.dragStart(event.position.dx);
  }

  /// 锁定为竖直上甩：打开快捷操作弧。
  void _lockQuickArc(DragGesture gesture, PointerMoveEvent event) {
    gesture.moved = true;
    gesture.isQuick = true;
    _holdTimer?.cancel();
    // 横滑中途改上甩时，滚筒可能正显示着，立即关闭以免与快捷弧重叠。
    _nav.hideRoller();
    setState(() {
      _computeQuickPositions();
      // 初始选中项 = 离当前手指最近的按钮（数量无关）。
      var nearest = -1;
      var nearestDistance = double.infinity;
      for (var i = 0; i < _quickPositions.length; i++) {
        final distance = (event.position - _quickPositions[i]).distance;
        if (distance < nearestDistance) {
          nearestDistance = distance;
          nearest = i;
        }
      }
      _quickSelection = nearestDistance <= _quickHotRadius ? nearest : -1;
      _quickArcShown = true;
    });
  }

  /// 快捷弧上根据手指位置更新选中项。
  ///
  /// 取距离最近的按钮：在热区半径内则选中，否则选中项为 -1
  /// （无高亮）——让用户看到自己可以「反悔」。
  void _updateQuickSelection(Offset position) {
    var nearest = -1;
    var nearestDistance = double.infinity;
    for (var i = 0; i < _quickPositions.length; i++) {
      final distance = (position - _quickPositions[i]).distance;
      if (distance < nearestDistance) {
        nearestDistance = distance;
        nearest = i;
      }
    }
    final next = nearestDistance <= _quickHotRadius ? nearest : -1;

    if (next != _quickSelection) {
      if (next >= 0) Haptics.tick();
      setState(() => _quickSelection = next);
    }
  }

  // ================================================================
  //  手势：松手 / 取消
  // ================================================================

  void _handleRootPointerUp(PointerUpEvent event) {
    _releaseGesture(
      event.pointer,
      cancelled: false,
      globalPosition: event.position,
      timestamp: event.timeStamp,
    );
  }

  void _handleRootPointerCancel(PointerCancelEvent event) {
    _releaseGesture(event.pointer, cancelled: true);
  }

  /// 手势结束的统一处理。
  void _releaseGesture(
    int pointer, {
    required bool cancelled,
    Offset? globalPosition,
    Duration? timestamp,
  }) {
    // 把手手势与 AI 长按各自独立结束，不进入导航条手势流程。
    final handleGesture = _handleGesture;
    if (handleGesture != null && pointer == handleGesture.pointer) {
      _handleGesture = null;
      _releaseHandleGesture(handleGesture, cancelled: cancelled);
      return;
    }
    final aiHold = _aiHold;
    if (aiHold != null && pointer == aiHold.pointer) {
      _releaseAiHold();
      return;
    }

    final globalX = globalPosition?.dx;
    final gesture = _gesture;
    if (gesture == null || pointer != gesture.pointer) return;

    _gesture = null;
    _holdTimer?.cancel();

    // 快捷操作弧：触发或直接收起。
    if (gesture.isQuick) {
      // 仅当松手时手指仍停在某按钮热区内才触发，
      // 否则直接收起（用户反悔）。
      final fire =
          !cancelled &&
          globalPosition != null &&
          _quickSelection >= 0 &&
          (globalPosition - _quickPositions[_quickSelection]).distance <=
              _quickHotRadius;
      _quickArcKey.currentState?.dismiss(fire: fire);
      return;
    }

    // 未移动：单击（记录时间用于双击判定）或双击直达。
    if (!gesture.moved) {
      if (!cancelled && gesture.doubleTap && globalX != null) {
        _nav.snapTo(_pageAtX(globalX).round());
      } else if (!cancelled) {
        _lastTapTime = timestamp;
      }
      return;
    }

    // 已移动：速度足够大则惯性滑动，否则就近吸附。
    if (!cancelled && _nav.dragReleaseVelocity.abs() > 1.15) {
      _nav.startFling(_nav.dragReleaseVelocity);
    } else {
      _nav.snapTo(_nav.nearestPage(_nav.position));
    }
  }

  /// 快捷弧触发：在选中项处显示涟漪。
  ///
  /// 真实快捷操作后续在此接入（当前仅视觉反馈）。
  void _handleQuickFire(int index) {
    Haptics.confirm();
    // 执行配置中该快捷操作的真实行为（当前为「开发中」占位反馈）。
    _quickActions[index].onSelect(context);
    setState(() {
      _ripples.add(RippleSpec(center: _quickPositions[index]));
    });
  }

  // ================================================================
  //  几何计算（薄封装：真实计算收敛在 DockLayout，输入为不可变事实）
  // ================================================================

  /// 当前几何快照：以 MediaQuery + 抽屉进度等不可变事实即时构造。
  DockLayout get _layout => DockLayout(
    size: MediaQuery.sizeOf(context),
    safeBottom: MediaQuery.paddingOf(context).bottom,
    pageCount: _destinations.length,
    drawerK: _drawerAnim.value,
  );

  Rect _handleHitRect() => _layout.handleHitRect;

  Rect _aiHitRect() => _layout.aiHitRect;

  ({Rect bar, Rect leftDot, Rect rightDot}) _navGeometry() =>
      _layout.navGeometry;

  Rect _searchCapsuleRect() => _layout.searchCapsuleRect;

  double _pageAtX(double globalX) => _layout.pageAtX(globalX);

  /// 计算快捷弧各操作项的位置与热区半径。
  ///
  /// 各按钮按 [_quickActions] 数量在四分之一椭圆曲线的中段自动
  /// 排布（规则见 [DockGeometry.layoutQuickArc]）。结果写入 State
  /// 缓存字段，故本方法保留在 State、只调用 [DockLayout] 的纯计算。
  void _computeQuickPositions() {
    final size = MediaQuery.sizeOf(context);
    final safeBottom = MediaQuery.paddingOf(context).bottom;

    final layout = DockGeometry.layoutQuickArc(
      origin: DockLayout.quickArcOrigin(size, safeBottom),
      count: _quickActions.length,
    );

    _quickPositions
      ..clear()
      ..addAll(layout.centers);
    _quickHotRadius = layout.hotRadius;
  }

  // ================================================================
  //  构建
  // ================================================================

  @override
  Widget build(BuildContext context) {
    final screenSize = MediaQuery.sizeOf(context);
    final safeBottom = MediaQuery.paddingOf(context).bottom;
    // 软键盘高度。**必须在本 State 的 context（Scaffold 之上）读取**：
    // Scaffold 在自动避让时会把 body 的 viewInsets.bottom 归零，
    // body 内部（含 _buildOverlays 拿到的 Builder context）读到的恒为 0。
    final keyboardInset = MediaQuery.viewInsetsOf(context).bottom;

    final scaffold = Scaffold(
      // 底部停靠件（把手条 / AI 条 / 导航胶囊 / 页码指示器 / 竖单 /
      // AI 对话框）一律钉在物理屏底边，**不随软键盘上浮**。
      // 关掉 Scaffold 的自动避让后 body 保持全屏高，这些底边锚点
      // （bottom: 常量 + safeBottom）也就固定在原位，被键盘遮住即可。
      // 真正需要避让键盘的只有两处，各自手动补偿：
      // - 页面轨道（日记编辑页光标）：_buildPageTrack 垫 keyboardInset；
      // - 搜索胶囊与 slash 层（输入框在胶囊里）：_buildOverlays 垫
      //   keyboardInset，且仅在搜索态（非搜索态胶囊就是导航条，须留原位）。
      resizeToAvoidBottomInset: false,
      // Builder 让本页操作配置能拿到 Scaffold 之下的 context
      // （ScaffoldMessenger/SnackBar）。
      body: Builder(
        builder: (context) {
          _bodyContext = context;
          return Listener(
            behavior: HitTestBehavior.translucent,
            onPointerDown: _handleRootPointerDown,
            onPointerMove: _handleRootPointerMove,
            onPointerUp: _handleRootPointerUp,
            onPointerCancel: _handleRootPointerCancel,
            child: Stack(
              children: [
                ..._buildStaticBackdrop(context),
                _buildPageTrack(context, screenSize, keyboardInset),
                ..._buildOverlays(
                  context,
                  screenSize,
                  safeBottom,
                  keyboardInset,
                ),
              ],
            ),
          );
        },
      ),
    );
    // 返回键：搜索态/快捷弧/竖单/AI 对话框/抽屉打开时先关浮层，
    // 不退出 App（canPop 在根树重建时随状态更新，
    // 见 _handleNavSearchToggled 与抽屉帧回调）。
    return ChatStoreScope(
      store: _chatStore,
      child: ChatSessionScope(
        controller: _chatSession,
        child: NavBadgeScope(
          service: _badges,
          child: PopScope(
            canPop:
                !_nav.isSearching &&
                !_quickArcShown &&
                !_menuShown &&
                !_aiShown &&
                _drawerAnim.value == 0,
            onPopInvokedWithResult: _handlePopInvoked,
            child: scaffold,
          ),
        ),
      ),
    );
  }

  /// 固定背景层：机能风纹理 + 顶部设备状态读数条。
  List<Widget> _buildStaticBackdrop(BuildContext context) => [
    // -------- 机能风背景（纹理随翻页同步平移，十字固定）--------
    //
    // 纹理与页面轨道 1:1 同速率横移：偏移 = 显示位置 × 屏宽。
    // 网格是周期图案，取模后视觉仍是连续平移；底图是无限画布，
    // 必须传未取模的连续位移，否则世界坐标跳回会让图案跳变。
    Positioned.fill(
      key: const ValueKey<String>('mech-bg'),
      child: AnimatedBuilder(
        animation: _nav,
        builder: (context, _) {
          final shift = -_nav.displayPosition * MediaQuery.sizeOf(context).width;
          return MechanicalBackground(
            panOffsetX: shift % MechanicalStyle.coarseGridSpacing,
            canvasOffsetX: shift,
          );
        },
      ),
    ),

    // -------- 机能风设备状态读数条（固定顶部）--------
    Positioned(
      key: const ValueKey<String>('mech-coords'),
      top: MediaQuery.paddingOf(context).top + MechanicalStyle.coordsTop,
      left: 0,
      right: 0,
      child: Center(
        child: MechanicalCoordsBar(
          stats: ControlBootstrap.instance?.registry.get<ConsoleStatsService>(),
        ),
      ),
    ),
  ];

  /// 横向页面轨道：大页码 + 各目的地页面，随导航显示位置横滑。
  ///
  /// [keyboardInset] 为软键盘高度：页面内容仍需避让键盘（否则日记编辑页
  /// 聚焦底部块时光标会藏在键盘后面），而底部停靠件要保持钉在原位，
  /// 故这里只给页面本身垫出键盘高度，不影响同级的浮层。
  Widget _buildPageTrack(
    BuildContext context,
    Size screenSize,
    double keyboardInset,
  ) => Positioned.fill(
    key: const ValueKey<String>('pages'),
    child: Padding(
      padding: EdgeInsets.only(bottom: keyboardInset),
      child: ClipRect(
        child: AnimatedBuilder(
          animation: _nav,
          builder: (context, _) {
            // 显示位置含橡胶带与磁力吸附曲线。
            final renderedPosition = _nav.displayPosition;
            return Stack(
              children: [
                Positioned(
                  left: -renderedPosition * screenSize.width,
                  top: 0,
                  bottom: 0,
                  width: screenSize.width * _destinations.length,
                  child: Stack(
                    children: [
                      // 机能风大页码：每页一格、页面之下，随轨道横滑。
                      Row(
                        children: [
                          for (var i = 0; i < _destinations.length; i++)
                            Expanded(
                              child: Stack(
                                children: [MechanicalPageNumber(index: i)],
                              ),
                            ),
                        ],
                      ),
                      Row(
                        // 页面由导航配置驱动：每个目的地的 pageBuilder
                        // 经 Builder 注入上下文，全部 Expanded 等宽。
                        children: [
                          for (final destination in _destinations)
                            Expanded(
                              child: Builder(builder: destination.pageBuilder),
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            );
          },
        ),
      ),
    ),
  );

  /// 浮层与底部三条：scrim / 快捷弧 / 涟漪 / 页码指示器 / AI 条 /
  /// 把手条 / 胶囊簇 / slash 层 / 抽屉 / 竖单 / AI 对话框。
  ///
  /// 子项顺序与原 Stack 逐字一致（含各 Key 与条件挂载位置）。
  /// [keyboardInset] 为软键盘高度：只作用于「搜索胶囊」与「slash 层」——
  /// 搜索态下输入框就在胶囊里，必须抬到键盘之上；非搜索态胶囊就是导航条，
  /// 须与其余底部停靠件一样留在原位（故只在搜索态补偿，避免键盘顶起）。
  List<Widget> _buildOverlays(
    BuildContext context,
    Size screenSize,
    double safeBottom,
    double keyboardInset,
  ) {
    // 底部三条几何（全部来自 DockGeometry，不靠运行时测量）。
    final handleWidth = DockGeometry.handleWidthFor(screenSize.width);
    final handleRestLeft = DockGeometry.handleLeftFor(screenSize.width);
    final handleDockedLeft = DockGeometry.dockedHandleLeftFor(screenSize.width);
    final drawerK = _drawerAnim.value;
    final handleLeft =
        handleRestLeft + (handleDockedLeft - handleRestLeft) * drawerK;
    final aiLeft = DockGeometry.aiLeftFor(screenSize.width);
    final aiWidth = DockGeometry.aiWidthFor(screenSize.width);
    // AI 对话框悬在软键盘之上：根 Scaffold 已关闭自动避让，这里必须
    // 手动补偿 keyboardInset，否则输入行会被键盘遮住。键盘弹起时与
    // 键盘的间距取左右边距（DockGeometry.sideMargin），使左、右、下
    // 三边等宽；收起时回到底部停靠条上方 38。高度再按键盘上方的可用
    // 空间收敛，避免小屏 + 键盘时面板顶出屏幕。
    final aiDialogBottom = keyboardInset > 0
        ? keyboardInset + DockGeometry.sideMargin
        : 38 + safeBottom;
    final aiDialogHeight = math.min(
      math.min(screenSize.height * 0.52, 360.0),
      math.max(0.0, screenSize.height - aiDialogBottom),
    );
    final bool barsHiddenBySearch = _nav.isSearching;
    // slash 面板底边 = 搜索胶囊上沿（胶囊底距 16+安全区，高 44，再留 8）。
    final slashLayerBottom =
        16 + safeBottom + DockGeometry.searchHeight + 8 + keyboardInset;

    return [
      // -------- 搜索态：全屏隐形 scrim（点外部关闭搜索）--------
      // 位于胶囊/结果/历史之下：点空白区命中 scrim 即关闭；
      // 点结果等上层组件时事件不会落到 scrim。
      if (_nav.isSearching)
        Positioned.fill(
          key: const ValueKey<String>('scrim'),
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: _exitSearch,
          ),
        ),

      // -------- 快捷操作弧 --------
      if (_quickArcShown)
        QuickActionArc(
          key: _quickArcKey,
          actions: _quickActions,
          positions: List.of(_quickPositions),
          selection: _quickSelection,
          onFire: _handleQuickFire,
          onDismissed: () {
            setState(() => _quickArcShown = false);
          },
        ),

      // -------- 触发涟漪 --------
      // 可同屏并存：按 RippleSpec.id 配对元素，先结束者移除时
      // 存留项不继承其动画 State（规范 1.6 / 事故 1 同类）。
      for (final spec in _ripples)
        Positioned(
          key: ValueKey<int>(spec.id),
          left: spec.center.dx - 30,
          top: spec.center.dy - 30,
          child: TriggerRipple(
            onEnded: () {
              setState(() => _ripples.remove(spec));
            },
          ),
        ),

      // -------- 页码指示器：左下页名牌 + 右下 3D 转鼓（仅横滑唤醒）--------
      Positioned(
        key: const ValueKey<String>('page-name-plate'),
        // 左边距与右下转鼓右边距同为 DockGeometry.sideMargin，
        // 两侧视觉对称（原 5vw 在 393dp 宽屏约 19.6dp，不对齐）。
        left: DockGeometry.sideMargin,
        // 色块底边与右下转鼓面板底边对齐（同为 52+safeBottom）。
        bottom: 52 + safeBottom,
        child: MechanicalPageNamePlate(
          controller: _nav,
          labels: [for (final d in _destinations) d.label],
        ),
      ),
      Positioned(
        key: const ValueKey<String>('roller'),
        right: DockGeometry.sideMargin,
        bottom: 52 + safeBottom,
        child: MechanicalPageDrum(
          controller: _nav,
          pageCount: _destinations.length,
        ),
      ),

      // -------- AI 虹彩条（常驻；搜索态由胶囊生长覆盖，先卸载） --------
      if (!barsHiddenBySearch)
        Positioned(
          key: const ValueKey<String>('ai-bar'),
          left: aiLeft,
          bottom: DockGeometry.bottomMargin + safeBottom - 4, // 光晕上下各溢 4px
          width: aiWidth,
          height: DockGeometry.barHeight + 8,
          child: AiBar(pressed: _aiPressed),
        ),

      // -------- 把手条（常态位：在胶囊之下，搜索生长时被覆盖） --------
      // 抽屉打开期间改由本 Stack 末尾的「停靠位把手」承载，二者
      // 不同时挂载（无状态外观组件，挂载切换无跳变）。
      if (!barsHiddenBySearch && !_menuShown && drawerK <= 0.001)
        Positioned(
          key: const ValueKey<String>('handle-bar'),
          left: handleLeft,
          bottom: DockGeometry.bottomMargin + safeBottom,
          width: handleWidth,
          height: DockGeometry.barHeight,
          child: const HandleBar(),
        ),

      // -------- 底部胶囊簇（历史 + 胶囊 + 倒计时边框） --------
      //
      // 根 Scaffold 已关闭自动避让（body 不再被键盘压缩），因此键盘高度
      // 必须在这里手动补偿：
      // - 搜索态（barsHiddenBySearch）：胶囊已 morph 成全宽搜索框、输入框
      //   就在其中，抬 keyboardInset 使其停在键盘上方；
      // - 非搜索态：胶囊是常规导航条，与把手/AI 条一样留在原位，不补偿。
      Positioned(
        key: const ValueKey<String>('capsule'),
        left: 14,
        right: 14,
        bottom: 16 + safeBottom + (barsHiddenBySearch ? keyboardInset : 0),
        child: SearchCapsule(
          controller: _nav,
          pageIds: [for (final d in _destinations) d.id],
          screenWidth: screenSize.width,
          pressedDot: _pressedDot,
          focusNode: _searchFocusNode,
          textController: _searchTextController,
          historyItems: _searchHistory.items.toSet().toList(growable: false),
          results: _searchResults,
          query: _searchQuery,
          onHistoryTap: _handleHistoryTap,
          onResultTap: _handleResultTap,
          onQueryChanged: _handleQueryChanged,
          onSubmitted: _handleSubmitted,
          slashMode: (_slash?.active ?? false) && _nav.isSearching,
          slashController: _slash,
        ),
      ),

      // -------- slash 指令态浮层（补全/结果/模态卡） --------
      // 叠在胶囊之上、抽屉与竖单之下；指令态退出时零占位。
      // 只在搜索态挂载，故与胶囊同步抬 keyboardInset（无双重补偿）。
      // 顶边钉在 DockGeometry.slashPanelTop（y=40），底边随输入框移动：
      // 面板高度 = 40 → 胶囊上沿，软键盘开合都自适应撑满。
      if (_slash != null && _nav.isSearching)
        Positioned(
          key: const ValueKey<String>('slash-layer'),
          left: 14,
          right: 14,
          // 极小屏 + 键盘时留 1px 兜底，避免 top+bottom 超过屏高。
          top: math.min(
            DockGeometry.slashPanelTop,
            math.max(0.0, screenSize.height - slashLayerBottom - 1),
          ),
          bottom: slashLayerBottom,
          child: SlashCommandLayer(controller: _slash!),
        ),

      // -------- 侧边抽屉（空壳面板 + 遮罩，在胶囊/AI 条之上） --------
      if (drawerK > 0.001)
        Positioned.fill(
          key: const ValueKey<String>('side-drawer'),
          child: SideDrawer(
            progress: _drawerAnim,
            onScrimTap: () => _settleDrawer(open: false),
          ),
        ),

      // -------- 停靠位把手：抽屉打开期间浮在遮罩之上，
      // 保证把手始终明亮可拖（与常态位把手不同时挂载）。 --------
      if (!barsHiddenBySearch && !_menuShown && drawerK > 0.001)
        Positioned(
          key: const ValueKey<String>('handle-bar-docked'),
          left: handleLeft,
          bottom: DockGeometry.bottomMargin + safeBottom,
          width: handleWidth,
          height: DockGeometry.barHeight,
          child: const HandleBar(),
        ),

      // -------- 本页操作竖单（点按遮罩任意处收起） --------
      if (_menuShown) ...[
        Positioned.fill(
          key: const ValueKey<String>('menu-scrim'),
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => _handleMenuKey.currentState?.dismiss(),
          ),
        ),
        Positioned(
          key: const ValueKey<String>('handle-menu'),
          left: handleRestLeft,
          bottom: DockGeometry.bottomMargin + safeBottom,
          width: handleWidth,
          child: HandleMenu(
            key: _handleMenuKey,
            actions: _currentPageActions(),
            handleWidth: handleWidth,
            onFire: _handlePageActionFire,
            onDismissed: _handleMenuDismissed,
          ),
        ),
      ],

      // -------- AI 对话框（点按遮罩任意处收起） --------
      if (_aiShown) ...[
        Positioned.fill(
          key: const ValueKey<String>('ai-scrim'),
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => _aiDialogKey.currentState?.dismiss(),
          ),
        ),
        Positioned(
          key: const ValueKey<String>('ai-dialog'),
          left: DockGeometry.sideMargin,
          right: DockGeometry.sideMargin,
          bottom: aiDialogBottom,
          height: aiDialogHeight,
          child: AiDialog(key: _aiDialogKey, onDismissed: _handleAiDismissed),
        ),
      ],
    ];
  }
}
