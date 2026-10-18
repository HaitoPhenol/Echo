import 'package:flutter/material.dart';

import '../../../theme/app_colors.dart';
import '../../../theme/mechanical_style.dart';

/// 日记层级页共用骨架：透明底（透背景机械纹理）、安全区、
/// 底部停靠条避让、机能风 kicker + 大标题（无分隔线，背景网格
/// 承担视觉分隔）。
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
    // 页面本体透明：直接透出 app 层机械网格纹理（与其他页一致，
    // 不再叠加压暗层）。命中仍不透明——转场期下层路由还在树中，
    // 空白区域的点击必须被本页吞掉，不能穿透到下层年/月列表。
    return Listener(
      behavior: HitTestBehavior.opaque,
      onPointerDown: (_) {},
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
                  // 头部行统一 28px 高、内容垂直居中：返回箭头与 kicker
                  // 的绝对位置在年/月/日/编辑四页完全一致，不随 trailing
                  // （补记/心情/撤销/保存/归档）自身高度浮动。各 trailing
                  // 控件高度必须 ≤ 28，超出会把行重新撑高造成错位。
                  SizedBox(
                    height: 28,
                    child: Row(
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
                  ),
                  const SizedBox(height: 12),
                  // 标题行单独上移（≈40 设备像素）：kicker/返回键行不动，
                  // 仅大标题向头部行贴近；用 Transform 而非负间距，
                  // 布局流保持非负。
                  Transform.translate(
                    offset: const Offset(0, -13),
                    child: Text(
                      title,
                      style: const TextStyle(
                        fontSize: MechanicalStyle.pageTitleFontSize,
                        fontWeight: MechanicalStyle.pageTitleFontWeight,
                        letterSpacing: 1.2,
                        color: AppColors.textPrimary,
                        height: 1.05,
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
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
    );
  }
}
