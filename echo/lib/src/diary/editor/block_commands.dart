import 'package:flutter/material.dart';

/// 块级结构操作（M3 调色板 / 转标题菜单 / Slash 命令面板统一绑定这些
/// 动作；M2 只在控制器层实现并测试，UI 暂不挂载）。
enum BlockAction {
  turnParagraph,
  turnHeading1,
  turnHeading2,
  turnHeading3,
  clearBackground,
}

/// 思源 13 档块底色在**编辑期**的临时显色。
///
/// 数据层永远只存色号（导出写 `var(--b3-font-backgroundN)` canonical
/// 串，见金标准 §5.3），所以编辑期配色可随时替换、零数据迁移。
///
/// TODO(M3)：以下 RGB 为深色编辑界面下的低饱和占位值，M3 调色板
/// 落地时必须替换为从思源 3.8.6 主题 CSS 提取的实际取值。
abstract final class BlockBackgroundPalette {
  BlockBackgroundPalette._();

  /// 合法色号区间（1..13，null = 无色）。
  static const int min = 1;
  static const int max = 13;

  static bool isValid(int number) => number >= min && number <= max;

  /// 色号 → 编辑期颜色（暗色底上做了压暗处理，保证正文白字可读）。
  static const Map<int, Color> colors = {
    1: Color(0xFF4A4A4A),
    2: Color(0xFF6B5D44),
    3: Color(0xFF7A5A3A),
    4: Color(0xFF7A4A3D),
    5: Color(0xFF7A3D3D),
    6: Color(0xFF7A3D5C),
    7: Color(0xFF5C3D7A),
    8: Color(0xFF3D4A7A),
    9: Color(0xFF2F5E7A),
    10: Color(0xFF2F7A6B),
    11: Color(0xFF3D7A3D),
    12: Color(0xFF6E7A2F),
    13: Color(0xFF7A7A2F),
  };

  /// 块底色填充（加透明度与底色混合，避免压住网格与正文）。
  static Color? fillOf(int? number) =>
      number == null ? null : colors[number]?.withValues(alpha: 0.32);
}
