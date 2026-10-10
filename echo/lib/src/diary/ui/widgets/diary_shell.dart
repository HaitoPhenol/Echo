import 'package:flutter/material.dart';

import '../../../theme/app_colors.dart';
import '../../../theme/mechanical_style.dart';

/// 日记层级页共用骨架：透明底（透背景机械纹理）、安全区、
/// 底部停靠条避让、机能风 kicker + 大标题 + 1px 分隔线。
///
/// 不提供 AppBar：返回键是标题区左侧的自定义小按钮，与整页
/// 「无标题栏」语言一致（见 ChatPage）。
class DiaryShell extends StatelessWidget {
  const DiaryShell({
    super.key,
    required this.kicker,
    required this.title,
    required this.child,
    this.onBack,
    this.trailing,
  });

  /// 分区小字，如 'DIARY // YEAR'。
  final String kicker;

  /// 大标题。
  final String title;

  /// null 时不显示返回按钮（层级根页）。
  final VoidCallback? onBack;

  /// 标题行右侧可选操作（编辑页后续放导出/撤销等）。
  final Widget? trailing;

  final Widget child;

  /// 底部悬浮停靠三条避让（与 ChatPage._dockReservedHeight 同值）。
  static const double dockReservedHeight = 26;

  @override
  Widget build(BuildContext context) {
    // 背景半透明但命中不透明：层级路由 opaque:false，下层路由仍在树中，
    // 空白区域的点击必须被本页吞掉，不能穿透到下层年/月列表。
    return Listener(
      behavior: HitTestBehavior.opaque,
      onPointerDown: (_) {},
      child: ColoredBox(
        color: AppColors.background.withValues(alpha: 0.55),
        child: Material(
          type: MaterialType.canvas,
          color: Colors.transparent,
          child: SafeArea(
            bottom: false,
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: MechanicalStyle.frameInset,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      if (onBack != null)
                        GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onTap: onBack,
                          child: Padding(
                            padding: const EdgeInsets.only(right: 10),
                            child: Icon(
                              Icons.arrow_back_ios_new,
                              size: 14,
                              color: AppColors.pageLabel,
                            ),
                          ),
                        ),
                      Expanded(
                        child: Text(
                          kicker,
                          style: const TextStyle(
                            fontSize: MechanicalStyle.kickerFontSize,
                            letterSpacing: MechanicalStyle.kickerLetterSpacing,
                            color: AppColors.mechInkDim,
                          ),
                        ),
                      ),
                      ?trailing,
                    ],
                  ),
                  const SizedBox(height: 12),
                  Text(
                    title,
                    style: const TextStyle(
                      fontSize: MechanicalStyle.pageTitleFontSize,
                      fontWeight: MechanicalStyle.pageTitleFontWeight,
                      letterSpacing: 1.2,
                      color: AppColors.textPrimary,
                      height: 1.05,
                    ),
                  ),
                  const SizedBox(height: 14),
                  Container(height: 1, color: AppColors.tone1),
                  const SizedBox(height: 6),
                  Expanded(child: child),
                  SizedBox(
                    height:
                        MediaQuery.paddingOf(context).bottom +
                        dockReservedHeight,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
