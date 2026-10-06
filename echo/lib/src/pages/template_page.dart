import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

/// 空白占位页面。
///
/// 当前不承载任何业务内容，仅居中显示页面标题，
/// 用于标识当前所在页面。后续开发某一具体页面时，
/// 直接替换本页面的内容（或复制本页新建页面）。
class TemplatePage extends StatelessWidget {
  const TemplatePage({super.key, required this.title, this.footer});

  /// 页面标题（与导航配置中的 label 一致）。
  final String title;

  /// 标题下方的附属区域（当前用于放置测试按钮，无内容时不占位）。
  final Widget? footer;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: AppColors.background,
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              title,
              style: const TextStyle(
                fontSize: 48,
                fontWeight: FontWeight.w200,
                color: AppColors.textPrimary,
              ),
            ),
            if (footer != null) const SizedBox(height: 48),
            ?footer,
          ],
        ),
      ),
    );
  }
}
