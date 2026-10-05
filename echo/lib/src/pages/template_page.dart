import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

/// 空白模板页面。
///
/// 当前不承载任何业务内容，仅居中显示一个数字标号，
/// 用于验证页面轨道与智能导航线的翻页效果。
/// 后续开发某一具体页面时，直接替换本页面的内容（或复制本页新建页面）。
class TemplatePage extends StatelessWidget {
  const TemplatePage({super.key, required this.index});

  /// 页面在导航轨道中的序号（从 0 开始）
  final int index;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: AppColors.background,
      child: Center(
        child: Text(
          '${index + 1}',
          style: const TextStyle(
            fontSize: 96,
            fontWeight: FontWeight.w200,
            color: AppColors.textPrimary,
          ),
        ),
      ),
    );
  }
}
