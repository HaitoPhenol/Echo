import 'package:flutter/material.dart';

/// 机能风页面背景实验样式常量（实验分支 feat/page-background-art 专用）。
///
/// 所有数值 1:1 移植自设计工程稿
/// `ideas/mechanical_style_page.html`（标题「滚筒页码 · 机能风」），
/// 注释中的「稿 Lxx」指该文件行号，便于回查原型出处。
///
/// 两点约定：
/// 1. 原型 CSS px 按手机浏览器视口近似等同于 Flutter 逻辑像素（dp），
///    先按 1:1 移植，**这些都是初始实验值**，装机后以真机观感回调；
/// 2. 本文件是实验隔离层：在方案验收通过前**不并入
///    [AppColors]**（色板变更属美术 token，须走 RCR）。
///    方案被推翻时本文件与相关实验组件整块删除。
abstract final class MechanicalStyle {
  MechanicalStyle._();

  // ================================================================
  // 底色（稿 L8：--bg:#0c0c0c）
  // ================================================================

  /// 机能风实验底色。仅作背景纹理的绘制底色参考，
  /// A2 落地前不替换 [AppColors.background]（0xFF0B0E12）。
  static const Color baseBackground = Color(0xFF0C0C0C);

  // ================================================================
  // 背景纹理三层（稿 L17-24：点阵 + 细网格 + 粗网格叠加）
  // ================================================================

  /// 细网格间距（dp，稿 background-size:32px）
  static const double fineGridSpacing = 32;

  /// 细网格线宽（dp，稿为 1px CSS）
  static const double fineGridStrokeWidth = 1;

  /// 细网格线色（稿 rgba(255,255,255,.05)）
  static const Color fineGridColor = Color(0x0DFFFFFF);

  /// 粗网格间距（dp，稿 background-size:128px）
  static const double coarseGridSpacing = 128;

  /// 粗网格线宽（dp）
  static const double coarseGridStrokeWidth = 1;

  /// 粗网格线色（稿 rgba(255,255,255,.10)）
  static const Color coarseGridColor = Color(0x1AFFFFFF);

  /// 点阵间距（dp，稿 background-size:128px）
  static const double dotGridSpacing = 128;

  /// 点阵圆点半径（dp，稿 radial-gradient 实色到 1px 即直径 2px）
  static const double dotRadius = 1;

  /// 点阵圆点色（稿 rgba(255,255,255,.22)）
  static const Color dotColor = Color(0x38FFFFFF);

  // ================================================================
  // 虚拟边界与四角十字定位标记（稿 L28-40 的实验改版）
  // ================================================================

  /// 虚拟边界距屏幕左右两侧的内缩（dp）= 14，与 DockGeometry
  /// 的三条留白同值——十字与底部导航几何共用一套留白体系。
  /// 实验改版（2026-10-09）：取消实体描边框，改由四角十字标定
  /// 「状态栏下沿 ↔ 导航栏上沿、左右各 14」的虚拟边界。
  static const double frameInset = 14;

  /// 十字边长（dp，稿 22px，由一条竖线与一条横线交叉）。
  /// 十字中心压在虚拟边界的四个角点上，各向内外延伸半个边长。
  static const double crossSize = 22;

  /// 十字线宽（dp）
  static const double crossStrokeWidth = 1;

  /// 十字色（稿 opacity:.5）
  static const Color crossColor = Color(0x80FFFFFF);

  // ================================================================
  // 顶部坐标读数条（稿 L42-45）
  // ================================================================

  /// 读数条距顶部距离（dp，稿 top:20px；真机还需叠加状态栏高度）
  static const double coordsTop = 20;

  /// 读数条字号（稿 9px）
  static const double coordsFontSize = 9;

  /// 读数条字距（dp，稿 letter-spacing:.4em = 9 × .4）
  static const double coordsLetterSpacing = 3.6;

  /// 读数条普通文字色（稿 rgba(255,255,255,.30)）
  static const Color coordsDimColor = Color(0x4DFFFFFF);

  /// 读数条强调文字色（稿 i 标签 rgba(255,255,255,.55)）
  static const Color coordsHiColor = Color(0x8CFFFFFF);

  // ================================================================
  // 每页空心大页码（稿 L57-58）
  // ================================================================

  /// 大页码字号（稿 120px）
  static const double pageNumberFontSize = 120;

  /// 大页码描边线宽（dp，稿 -webkit-text-stroke:1px）
  static const double pageNumberStrokeWidth = 1;

  /// 大页码描边色（稿 rgba(255,255,255,.10)，填充透明）
  static const Color pageNumberStrokeColor = Color(0x1AFFFFFF);

  // ================================================================
  // 分区小标题 kicker（稿 L49-50：SEC.01 // CONSOLE）
  // ================================================================

  /// kicker 字号（稿 11px）
  static const double kickerFontSize = 11;

  /// kicker 字距（dp，稿 letter-spacing:.35em = 11 × .35）
  static const double kickerLetterSpacing = 3.85;

  /// kicker 主文字色（稿 --hi:#d8d8d8）
  static const Color kickerHiColor = Color(0xFFD8D8D8);

  /// kicker 次要文字色（稿 --dim:#646464，用于 // 与英文标注）
  static const Color kickerDimColor = Color(0xFF646464);
}
