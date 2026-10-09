import 'package:flutter/material.dart';

import '../../theme/app_colors.dart';
import '../../theme/mechanical_style.dart';
import '../nav_physics.dart';

/// 机能风左下角页名牌（横滑唤醒时与转鼓同时浮现）。
///
/// 移植自设计工程稿 `ideas/mechanical_style_page.html` 的左下角
/// 「#pgname」（稿 L305-317、L918-938）：半透明面板色块内一个大字
/// 页名 + 下方 56px 短横线；显隐节奏与 [MechanicalPageDrum] 完全一致
/// （同一个 rollerVisible、同一组时长/曲线），文字在页位置跨过中点时
/// 硬切（`NavPhysicsController.activePage` = nearestPage），与原稿
/// `Math.round(x/W)` 行为相同。
///
/// 组件只负责内容与显隐；屏幕位置由调用方用 [Positioned] 给定：
/// left:5vw，色块底边与右下转鼓面板底边对齐（52+安全区；
/// 原稿 bottom:26 的定位未采用，以用户真机裁决的底对齐为准）。
class MechanicalPageNamePlate extends StatelessWidget {
  const MechanicalPageNamePlate({
    super.key,
    required this.controller,
    required this.labels,
  });

  final NavPhysicsController controller;

  /// 按轨道顺序排列的页名（由 NavDestination.label 统一提供）。
  final List<String> labels;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        final visible = controller.rollerVisible;
        final index = controller.activePage.clamp(0, labels.length - 1);
        return IgnorePointer(
          ignoring: !visible,
          child: AnimatedOpacity(
            opacity: visible ? 1 : 0,
            duration: MechanicalStyle.indicatorFadeDuration,
            child: AnimatedSlide(
              offset: visible ? Offset.zero : const Offset(0, 0.4),
              duration: MechanicalStyle.indicatorRiseDuration,
              curve: const Cubic(0.3, 1.4, 0.4, 1),
              child: DecoratedBox(
                // 稿 rgba(15,15,15,.90)：基色用 mechDrumPanel 具名 token。
                decoration: BoxDecoration(
                  color: AppColors.mechDrumPanel.withValues(alpha: 0.90),
                ),
                child: Padding(
                  padding: const EdgeInsets.only(
                    left: MechanicalStyle.namePlatePadH,
                    top: MechanicalStyle.namePlatePadTop,
                    right: MechanicalStyle.namePlatePadH,
                    bottom: MechanicalStyle.namePlatePadBottom,
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        labels[index],
                        style: TextStyle(
                          // 稿 --serif 栈（Songti SC/STSong/Noto Serif
                          // CJK SC/SimSun…）：不打包字体，走系统 serif
                          // 通用族——Android 西文 NotoSerif、中文回退
                          // NotoSerifCJK（无 Bold 面时由引擎合成加粗）。
                          fontFamily: 'serif',
                          fontSize: MechanicalStyle.namePlateFontSize,
                          fontWeight: FontWeight.w700,
                          letterSpacing:
                              MechanicalStyle.namePlateLetterSpacing,
                          height: 1,
                          color: AppColors.mechInk,
                          // 稿 text-shadow:0 2px 12px rgba(0,0,0,.6)
                          shadows: [
                            Shadow(
                              color: Colors.black.withValues(alpha: 0.6),
                              offset: const Offset(0, 2),
                              blurRadius: 12,
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(
                        height: MechanicalStyle.namePlateUnderlineGap,
                      ),
                      Container(
                        width: MechanicalStyle.namePlateUnderlineWidth,
                        height: MechanicalStyle.namePlateUnderlineHeight,
                        color: AppColors.mechInk,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
