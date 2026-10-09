import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/mechanical_style.dart';

/// 空白占位页面。
///
/// 当前不承载任何业务内容，仅居中显示页面标题，
/// 用于标识当前所在页面。后续开发某一具体页面时，
/// 直接替换本页面的内容（或复制本页新建页面）。
class TemplatePage extends StatelessWidget {
  const TemplatePage({
    super.key,
    required this.title,
    this.secCode,
    this.secName,
    this.footer,
  });

  /// 页面标题（与导航配置中的 label 一致）。
  final String title;

  /// 机能风分区编号（如 SEC.01）；null 时不显示 kicker。
  final String? secCode;

  /// 机能风分区英文名（如 CONSOLE）；与 [secCode] 成对出现。
  final String? secName;

  /// 标题下方的附属区域（当前用于放置测试按钮，无内容时不占位）。
  final Widget? footer;

  @override
  Widget build(BuildContext context) {
    final showKicker = secCode != null && secName != null;
    // 底色透明：由主屏 Stack 底层的 MechanicalBackground 透出固定纹理，
    // 页面本体只承载内容。
    return ColoredBox(
      color: Colors.transparent,
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // 机能风分区小标题（稿 .kick：SEC.01 // CONSOLE，
            // 仅 // 用 dim 色）。
            if (showKicker) ...[
              Text.rich(
                TextSpan(
                  children: [
                    TextSpan(text: '$secCode '),
                    const TextSpan(
                      style: TextStyle(
                        fontWeight: FontWeight.w400,
                        color: AppColors.mechInkDim,
                      ),
                      text: '// ',
                    ),
                    TextSpan(text: secName),
                  ],
                ),
                style: TextStyle(
                  fontSize: MechanicalStyle.kickerFontSize,
                  fontWeight: FontWeight.w700,
                  letterSpacing: MechanicalStyle.kickerLetterSpacing,
                  color: AppColors.mechInk,
                  height: 1.2,
                ),
              ),
              const SizedBox(height: 22),
            ],
            // 大字距下 Flutter 在末字后也追加一个字距，布局盒比墨水
            // 宽出一个 letterSpacing；向左补偿半个字距做光学居中
            // （真机 PIL 像素校验：补偿后控制台/日志/我三页墨水中心
            // 均为屏中 540，见 29.png）。
            Transform.translate(
              offset: const Offset(
                -MechanicalStyle.pageTitleLetterSpacing / 2,
                0,
              ),
              child: Text(
                title,
                style: const TextStyle(
                  fontSize: MechanicalStyle.pageTitleFontSize,
                  fontWeight: MechanicalStyle.pageTitleFontWeight,
                  letterSpacing: MechanicalStyle.pageTitleLetterSpacing,
                  color: AppColors.textPrimary,
                ),
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
