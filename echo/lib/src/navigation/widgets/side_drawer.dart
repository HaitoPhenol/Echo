import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../../theme/app_colors.dart';
import '../dock_geometry.dart';

/// 把手条右拖后从左缘滑入的**侧边抽屉**。
///
/// 由父级传入 0..1 的开合进度（跟手拖动期间直接写值、松手后由
/// AnimationController 吸附），本组件只负责呈现：
/// - 全屏遮罩：黑 α.44 随进度淡入，点按关闭抽屉；
/// - 抽屉面板：宽 min(78vw,340)，右侧 22px 圆角、深色表面叠 18px
///   毛玻璃；面板内当前只放「设置」入口。
///
/// 面板空白区不做命中拦截：点按会穿透到遮罩 → 关闭抽屉；
/// 只有设置入口自身可点。把手条（在本组件之上）始终可拖。
class SideDrawer extends StatelessWidget {
  const SideDrawer({
    super.key,
    required this.progress,
    required this.onScrimTap,
    required this.onOpenSettings,
  });

  /// 开合进度 0（全关）..1（全开）。
  final Animation<double> progress;

  /// 点按遮罩（或穿透而来的面板空白区）。
  final VoidCallback onScrimTap;

  /// 点按面板内的「设置」入口。
  final VoidCallback onOpenSettings;

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.sizeOf(context).width;
    final drawerWidth = DockGeometry.drawerWidthFor(screenWidth);
    final topInset = MediaQuery.paddingOf(context).top;

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
                            filter: ui.ImageFilter.blur(
                              sigmaX: 18,
                              sigmaY: 18,
                            ),
                            child: const SizedBox.expand(),
                          ),
                        ),
                        // 深色表面（不画右缘描边：圆角侧的 1px 线在
                        // 深色背景上呈现为突兀的竖线，圆角本身已足够分界）。
                        const Positioned.fill(
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              color: AppColors.drawerSurface,
                            ),
                          ),
                        ),
                        // 内容区：当前只有设置入口。
                        Padding(
                          padding: EdgeInsets.fromLTRB(
                            18,
                            topInset + 24,
                            18,
                            24,
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text.rich(
                                TextSpan(
                                  children: [
                                    const TextSpan(text: 'SYS '),
                                    const TextSpan(
                                      style: TextStyle(
                                        color: AppColors.mechInkDim,
                                      ),
                                      text: '// ',
                                    ),
                                    const TextSpan(text: 'ECHO'),
                                  ],
                                ),
                                style: const TextStyle(
                                  fontFamily: 'monospace',
                                  fontSize: 10.5,
                                  fontWeight: FontWeight.w700,
                                  letterSpacing: 1.2,
                                  color: AppColors.mechInk,
                                ),
                              ),
                              const SizedBox(height: 18),
                              _DrawerEntry(
                                onTap: onOpenSettings,
                                icon: Icons.settings_outlined,
                                title: '设置',
                                subtitle: '模型 API · MCP',
                              ),
                            ],
                          ),
                        ),
                      ],
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

/// 抽屉内的一条入口：图标 + 标题 + 副标题。
class _DrawerEntry extends StatelessWidget {
  const _DrawerEntry({
    required this.onTap,
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  final VoidCallback onTap;
  final IconData icon;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.tone1),
        ),
        child: Row(
          children: [
            Icon(icon, size: 18, color: AppColors.pageLabel),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    subtitle,
                    style: const TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 10.5,
                      letterSpacing: 0.4,
                      color: AppColors.mechInkDim,
                    ),
                  ),
                ],
              ),
            ),
            const Icon(
              Icons.chevron_right,
              size: 18,
              color: AppColors.textMuted,
            ),
          ],
        ),
      ),
    );
  }
}
