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
}
