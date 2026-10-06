import 'package:flutter/material.dart';

/// 应用调色板。
///
/// 颜色取值移植自原型 ideas/smart_line.html，集中管理，
/// 便于后续统一调整设计风格。
abstract final class AppColors {
  /// 页面底色（近黑的冷灰）
  static const Color background = Color(0xFF0B0E12);

  /// 主文字色
  static const Color textPrimary = Color(0xFFE8ECF0);

  /// 次级文字 / 未选中图标色
  static const Color textMuted = Color(0xFF57616B);

  /// 页名标签色
  static const Color pageLabel = Color(0xFF9AA3AD);

  /// 滚筒底色（深色 88% 不透明）
  static const Color rollerBackground = Color(0xE00F141A);

  /// 搜索态胶囊底色（深色 90% 不透明）
  static const Color searchBackground = Color(0xE60F141A);

  /// 搜索强调色（光标、输入态图标、倒计时边框）
  static const Color accentBlue = Color(0xFF7AA2FF);

  /// 反色（白底下的深色文字/图标）
  static const Color inverse = Color(0xFF0D1116);

  /// 导航锚点：通知呼吸绿
  static const Color anchorGreen = Color(0xFF30D158);

  /// 导航锚点：异常闪烁红
  static const Color anchorRed = Color(0xFFFF453A);
}
