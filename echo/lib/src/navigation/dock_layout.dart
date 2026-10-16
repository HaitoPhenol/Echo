import 'package:flutter/material.dart';

import 'dock_geometry.dart';

/// 底部三条与页面轨道相关几何的纯计算容器。
///
/// 输入只有不可变事实（屏尺寸、安全区、页数、抽屉进度）；所有坐标
/// 一律由 [DockGeometry] 静态常量推算，不新增/复制任何数值，也不读取
/// 除入参之外的隐式来源（原实现散在 State 里隐式读 MediaQuery）。
class DockLayout {
  DockLayout({
    required this.size,
    required this.safeBottom,
    required this.pageCount,
    required this.drawerK,
  });

  /// 屏幕尺寸。
  final Size size;

  /// 底部安全区高度。
  final double safeBottom;

  /// 页面总数（页面轨道的页数）。
  final int pageCount;

  /// 抽屉开合进度（0..1，影响把手停靠位热区的横向位置）。
  final double drawerK;

  /// 底边三条共用的顶边 y（把手条 / AI 条 / 导航条等高）。
  double get dockTop =>
      size.height -
      safeBottom -
      DockGeometry.bottomMargin -
      DockGeometry.barHeight;

  /// 把手条可视矩形（左下角：左边距 14、宽 12% 屏宽、高 10）。
  Rect get handleRect => Rect.fromLTWH(
    DockGeometry.handleLeftFor(size.width),
    dockTop,
    DockGeometry.handleWidthFor(size.width),
    DockGeometry.barHeight,
  );

  /// AI 条可视矩形（把手条右侧 14px 间隙，宽 38vw - 56）。
  Rect get aiRect => Rect.fromLTWH(
    DockGeometry.aiLeftFor(size.width),
    dockTop,
    DockGeometry.aiWidthFor(size.width),
    DockGeometry.barHeight,
  );

  /// 把手隐形热区：纵向同导航条规则（向上 32、向下 10），横向不
  /// 扩展；左边距随抽屉开合在常态位与停靠位之间滑动。
  Rect get handleHitRect {
    final width = size.width;
    final visual = handleRect;
    final rest = DockGeometry.handleLeftFor(width);
    final docked = DockGeometry.dockedHandleLeftFor(width);
    final left = rest + (docked - rest) * drawerK;
    return Rect.fromLTRB(
      left,
      visual.top - 32,
      left + DockGeometry.handleWidthFor(width),
      visual.bottom + 10,
    );
  }

  /// AI 条隐形热区：纵向向上 32、向下 10，横向等于条自身长度。
  Rect get aiHitRect {
    final visual = aiRect;
    return Rect.fromLTRB(
      visual.left,
      visual.top - 32,
      visual.right,
      visual.bottom + 10,
    );
  }

  /// 常规态导航组件的三个可视矩形：导航条、左圆点、右圆点。
  ///
  /// 整体右对齐（右边距 14）、底边距 16；圆点与导航条等高 10，
  /// 圆点与导航条间距 5。
  ({Rect bar, Rect leftDot, Rect rightDot}) get navGeometry {
    final assemblyWidth = DockGeometry.navAssemblyWidthFor(size.width);
    final barWidth = DockGeometry.navBarWidthFor(size.width);

    final top = dockTop;
    final right = size.width - DockGeometry.sideMargin;

    final leftDot = Rect.fromLTWH(
      right - assemblyWidth,
      top,
      DockGeometry.dotDiameter,
      DockGeometry.barHeight,
    );
    final rightDot = Rect.fromLTWH(
      right - DockGeometry.dotDiameter,
      top,
      DockGeometry.dotDiameter,
      DockGeometry.barHeight,
    );
    final barRight = right - DockGeometry.dotDiameter - DockGeometry.dotGap;
    final bar = Rect.fromLTWH(
      barRight - barWidth,
      top,
      barWidth,
      DockGeometry.barHeight,
    );
    return (bar: bar, leftDot: leftDot, rightDot: rightDot);
  }

  /// 搜索态全宽胶囊的可视矩形（高 44，底边距 16）。
  Rect get searchCapsuleRect {
    final bottom = size.height - safeBottom - DockGeometry.bottomMargin;
    return Rect.fromLTRB(
      DockGeometry.sideMargin,
      bottom - DockGeometry.searchHeight,
      size.width - DockGeometry.sideMargin,
      bottom,
    );
  }

  /// 屏幕横坐标 → 页位置（双击直达用，以缩短后的导航条为行程）。
  double pageAtX(double globalX) {
    final barRect = navGeometry.bar;

    final barWidth = barRect.width;
    // 与 _thumb 的滑块宽度保持同一规则：导航条长度 / 页面数。
    final thumbWidth = barWidth / pageCount;

    final center = (globalX - barRect.left).clamp(
      thumbWidth / 2,
      barWidth - thumbWidth / 2,
    );
    return (center - thumbWidth / 2) / (barWidth - thumbWidth) * (pageCount - 1);
  }

  /// 竖单三个按钮的圆心（与 HandleMenu 内边距/间距规则一致，
  /// 供触发涟漪定位）。
  List<Offset> get pageMenuPositions {
    final width = size.width;
    final handleWidth = DockGeometry.handleWidthFor(width);
    final diameter = DockGeometry.menuButtonDiameterFor(handleWidth);
    final edge = DockGeometry.menuEdgeInsetFor(handleWidth);
    final menuHeight = DockGeometry.menuHeightFor(handleWidth);

    final bottom = size.height - safeBottom - DockGeometry.bottomMargin;
    final top = bottom - menuHeight;
    final centerX = DockGeometry.handleLeftFor(width) + handleWidth / 2;
    return [
      for (var i = 0; i < 3; i++)
        Offset(centerX, top + edge + diameter / 2 + i * (diameter + 10)),
    ];
  }

  /// 快捷弧曲线起点。
  ///
  /// 横坐标：缩短导航条左起 1/4 处——实测手势起点位于条上约
  /// 0.23 处（系统「指针位置」截图量得），这样曲线末端仍在屏内、
  /// 按钮整体以导航条中心对称。纵坐标为导航条垂直中点。
  static Offset quickArcOrigin(Size size, double safeBottom) {
    final assemblyWidth = DockGeometry.navAssemblyWidthFor(size.width);
    final assemblyLeft = size.width - DockGeometry.sideMargin - assemblyWidth;
    final barWidth = DockGeometry.navBarWidthFor(size.width);
    final barLeft =
        assemblyLeft + DockGeometry.dotDiameter + DockGeometry.dotGap;

    return Offset(
      barLeft + barWidth / 4,
      size.height -
          safeBottom -
          DockGeometry.bottomMargin -
          DockGeometry.barHeight / 2,
    );
  }
}
