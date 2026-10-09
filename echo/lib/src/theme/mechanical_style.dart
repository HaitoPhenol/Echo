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

  /// 三层纹理相对屏幕左上角的整体平移（dp，真机观感回调值）。
  /// 取细网格半个格距（16）：所有格线/点阵同步错开，边缘仍由
  /// 负向起点的循环保证铺满，不会出现半截新线。
  /// 实验值 2026-10-09，用户要求「网格整体右移、下移一点」。
  static const double gridOriginShiftX = 16;
  static const double gridOriginShiftY = 16;

  // ================================================================
  // 虚拟边界与顶部十字定位标记（稿 L28-40 的实验改版）
  // ================================================================

  /// 虚拟边界距屏幕左右两侧的内缩（dp）= 14，与 DockGeometry
  /// 的三条留白同值——顶部十字与导航几何共用一套留白体系。
  /// 实验改版（2026-10-09）：取消实体描边框与底部十字，
  /// 只保留顶部两个十字标定「状态栏下沿、左右各 14」的位置。
  static const double frameInset = 14;

  /// 十字边长（dp，稿 22px，由一条竖线与一条横线交叉）。
  /// 十字中心压在虚拟边界的两个顶角上，各向内外延伸半个边长。
  static const double crossSize = 22;

  /// 十字线宽（dp）
  static const double crossStrokeWidth = 1;

  // 十字色直接复用 [coarseGridColor]（白 α.10）：α.50 过于显眼，
  // 2026-10-09 用户裁决降到与粗网格同亮度，融入背景。

  // ================================================================
  // 顶部坐标读数条（稿 L42-45）
  // ================================================================

  /// 读数条距顶部距离（dp，贴死状态栏下沿 0；真机还需叠加状态栏高度）。
  /// 读数条居中、顶部十字在左右边缘，水平不相交，故可贴近。
  static const double coordsTop = 0;

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

  /// 大页码顶距比例（稿 top:5vh，相对屏高）
  static const double pageNumberTopFactor = 0.05;

  /// 大页码右边距比例。稿为 8vw，真机按用户意见往中间收一点（0.14）。
  static const double pageNumberRightFactor = 0.14;

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

  // ================================================================
  // 右下角 3D 页码转鼓指示器（稿 L318-345「滚筒模块」）
  // ================================================================

  /// 转鼓面板底色（稿 --panel:#0f0f0f）
  static const Color drumPanelColor = Color(0xFF0F0F0F);

  /// 面板方边框色（稿 1px solid --line:#262626）
  static const Color drumBorderColor = Color(0xFF262626);

  /// 面板内边距（dp，稿 padding:10px 14px 12px）
  static const double drumPadTop = 10;
  static const double drumPadH = 14;
  static const double drumPadBottom = 12;

  /// 左上/右下直角亮线边长与线宽（稿 16px、2px）
  static const double drumCornerSize = 16;
  static const double drumCornerStrokeWidth = 2;

  /// 直角亮线/刻度激活/进度条/blip 高亮色（稿 --hi:#d8d8d8）
  static const Color drumHiColor = Color(0xFFD8D8D8);

  /// blip 闪烁方块边长（稿 6px）
  static const double drumBlipSize = 6;

  /// blip 闪烁周期（稿 animation:blip 1.2s steps(2)）
  static const Duration drumBlipPeriod = Duration(milliseconds: 1200);

  /// 顶行标签字号/字距/颜色（稿 .tag 10px .3em，--dim:#646464）
  static const double drumTagFontSize = 10;
  static const double drumTagLetterSpacing = 3;
  static const Color drumTagColor = Color(0xFF646464);

  /// 右上编号字号/字距/颜色（稿 .unit 9px .15em，#3d3d3d）
  static const double drumUnitFontSize = 9;
  static const double drumUnitLetterSpacing = 1.35;
  static const Color drumUnitColor = Color(0xFF3D3D3D);

  /// 顶行与转鼓主体的间距（稿 margin-bottom:8px）
  static const double drumHeadGap = 8;

  /// 3D 视窗宽高（稿 #view 148×96）与透视距离（perspective:520px）
  static const double drumViewWidth = 148;
  static const double drumViewHeight = 96;
  static const double drumPerspective = 520;

  /// 圆柱半径（稿 R=190，与视窗宽度配合保证相邻面夹角处不穿帮）
  static const double drumRadius = 190;

  /// 视窗左右虚线竖边色（稿 1px dashed --line）
  static const Color drumViewEdgeColor = Color(0xFF262626);

  /// 转鼓大数字字号/字距/颜色（稿 56px w700 .04em，--ink:#e1e1e1）
  static const double drumNumberFontSize = 56;
  static const double drumNumberLetterSpacing = 2.24;
  static const Color drumNumberColor = Color(0xFFE1E1E1);

  /// 视窗与右侧刻度列的间距（稿 gap:16px）
  static const double drumTicksGap = 16;

  /// 单个刻度杠宽高（稿 14×4）与杠间距（稿 gap:7）
  static const double drumTickWidth = 14;
  static const double drumTickHeight = 4;
  static const double drumTickGap = 7;

  /// 刻度未激活色（稿 #272727）
  static const Color drumTickOffColor = Color(0xFF272727);

  /// 刻度亮暗过渡时长（稿 transition:background .25s）
  static const Duration drumTickDuration = Duration(milliseconds: 250);

  /// 底部进度条高度（稿 2px）与底色（稿 rgba(255,255,255,.05)）
  static const double drumProgressHeight = 2;
  static const Color drumProgressTrackColor = Color(0x0DFFFFFF);
}
