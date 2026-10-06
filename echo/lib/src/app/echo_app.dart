import 'package:flutter/material.dart';

import '../navigation/smart_nav_screen.dart';
import '../theme/app_colors.dart';

/// Echo 应用根组件。
///
/// 负责全局主题配置与首页挂载。当前为开发期深色主题，
/// 首页是智能导航实验屏 [SmartNavScreen]。
class EchoApp extends StatelessWidget {
  const EchoApp({super.key});

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
      home: const SmartNavScreen(),
    );
  }
}
