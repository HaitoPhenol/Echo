import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../../theme/app_colors.dart';
import '../dock_geometry.dart';

/// 把手条右拖后从左缘滑入的**侧边抽屉**（当前为空壳）。
///
/// 由父级传入 0..1 的开合进度（跟手拖动期间直接写值、松手后由
/// AnimationController 吸附），本组件只负责呈现：
/// - 全屏遮罩：黑 α.44 随进度淡入，点按关闭抽屉；
/// - 抽屉面板：宽 min(78vw,340)，右侧 22px 圆角、深色表面叠 18px
///   毛玻璃、右缘细描边，内容**留空**（本阶段不承载任何东西）。
///
/// 面板整体 [IgnorePointer]：内部无交互物，点按穿透到遮罩 → 关闭。
/// 把手条自身（在本组件之上）始终可拖，是关闭抽屉的主手势。
class SideDrawer extends StatelessWidget {
  const SideDrawer({
    super.key,
    required this.progress,
    required this.onScrimTap,
  });

  /// 开合进度 0（全关）..1（全开）。
  final Animation<double> progress;

  /// 点按遮罩（或穿透而来的面板空白区）。
  final VoidCallback onScrimTap;

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.sizeOf(context).width;
    final drawerWidth = DockGeometry.drawerWidthFor(screenWidth);

    return AnimatedBuilder(
      animation: progress,
      builder: (context, _) {
        final k = progress.value;
        return Stack(
          children: [
            // -------- 遮罩（面板之下） --------
            Positioned.fill(
              child: IgnorePointer(
                ignoring: k == 0,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: onScrimTap,
                  child: ColoredBox(
                    color: Colors.black.withValues(alpha: 0.44 * k),
                  ),
                ),
              ),
            ),

            // -------- 抽屉面板 --------
            Positioned(
              top: 0,
              bottom: 0,
              left: 0,
              width: drawerWidth,
              child: IgnorePointer(
                child: Transform.translate(
                  offset: Offset(-drawerWidth * (1 - k), 0),
                  child: RepaintBoundary(
                    child: ClipRRect(
                      borderRadius: const BorderRadius.horizontal(
                        right: Radius.circular(22),
                      ),
                      child: Stack(
                        children: [
                          // 毛玻璃底层（裁剪在圆角内）。
                          Positioned.fill(
                            child: BackdropFilter(
                              filter: ui.ImageFilter.blur(sigmaX: 18, sigmaY: 18),
                              child: const SizedBox.expand(),
                            ),
                          ),
                          // 深色表面 + 右缘描边。
                          Positioned.fill(
                            child: DecoratedBox(
                              decoration: const BoxDecoration(
                                color: AppColors.drawerSurface,
                                border: Border(
                                  right: BorderSide(color: AppColors.tone1),
                                ),
                              ),
                            ),
                          ),
                          // 内容区：按产品要求留空。
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}
