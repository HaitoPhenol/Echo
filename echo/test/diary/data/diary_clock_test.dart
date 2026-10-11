import 'package:echo/src/diary/data/diary_clock.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('DiaryClock.diaryDate 04:00 日界', () {
    test('03:59:59 归属前一天', () {
      expect(
        DiaryClock.diaryDate(DateTime(2026, 10, 10, 3, 59, 59)),
        DateTime(2026, 10, 9),
      );
    });

    test('04:00:00 归属当天', () {
      expect(
        DiaryClock.diaryDate(DateTime(2026, 10, 10, 4, 0, 0)),
        DateTime(2026, 10, 10),
      );
    });

    test('午夜 00:00 归属前一天（熬夜场景）', () {
      expect(
        DiaryClock.diaryDate(DateTime(2026, 10, 10, 0, 0, 0)),
        DateTime(2026, 10, 9),
      );
    });

    test('23:59 归属当天', () {
      expect(
        DiaryClock.diaryDate(DateTime(2026, 10, 10, 23, 59, 59)),
        DateTime(2026, 10, 10),
      );
    });

    test('凌晨跨界正确回退到上月、上年', () {
      expect(
        DiaryClock.diaryDate(DateTime(2026, 10, 1, 2, 30)),
        DateTime(2026, 9, 30),
      );
      expect(
        DiaryClock.diaryDate(DateTime(2026, 1, 1, 1, 0)),
        DateTime(2025, 12, 31),
      );
    });

    test('today() 取可注入的墙上时间', () {
      final clock = DiaryClock(now: () => DateTime(2026, 3, 8, 3, 30));
      expect(clock.today(), DateTime(2026, 3, 7));
      final clock2 = DiaryClock(now: () => DateTime(2026, 3, 8, 4, 1));
      expect(clock2.today(), DateTime(2026, 3, 8));
    });
  });

  group('DiaryClock 拨钟（ECP sys.clock.set 同路基础）', () {
    test('overrideTo 固定 now/today，clearOverride 恢复墙钟', () {
      var wall = DateTime(2026, 10, 11, 10);
      final clock = DiaryClock(now: () => wall);
      expect(clock.isOverridden, isFalse);

      clock.overrideTo(DateTime(2026, 10, 12, 3, 59));
      expect(clock.isOverridden, isTrue);
      expect(clock.now(), DateTime(2026, 10, 12, 3, 59));
      // 拨钟期间墙钟走动不影响读数。
      wall = DateTime(2026, 10, 11, 22);
      expect(clock.today(), DateTime(2026, 10, 11)); // 03:59 归前一天

      clock.clearOverride();
      expect(clock.isOverridden, isFalse);
      expect(clock.now(), wall);
      expect(clock.today(), DateTime(2026, 10, 11));
    });
  });
}
