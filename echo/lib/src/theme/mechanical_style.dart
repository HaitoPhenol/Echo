import 'package:flutter/material.dart';

/// 机能风视觉层的**非颜色**样式常量（几何 / 排印 / 时长）。
///
/// 所有数值 1:1 移植自设计工程稿
/// `ideas/mechanical_style_page.html`（标题「滚筒页码 · 机能风」），
/// 注释中的「稿 Lxx」指该文件行号，便于回查原型出处；
/// 部分数值经 MIX 2S 真机观感回调（注释标注日期与裁决）。
///
/// 颜色 token 不在本类：机能风全部色值已收编进
/// [AppColors] 的「机能风视觉层」色组（RCR-2026-001）。
/// 原型 CSS px 按手机浏览器视口近似等同于 Flutter 逻辑像素（dp）。
abstract final class MechanicalStyle {
  MechanicalStyle._();

  // ================================================================
  // 背景纹理三层（稿 L17-24：点阵 + 细网格 + 粗网格叠加）
  // ================================================================

  /// 细网格间距（dp，稿 background-size:32px）
  static const double fineGridSpacing = 32;

  /// 细网格线宽（dp，稿为 1px CSS）
  static const double fineGridStrokeWidth = 1;

  /// 粗网格间距（dp，稿 background-size:128px）
  static const double coarseGridSpacing = 128;

  /// 粗网格线宽（dp）
  static const double coarseGridStrokeWidth = 1;

  /// 点阵间距（dp，稿 background-size:128px）
  static const double dotGridSpacing = 128;

  /// 点阵圆点半径（dp，稿 radial-gradient 实色到 1px 即直径 2px）
  static const double dotRadius = 1;

  /// 三层纹理相对屏幕左上角的整体平移（dp，真机观感回调值）。
  /// 取细网格半个格距（16）：所有格线/点阵同步错开，边缘仍由
  /// 负向起点的循环保证铺满，不会出现半截新线。
  /// 2026-10-09 用户裁决「网格整体右移、下移一点」。
  static const double gridOriginShiftX = 16;
  static const double gridOriginShiftY = 16;

  // ================================================================
  // 虚拟边界与顶部十字定位标记（稿 L28-40 的改版）
  // ================================================================

  /// 虚拟边界距屏幕左右两侧的内缩（dp）= 14，与 DockGeometry
  /// 的三条留白同值——顶部十字与导航几何共用一套留白体系。
  /// 改版（2026-10-09）：取消实体描边框与底部十字，
  /// 只保留顶部两个十字标定「状态栏下沿、左右各 14」的位置。
  static const double frameInset = 14;

  /// 十字边长（dp，稿 22px，由一条竖线与一条横线交叉）。
  /// 十字中心压在虚拟边界的两个顶角上，各向内外延伸半个边长。
  static const double crossSize = 22;

  /// 十字线宽（dp）
  static const double crossStrokeWidth = 1;

  // 十字色用 AppColors.mechCoarseGrid（白 α.10）：α.50 过于显眼，
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

  // ================================================================
  // 每页空心大页码（稿 L57-58）
  // ================================================================

  /// 大页码字号（稿 120px）
  static const double pageNumberFontSize = 120;

  /// 大页码描边线宽（dp，稿 -webkit-text-stroke:1px）
  static const double pageNumberStrokeWidth = 1;

  /// 大页码顶距比例（稿 top:5vh，相对屏高）
  static const double pageNumberTopFactor = 0.05;

  /// 大页码右边距比例。稿为 8vw，真机按用户意见往中间收一点（0.14）；
  /// 另在 page_number 内减 32dp 常数做二次内收。
  static const double pageNumberRightFactor = 0.14;

  // ================================================================
  // 分区小标题 kicker（稿 L49-50：SEC.01 // CONSOLE）
  // ================================================================

  /// kicker 字号（稿 11px）
  static const double kickerFontSize = 11;

  /// kicker 字距（dp，稿 letter-spacing:.35em = 11 × .35）
  static const double kickerLetterSpacing = 3.85;

  // ================================================================
  // 模板页大标题排印（C2 试验采纳，稿 L51：h2 700 / letter-spacing .12em）
  // ================================================================

  /// 大标题字号（现状 48，落在稿 clamp(40px,7vw,80px) 区间内）
  static const double pageTitleFontSize = 48;

  /// 大标题字重：稿 h2 为 700（原细体 w200，C2 改粗对标稿）
  static const FontWeight pageTitleFontWeight = FontWeight.w700;

  /// 大标题字距（稿 .12em = 48 × .12）
  static const double pageTitleLetterSpacing = 5.76;

  // ================================================================
  // 右下角 3D 页码转鼓指示器（稿 L318-345「滚筒模块」）
  // ================================================================

  /// 面板内边距（dp，稿 padding:10px 14px 12px）
  static const double drumPadTop = 10;
  static const double drumPadH = 14;
  static const double drumPadBottom = 12;

  /// 左上/右下直角亮线边长与线宽（稿 16px、2px）
  static const double drumCornerSize = 16;
  static const double drumCornerStrokeWidth = 2;

  /// blip 闪烁方块边长（稿 6px）
  static const double drumBlipSize = 6;

  /// blip 闪烁周期（稿 animation:blip 1.2s steps(2)）
  static const Duration drumBlipPeriod = Duration(milliseconds: 1200);

  /// 顶行标签字号/字距（稿 .tag 10px .3em）
  static const double drumTagFontSize = 10;
  static const double drumTagLetterSpacing = 3;

  /// 顶行与转鼓主体的间距（稿 margin-bottom:8px）
  static const double drumHeadGap = 8;

  /// 3D 视窗宽高（稿 #view 148×96）与透视距离（perspective:520px）
  static const double drumViewWidth = 148;
  static const double drumViewHeight = 96;
  static const double drumPerspective = 520;

  /// 圆柱半径（稿 R=190，与视窗宽度配合保证相邻面夹角处不穿帮）
  static const double drumRadius = 190;

  /// 转鼓大数字字号/字距（稿 56px w700 .04em）
  static const double drumNumberFontSize = 56;
  static const double drumNumberLetterSpacing = 2.24;

  /// 底部进度条高度（稿 2px）
  static const double drumProgressHeight = 2;

  /// 转鼓与页名牌共用的显隐节奏（稿 .25s/.3s；Flutter 端真机验收值）
  static const Duration indicatorFadeDuration = Duration(milliseconds: 220);
  static const Duration indicatorRiseDuration = Duration(milliseconds: 340);

  /// 退场「百叶窗故障」竖条数（两个指示器共用）。
  static const int indicatorExitBandCount = 10;

  /// 退场前段整构件数码横抖最大幅度（px，快速衰减）。
  static const double indicatorExitJitter = 3;

  // ================================================================
  // 左下角页名牌（稿 L305-317「#pgname」，与转鼓同时显隐）
  // ================================================================

  // 页名牌不设独立左右边距常量：左边距与右下转鼓右边距同源，
  // 都取 DockGeometry.sideMargin（14dp），定位在 smart_nav_screen。

  /// 色块内边距（稿 padding:12px 26px 14px）
  static const double namePlatePadTop = 12;
  static const double namePlatePadH = 26;
  static const double namePlatePadBottom = 14;

  /// 页名字号/字距（稿 clamp(64,9vw,120) w700 .08em，手机端取 64）
  static const double namePlateFontSize = 64;
  static const double namePlateLetterSpacing = 5.12;

  /// 名字下方短横线：宽/高/与文字间距（稿 56px、3px、margin-top:18px）
  static const double namePlateUnderlineWidth = 56;
  static const double namePlateUnderlineHeight = 3;
  static const double namePlateUnderlineGap = 18;

  // ---- 赛博故障（glitch）：稿外新增，真机验收值 ----

  /// 赛博故障单段总时长：唤醒时播一次，唤醒期间每成功翻页
  /// （activePage 硬切）重播一次；边界回弹不播。
  static const Duration nameGlitchDuration =
      Duration(milliseconds: 620);

  /// 整字数码抖动最大位移（px，幅度按序列递减到 0）。
  static const double nameGlitchShakeMax = 6;

  /// 文字水平切片撕裂错位最大位移（px）。
  static const double nameGlitchSliceShift = 9;

  /// 灰色重影副本横向偏移（px；副本取 mechInkDim）。
  static const double nameGlitchChromaShift = 4;
}
