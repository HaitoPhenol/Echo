import 'dart:async';

import 'package:flutter/material.dart';

import '../diary/data/diary_repository.dart';
import '../services/chat_store.dart';
import '../navigation/smart_nav_screen.dart';
import '../theme/app_colors.dart';
import 'app_services.dart';

/// Echo 应用根组件。
///
/// 负责全局主题配置、装配根生命周期与首页挂载。当前为开发期深色主题，
/// 首页是智能导航实验屏 [SmartNavScreen]。
class EchoApp extends StatefulWidget {
  const EchoApp({super.key, this.diaryRepository, this.chatRepository});

  /// 测试注入缝：装配根打开日记模块时使用的仓储；生产环境为 null。
  final DiaryRepository? diaryRepository;

  /// 测试注入缝：聊天历史仓储；生产环境为 null（装配根用持久化仓储）。
  final ChatRepository? chatRepository;

  @override
  State<EchoApp> createState() => _EchoAppState();
}

class _EchoAppState extends State<EchoApp> {
  /// 应用装配根：跨页共享的日记模块/聊天服务与导航配置。
  late final AppServices _services;

  @override
  void initState() {
    super.initState();
    _services = AppServices.create(
      diaryRepository: widget.diaryRepository,
      chatRepository: widget.chatRepository,
    );
  }

  @override
  void dispose() {
    unawaited(_services.dispose());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Echo',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        scaffoldBackgroundColor: AppColors.background,
        colorScheme: ColorScheme.fromSeed(
          seedColor: AppColors.accentBlue,
          brightness: Brightness.dark,
        ),
        // M3 默认 SnackBar 是反色浅底（inverseSurface），与应用近黑
        // 浮层语言冲突；统一为 overlaySurface 深底 + 白字、贴底常驻样式。
        snackBarTheme: SnackBarThemeData(
          behavior: SnackBarBehavior.fixed,
          backgroundColor: AppColors.overlaySurface,
          contentTextStyle: const TextStyle(color: AppColors.textPrimary),
          actionTextColor: AppColors.accentBlue,
          elevation: 0,
        ),
      ),
      home: SmartNavScreen(
        destinations: _services.destinations,
        diaryPage: () => _services.diaryPage,
        chatStore: _services.chatStore,
        chatSession: _services.chatSession,
        aiChat: _services.aiChat,
        settingsPageBuilder: _services.settingsPage,
      ),
    );
  }
}
