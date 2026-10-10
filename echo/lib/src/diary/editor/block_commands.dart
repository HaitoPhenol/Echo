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

/// 思源 13 档块底色在**编辑期**的显色（暗色主题取色）。
///
/// 数据层永远只存色号（导出写 `var(--b3-font-backgroundN)` canonical
/// 串，见金标准 §5.3），所以编辑期配色可随时替换、零数据迁移。
///
/// 色值来源：思源 v3.8.6 官方暗色主题 `midnight/theme.css`
/// （--b3-font-background1..13；1..4 分别别名 card-error/warning/
/// info/success，13 别名 --b3-theme-on-background）。编辑期所见即
/// 思源暗色模式导入后所得。App 深色专用，不跟随浅色 daylight 主题。
abstract final class BlockBackgroundPalette {
  BlockBackgroundPalette._();

  /// 合法色号区间（1..13，null = 无色）。
  static const int min = 1;
  static const int max = 13;

  static bool isValid(int number) => number >= min && number <= max;

  /// 色号 → midnight 暗色主题下的实际填充色（不透明，与思源一致）。
  static const Map<int, Color> colors = {
    1: Color(0xFF442724), // --b3-card-error-background
    2: Color(0xFF554636), // --b3-card-warning-background
    3: Color(0xFF28405C), // --b3-card-info-background
    4: Color(0xFF425347), // --b3-card-success-background
    5: Color(0xFF3A3F42),
    6: Color(0xFF031840),
    7: Color(0xFF593905),
    8: Color(0xFF3A0C09),
    9: Color(0xFF4D1B40),
    10: Color(0xFF1A5459),
    11: Color(0xFF305415),
    12: Color(0xFF4A4712),
    13: Color(0xFFDADADA), // --b3-theme-on-background（近白，需深字）
  };

  /// 块底色填充。
  static Color? fillOf(int? number) =>
      number == null ? null : colors[number];

  /// 该填充色上是否应改用深色正文（仅 13 号近白；其余暗色用白字）。
  static bool needsDarkInk(int? number) {
    final color = colors[number];
    return color != null && color.computeLuminance() > 0.4;
  }
}
