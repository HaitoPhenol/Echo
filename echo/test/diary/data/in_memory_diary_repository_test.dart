import 'package:flutter_test/flutter_test.dart';

import 'package:echo/src/diary/data/diary_repository.dart';
import 'package:echo/src/diary/data/in_memory_diary_repository.dart';
import 'package:echo/src/diary/sy/diary_model.dart';
import 'package:echo/src/diary/sy/sy_id.dart';

void main() {
  final fixedNow = DateTime(2026, 12, 15, 9, 30);

  DiaryDocument doc(DateTime date, List<String> paragraphs) =>
      DiaryDocument(
        id: SyIdGenerator.dayContainer(date),
        date: date,
        title: '${date.month}月${date.day}日',
        blocks: [
          for (final t in paragraphs) DiaryBlock(id: '20260101000000-aaaaaaa', text: t),
        ],
      );
  // 注意：测试里每篇文档块 ID 相同没有关系（仓储不校验块 ID 冲突），
  // 仅当同一文档内需要多块时才单独构造。

  group('InMemoryDiaryRepository 空仓可达性', () {
    test('today 归一到自然日（时分秒抹零，时钟可注入）', () {
      final repo = InMemoryDiaryRepository(
        now: () => DateTime(2026, 12, 15, 23, 59, 59),
        seedDebugData: false,
      );
      expect(repo.today(), DateTime(2026, 12, 15));
    });

    test('空仓仍暴露当前年/月，日列表为空，findDay 返回 null', () async {
      final repo = InMemoryDiaryRepository(
        now: () => fixedNow,
        seedDebugData: false,
      );

      expect(await repo.availableYears(), [2026]);
      expect(await repo.monthsOfYear(2026), [12]);
      expect(await repo.monthsOfYear(2025), isEmpty);
      expect(await repo.daysOfMonth(2026, 12), isEmpty);
      expect(await repo.findDay(fixedNow), isNull);
    });
  });

  group('InMemoryDiaryRepository 草稿读写', () {
    test('upsert 后 findDay/daysOfMonth 可见，并按自然日归一', () async {
      final repo = InMemoryDiaryRepository(
        now: () => fixedNow,
        seedDebugData: false,
      );
      final day = DateTime(2026, 3, 9);
      await repo.upsertDraft(doc(day, ['第一段', '第二段']));

      // 带时分秒的查询仍命中同一自然日。
      final found = await repo.findDay(DateTime(2026, 3, 9, 21, 44));
      expect(found, isNotNull);
      expect(found!.blocks.length, 2);

      final summaries = await repo.daysOfMonth(2026, 3);
      expect(summaries, hasLength(1));
      expect(summaries.single.date, DateTime(2026, 3, 9));
      expect(summaries.single.preview, '第一段');
      expect(summaries.single.blockCount, 2);
      expect(summaries.single.state, DiaryDocState.draft);

      expect(await repo.availableYears(), [2026]);
      expect(await repo.monthsOfYear(2026), [3, 12]); // 12 = 当前月
    });

    test('预览跳过空块、压平换行并截断到 40 字', () async {
      final repo = InMemoryDiaryRepository(
        now: () => fixedNow,
        seedDebugData: false,
      );
      await repo.upsertDraft(doc(DateTime(2026, 3, 10), [
        '',
        '行1\n行2${'x' * 40}',
      ]));
      final s = (await repo.daysOfMonth(2026, 3)).single;
      expect(s.preview.startsWith('行1 行2'), isTrue);
      expect(s.preview.length, 40);
    });

    test('upsert 触发监听（列表页据此刷新）', () async {
      final repo = InMemoryDiaryRepository(
        now: () => fixedNow,
        seedDebugData: false,
      );
      var notified = 0;
      repo.addListener(() => notified++);

      await repo.upsertDraft(doc(DateTime(2026, 3, 11), ['a']));
      expect(notified, 1);
    });

    test('draftCountOfMonth 按月计数，其他月份为 0', () async {
      final repo = InMemoryDiaryRepository(
        now: () => fixedNow,
        seedDebugData: false,
      );
      await repo.upsertDraft(doc(DateTime(2026, 3, 2), ['a']));
      await repo.upsertDraft(doc(DateTime(2026, 3, 20), ['b']));
      await repo.upsertDraft(doc(DateTime(2026, 4, 1), ['c']));

      expect(await repo.draftCountOfMonth(2026, 3), 2);
      expect(await repo.draftCountOfMonth(2026, 4), 1);
      expect(await repo.draftCountOfMonth(2026, 5), 0);
    });

    test('多日按日期升序返回', () async {
      final repo = InMemoryDiaryRepository(
        now: () => fixedNow,
        seedDebugData: false,
      );
      await repo.upsertDraft(doc(DateTime(2026, 3, 20), ['late']));
      await repo.upsertDraft(doc(DateTime(2026, 3, 2), ['early']));
      final days = await repo.daysOfMonth(2026, 3);
      expect(days.map((d) => d.date.day), [2, 20]);
    });
  });

  group('InMemoryDiaryRepository 开发种子', () {
    test('固定时钟下安装今天/昨天/上月三篇', () async {
      final repo = InMemoryDiaryRepository(
        now: () => DateTime(2026, 12, 15),
        seedDebugData: true,
      );
      expect(await repo.findDay(DateTime(2026, 12, 15)), isNotNull);
      expect(await repo.findDay(DateTime(2026, 12, 14)), isNotNull);
      expect(await repo.findDay(DateTime(2026, 11, 15)), isNotNull);
    });

    test('年初回绕：上月落在去年 12 月', () async {
      final repo = InMemoryDiaryRepository(
        now: () => DateTime(2027, 1, 3),
        seedDebugData: true,
      );
      expect(await repo.findDay(DateTime(2026, 12, 3)), isNotNull);
      expect(await repo.availableYears(), containsAll([2026, 2027]));
    });

    test('显式关闭时不安装种子', () async {
      final repo = InMemoryDiaryRepository(
        now: () => DateTime(2026, 12, 15),
        seedDebugData: false,
      );
      expect(await repo.findDay(DateTime(2026, 12, 15)), isNull);
    });
  });
}
