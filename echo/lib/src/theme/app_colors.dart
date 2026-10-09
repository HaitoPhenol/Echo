import 'package:flutter/material.dart';

/// 应用调色板。
///
/// 颜色取值移植自原型 ideas/smart_line.html，集中管理，
/// 便于后续统一调整设计风格。
///
/// 核心设计语言是 [tone1]～[tone4] 的**中性亮度四阶阶梯**
/// （深色底上的白色层级）：导航线各元素按亮度对号入座，
/// 新增元素时就近取阶，不再自造白透明度。
abstract final class AppColors {
  // ================================================================
  // 深色表面层（与亮度阶梯并列：一切有色元素都画在这些表面上）
  // ================================================================

  /// 页面底色（近黑的冷灰）
  static const Color background = Color(0xFF0B0E12);

  /// 滚筒底色（深色 88% 不透明）
  static const Color rollerBackground = Color(0xE00F141A);

  /// 搜索态胶囊底色（深色 90% 不透明）
  static const Color searchBackground = Color(0xE60F141A);

  /// 全屏浮层表面色（深色 92% 不透明）：把手竖单、AI 对话框
  static const Color overlaySurface = Color(0xEB0F141A);

  /// 侧边抽屉底色（深色 96% 不透明，另叠 18px 毛玻璃）
  static const Color drawerSurface = Color(0xF511161D);

  // ================================================================
  // 中性亮度四阶阶梯（1 最暗 → 4 最亮）
  // ================================================================

  /// 阶 1 · 导航条（轨道本体）
  static const Color tone1 = Color(0x29FFFFFF); // α 0.16

  /// 阶 2 · 拇指滑块
  static const Color tone2 = Color(0x6BFFFFFF); // α 0.42

  /// 阶 3 · 导航锚点
  static const Color tone3 = Color(0xB8FFFFFF); // α 0.72

  /// 阶 4 · 快捷弧选中操作项（纯白）
  static const Color tone4 = Color(0xFFFFFFFF); // α 1.00

  // ================================================================
  // 文字 / 图标语义色（就近对齐亮度阶梯）
  // ================================================================

  /// 主文字色（= 阶 4）
  static const Color textPrimary = tone4;

  /// 次级文字 / 未选中图标色（= 阶 2）
  static const Color textMuted = tone2;

  /// 页名标签 / 搜索结果图标色（= 阶 3）
  static const Color pageLabel = tone3;

  /// 反色（白底下的深色文字/图标，如滑块按下态、选中按钮上的图标）
  static const Color inverse = Color(0xFF0D1116);

  // ================================================================
  // 功能强调色（不参与亮度阶梯：仅用于状态语义）
  // ================================================================

  /// 搜索强调色（光标、输入态图标、倒计时边框）
  static const Color accentBlue = Color(0xFF7AA2FF);

  /// 导航锚点：通知呼吸绿
  static const Color anchorGreen = Color(0xFF30D158);

  /// 导航锚点：异常闪烁红
  static const Color anchorRed = Color(0xFFFF453A);

  // ================================================================
  // 机能风视觉层（RCR-2026-001 收编）
  //
  // 工程稿 ideas/mechanical_style_page.html 的皮肤 token：固定背景
  // 纹理、顶部读数条、空心大页码 / kicker、3D 页码转鼓。
  // 与上方亮度四阶阶梯**并列、互不混用**（网格纹理需要独立的低 α
  // 白系列，不就近归并 tone 阶）；几何 / 排印 / 时长数值不属于颜色，
  // 仍在 `theme/mechanical_style.dart` 的 MechanicalStyle。
  // ================================================================

  /// 机能风固定背景底色（近黑中性灰）。主屏全程被背景层覆盖，
  /// 冷灰 [background]（Scaffold 底色）不外露。
  static const Color mechBackground = Color(0xFF0C0C0C);

  /// 背景细网格线（白 α.05，32dp 格距）
  static const Color mechFineGrid = Color(0x0DFFFFFF);

  /// 背景粗网格线与顶部十字标定（白 α.10，128dp 格距）
  static const Color mechCoarseGrid = Color(0x1AFFFFFF);

  /// 背景点阵圆点（白 α.22，128dp 间距）
  static const Color mechGridDot = Color(0x38FFFFFF);

  /// 顶部读数条普通文字（白 α.30）
  static const Color mechCoordsDim = Color(0x4DFFFFFF);

  /// 顶部读数条强调文字（白 α.55）
  static const Color mechCoordsHi = Color(0x8CFFFFFF);

  /// 空心大页码描边（白 α.10，填充透明）
  static const Color mechPageNumberStroke = Color(0x1AFFFFFF);

  /// 机能风主墨色（稿 --hi:#d8d8d8）：kicker 主文字、转鼓直角亮线 /
  /// 进度条 / blip 高亮、页名牌文字与下划短线共用。
  static const Color mechInk = Color(0xFFD8D8D8);

  /// 机能风次墨色（稿 --dim:#646464）：kicker 的 // 与英文标注、
  /// 转鼓顶行标签共用。
  static const Color mechInkDim = Color(0xFF646464);

  /// 转鼓面板与页名牌底色（稿 --panel:#0f0f0f；页名牌用时取 α.90）
  static const Color mechDrumPanel = Color(0xFF0F0F0F);

  /// 转鼓方边框与视窗左右虚线竖边（稿 --line:#262626）
  static const Color mechDrumLine = Color(0xFF262626);

  /// 转鼓大数字墨色（稿 --ink:#e1e1e1）
  static const Color mechDrumNumber = Color(0xFFE1E1E1);

  /// 转鼓底部进度条轨道色（白 α.05）
  static const Color mechDrumProgressTrack = Color(0x0DFFFFFF);
}
