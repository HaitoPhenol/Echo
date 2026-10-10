import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:echo/src/diary/editor/block_commands.dart';

void main() {
  group('BlockBackgroundPalette（思源 midnight 3.8.6 取色）', () {
    test('合法区间 1..13', () {
      expect(BlockBackgroundPalette.isValid(1), isTrue);
      expect(BlockBackgroundPalette.isValid(13), isTrue);
      expect(BlockBackgroundPalette.isValid(0), isFalse);
      expect(BlockBackgroundPalette.isValid(14), isFalse);
    });

    test('13 档色值与 midnight/theme.css 实取一致（锁死防误改）', () {
      const expected = <int, Color>{
        1: Color(0xFF442724),
        2: Color(0xFF554636),
        3: Color(0xFF28405C),
        4: Color(0xFF425347),
        5: Color(0xFF3A3F42),
        6: Color(0xFF031840),
        7: Color(0xFF593905),
        8: Color(0xFF3A0C09),
        9: Color(0xFF4D1B40),
        10: Color(0xFF1A5459),
        11: Color(0xFF305415),
        12: Color(0xFF4A4712),
        13: Color(0xFFDADADA),
      };
      expect(BlockBackgroundPalette.colors, expected);
    });

    test('fillOf 不透明实色，null 无色', () {
      expect(BlockBackgroundPalette.fillOf(null), isNull);
      final c = BlockBackgroundPalette.fillOf(3)!;
      expect(c, const Color(0xFF28405C));
      expect(c.a, 1.0);
    });

    test('仅 13 号近白需要深色正文', () {
      for (var n = 1; n <= 12; n++) {
        expect(BlockBackgroundPalette.needsDarkInk(n), isFalse,
            reason: '$n 号为暗色底');
      }
      expect(BlockBackgroundPalette.needsDarkInk(13), isTrue);
      expect(BlockBackgroundPalette.needsDarkInk(null), isFalse);
    });
  });
}
