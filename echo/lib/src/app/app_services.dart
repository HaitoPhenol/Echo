import 'dart:async';

import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/widgets.dart';

import '../ai/ai_chat_controller.dart';
import '../ai/ai_config_store.dart';
import '../control/bootstrap.dart';
import '../diary/data/diary_repository.dart';
import '../diary/diary_module.dart';
import '../diary/diary_page_handle.dart';
import '../diary/ui/diary_page.dart';
import '../navigation/nav_destination.dart';
import '../navigation/nav_destination_specs.dart';
import '../pages/chat_page.dart';
import '../pages/console_page.dart';
import '../pages/debug_badge_controls.dart';
import '../pages/settings_page.dart';
import '../pages/template_page.dart';
import '../services/chat_repository_file.dart';
import '../services/chat_session_controller.dart';
import '../services/chat_store.dart';

/// 应用装配根：集中创建并持有跨页共享的领域实例与导航配置。
///
/// 导航屏只消费本类产出的实例，不再自己 new 聊天服务，也不 import
/// 日记数据层/具体页面；具体页面与本处绑定（页面构造器抽象见
/// [NavDestination.pageBuilder]）。
class AppServices {
  AppServices._(
    this.destinations,
    this.chatStore,
    this.chatSession,
    this.aiConfigStore,
    this.aiChat,
    this._chatRepository,
    this._ownsChatRepository,
    this._diaryModule,
    this._diaryPageKey,
  );

  /// 导航目的地配置（含具体页面绑定）的唯一来源。
  final List<NavDestination> destinations;

  /// 聊天会话数据服务（会话增删 / 已读未读 / 消息）。
  final ChatStore chatStore;

  /// 当前打开会话控制器（点按行与 chat.open 命令同源）。
  final ChatSessionController chatSession;

  /// AI 模型配置存储（设置页读写；异步从私有目录载入）。
  final AiConfigStore aiConfigStore;

  /// AI 对话编排器（AI 对话框与聊天页全屏对话共用同一份状态）。
  final AiChatController aiChat;

  /// 聊天数据仓储（AI 会话与普通会话同源；生产为私有目录持久化）。
  final ChatRepository _chatRepository;

  /// 仓储是否由装配根创建（外部注入的实例不由本处释放）。
  final bool _ownsChatRepository;

  final GlobalKey<DiaryPageState> _diaryPageKey;
  final Future<DiaryModule> _diaryModule;

  bool _disposed = false;

  /// 日记页能力句柄：页面未挂载时为 null。
  ///
  /// 导航屏经此驱动日记内层栈（今日日记/补记/插入时间戳）与导出提醒，
  /// 只依赖 [DiaryPageHandle] 抽象，不认识具体页面实现。
  DiaryPageHandle? get diaryPage => _diaryPageKey.currentState;

  /// 设置页构造器：导航屏只拿此闭包压栈，不 import 具体页面实现。
  Widget settingsPage(BuildContext context) =>
      SettingsPage(store: aiConfigStore);

  /// 按生产口径装配：日记模块异步开库（测试注入仓储时跳过文件 I/O），
  /// 聊天历史在生产环境落私有目录、测试环境留在内存；所有实例随
  /// App 生命周期释放。
  static AppServices create({
    DiaryRepository? diaryRepository,
    ChatRepository? chatRepository,
  }) {
    final diaryPageKey = GlobalKey<DiaryPageState>();
    final diaryModule = DiaryModule.open(
      repository: diaryRepository,
      seedDebugData: kDebugMode,
    );
    // 测试注入日记仓储即为「无真实文件 I/O」的环境，聊天历史同步走
    // 内存，避免 path_provider 在 fake-async 区卡住；生产用持久化仓储。
    final ownedChatRepository = chatRepository == null;
    final repository = chatRepository ??
        (diaryRepository == null
            ? FileChatRepository()
            : InMemoryChatRepository());
    final chatStore = ChatStore(repository: repository);
    final chatSession = ChatSessionController(chatStore);

    // AI 配置：先在内存里可用，异步读取私有目录文件；读失败保持空配置。
    final aiConfigStore = AiConfigStore();
    unawaited(aiConfigStore.load());

    // 内置 AI 会话：等历史读盘完成后确保存在（已有则不重复插入）。
    unawaited(
      chatStore.ensureAiConversation(
        id: AiConversation.id,
        nickname: AiConversation.nickname,
        preview: AiConversation.idlePreview,
      ),
    );

    final aiChat = AiChatController(
      chatStore: chatStore,
      configStore: aiConfigStore,
    );

    // (id, 标题) 唯一来源在 kNavDestinationSpecs（控制层共用）。
    final destinations = <NavDestination>[
      for (final spec in kNavDestinationSpecs)
        NavDestination(
          id: spec.id,
          label: spec.label,
          icon: null, // TODO: 各页面定型后在此填入图标
          pageBuilder: (_) => switch (spec.id) {
            'console' => ConsolePage(
              // 仅 debug 构建挂锚点调试面板；release 传 null，调试组件
              // 随树摇移除。
              footer: kDebugMode
                  ? ConsoleBadgeControls(consolePageId: spec.id)
                  : null,
            ),
            'chat' => const ChatPage(),
            // 生产环境（无测试注入仓储）开屏预进今日日记编辑页：
            // 日记页随轨道离屏常驻，先把今日编辑页压进内层栈，
            // 用户横滑到笔记页即见今日日记。
            'notes' => DiaryPage(
              key: diaryPageKey,
              diaryModule: diaryModule,
              preEnterToday: diaryRepository == null,
              // 导出提醒红锚点按稳定目的地 id 上报。
              badgeDestinationId: spec.id,
            ),
            _ => TemplatePage(
              title: spec.label,
              secCode: spec.id == 'me' ? 'SEC.04' : null,
              secName: spec.id == 'me' ? 'ME' : null,
            ),
          },
        ),
    ];

    final services = AppServices._(
      destinations,
      chatStore,
      chatSession,
      aiConfigStore,
      aiChat,
      repository,
      ownedChatRepository,
      diaryModule,
      diaryPageKey,
    );
    services._registerWithControl();
    return services;
  }

  /// ECP 接线：把与 UI 同源的聊天实例注册给控制面
  /// （widget 测试未走 ControlBootstrap.init 时 instance 为 null，静默跳过）。
  void _registerWithControl() {
    final registry = ControlBootstrap.instance?.registry;
    registry
      ?..set(chatStore)
      // 命令层按抽象 ChatRepository 解析，与 UI 同源同一个 store。
      ..set<ChatRepository>(chatStore)
      ..set(chatSession);
  }

  /// 释放装配根：解除控制面注册，释放聊天服务与日记模块（幂等）。
  ///
  /// 外部注入的日记仓储不归模块所有，模块 dispose 不会关闭它。
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;

    final registry = ControlBootstrap.instance?.registry;
    registry
      ?..unset<ChatStore>()
      ..unset<ChatRepository>()
      ..unset<ChatSessionController>();

    chatSession.dispose();
    aiChat.dispose();
    chatStore.dispose();
    if (_ownsChatRepository) _chatRepository.dispose();
    aiConfigStore.dispose();

    try {
      final module = await _diaryModule;
      await module.dispose();
    } catch (_) {
      // 模块异步装配失败时无实例可释放。
    }
  }
}
