import 'dart:math';

import 'package:echo/src/diary/sy/sy_id.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('SyIdGenerator.next', () {
    test('生成 1000 个 ID 全部符合 22 位规范且唯一', () {
      final gen = SyIdGenerator(random: Random(42));
      final ids = {for (var i = 0; i < 1000; i++) gen.next()};
      expect(ids.length, 1000);
      expect(ids.every(SyIdGenerator.isValid), isTrue);
    });

    test('时间戳段使用当前时刻（秒级）', () {
      final fixed = DateTime(2026, 1, 7, 8, 0, 0);
      final gen = SyIdGenerator(random: Random(1), now: () => fixed);
      expect(gen.next(), startsWith('20260107080000-'));
    });
  });

  group('容器确定性 ID', () {
    test('年容器：{yyyy}0101000000-echo000', () {
      expect(SyIdGenerator.yearContainer(2026), '20260101000000-echo000');
      expect(SyIdGenerator.isValid('20260101000000-echo000'), isTrue);
    });

    test('月容器：{yyyyMM}01000000-echo000', () {
      expect(
        SyIdGenerator.monthContainer(DateTime(2026, 10)),
        '20261001000000-echo000',
      );
    });

    test('日容器：{yyyyMMdd}080000-echo000', () {
      expect(
        SyIdGenerator.dayContainer(DateTime(2026, 10, 10)),
        '20261010080000-echo000',
      );
    });

    test('容器 ID 重复计算幂等', () {
      final d = DateTime(2026, 10, 10);
      expect(SyIdGenerator.dayContainer(d), SyIdGenerator.dayContainer(d));
    });
  });

  group('data 快照块确定性 ID（M4）', () {
    test('{yyyyMMdd}080100-dataNNN 合 22 位规范且可识别', () {
      final id = SyIdGenerator.dataBlock(DateTime(2026, 10, 10), 1);
      expect(id, '20261010080100-data001');
      expect(SyIdGenerator.isValid(id), isTrue);
      expect(SyIdGenerator.isDataBlockId(id), isTrue);
    });

    test('角色序号递增到 3 位', () {
      expect(
        SyIdGenerator.dataBlock(DateTime(2026, 10, 10), 12),
        '20261010080100-data012',
      );
    });

    test('普通块/容器 ID 不被识别为 data 块', () {
      expect(
        SyIdGenerator.isDataBlockId('20261010080000-echo000'),
        isFalse,
      );
      final gen = SyIdGenerator(random: Random(1));
      expect(SyIdGenerator.isDataBlockId(gen.next()), isFalse);
    });
  });

  group('isValid 反例', () {
    for (final bad in [
      '',
      '20261010080000-echo00', // 随机段 6 位
      '2026101008000-ECHO000', // 13 位 + 大写
      '20261010080000_echo000', // 下划线
      '2026-101-008000-echo000', // 含连字符
    ]) {
      test('"$bad" 不合法', () {
        // 注意：isValid 只校格式，不校日期合法性。
        expect(SyIdGenerator.isValid(bad), isFalse);
      });
    }
  });
}
