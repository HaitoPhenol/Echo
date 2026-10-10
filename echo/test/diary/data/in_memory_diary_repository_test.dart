import 'dart:math';

import 'package:flutter_test/flutter_test.dart';

import 'package:echo/src/diary/data/diary_clock.dart';
import 'package:echo/src/diary/data/diary_repository.dart';
import 'package:echo/src/diary/data/in_memory_diary_repository.dart';
import 'package:echo/src/diary/sy/diary_model.dart';
import 'package:echo/src/diary/sy/sy_id.dart';

void main() {
  final fixedNow = DateTime(2026, 12, 15, 9, 30);

  InMemoryDiaryRepository repoAt(DateTime now, {bool seed = false}) =>
      InMemoryDiaryRepository(
        clock: DiaryClock(now: () => now),
        seedDebugData: seed,
      );

  DiaryDocument doc(DateTime date, List<String> paragraphs) =>
      DiaryDocument(
        id: SyIdGenerator.dayContainer(date),
        date: date,
        title: '${date.month}月${date.day}日',
        blocks: [
          for (final t in paragraphs)
            DiaryBlock(id: '20260101000000-aaaaaaa', text: t),
        ],
      );
  // 注意：测试里每篇文档块 ID 相同没有关系（仓储不校验块 ID 冲突），
  // 仅当同一文档内需要多块时才单独构造。

  group('InMemoryDiaryRepository 时钟与空仓（M4 新口径）', () {
    test('today 委托 DiaryClock：03:xx 归前一天，04:xx 归当天', () {
      expect(
        repoAt(DateTime(2026, 12, 15, 3, 59)).today(),
        DateTime(2026, 12, 14),
      );
      expect(
        repoAt(DateTime(2026, 12, 15, 4, 0)).today(),
        DateTime(2026, 12, 15),
      );
    });

    test('空仓年/月/日列表全空，不再兜底当前年月', () async {
      final repo = repoAt(fixedNow);
      expect(await repo.availableYears(), isEmpty);
      expect(await repo.monthsOfYear(2026), isEmpty);
      expect(await repo.daysOfMonth(2026, 12), isEmpty);
      expect(await repo.findDay(fixedNow), isNull);
    });
  });

  group('InMemoryDiaryRepository 草稿读写', () {
    test('upsert 后 findDay/daysOfMonth 可见，并按自然日归一', () async {
      final repo = repoAt(fixedNow);
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
      expect(await repo.monthsOfYear(2026), [3]); // 不再兜底 12 月
    });

    test('预览跳过空块、压平换行并截断到 40 字', () async {
      final repo = repoAt(fixedNow);
      await repo.upsertDraft(doc(DateTime(2026, 3, 10), [
        '',
        '行1\n行2${'x' * 40}',
      ]));
      final s = (await repo.daysOfMonth(2026, 3)).single;
      expect(s.preview.startsWith('行1 行2'), isTrue);
      expect(s.preview.length, 40);
    });

    test('M4：预览忽略 readonly data 快照与标题，模板空稿预览为空', () async {
      final repo = repoAt(fixedNow);
      final date = DateTime(2026, 3, 12);
      final ids = SyIdGenerator(random: Random(3), now: () => fixedNow);
      await repo.upsertDraft(
        DiaryDocument(
          id: SyIdGenerator.dayContainer(date),
          date: date,
          title: '3月12日',
          blocks: [
            DiaryBlock(
              id: ids.next(),
              kind: DiaryBlockKind.heading,
              level: 2,
              text: '📈 自动记录',
            ),
            DiaryBlock(
              id: SyIdGenerator.dataBlock(date, 1),
              text: '🌡️ 21°C　💧 45%　📅 3 条日程　☁️ 多云',
              background: 3,
              readonly: true,
            ),
            DiaryBlock(
              id: ids.next(),
              kind: DiaryBlockKind.heading,
              level: 2,
              text: '💭 今天',
            ),
            DiaryBlock(id: ids.next(), text: ''),
          ],
        ),
      );
      final s = (await repo.daysOfMonth(2026, 3)).single;
      expect(s.preview, '');
    });

    test('upsert 触发监听（列表页据此刷新）', () async {
      final repo = repoAt(fixedNow);
      var notified = 0;
      repo.addListener(() => notified++);

      await repo.upsertDraft(doc(DateTime(2026, 3, 11), ['a']));
      expect(notified, 1);
    });

    test('draftCountOfMonth 按月计数，其他月份为 0', () async {
      final repo = repoAt(fixedNow);
      await repo.upsertDraft(doc(DateTime(2026, 3, 2), ['a']));
      await repo.upsertDraft(doc(DateTime(2026, 3, 20), ['b']));
      await repo.upsertDraft(doc(DateTime(2026, 4, 1), ['c']));

      expect(await repo.draftCountOfMonth(2026, 3), 2);
      expect(await repo.draftCountOfMonth(2026, 4), 1);
      expect(await repo.draftCountOfMonth(2026, 5), 0);
    });

    test('多日按日期升序返回', () async {
      final repo = repoAt(fixedNow);
      await repo.upsertDraft(doc(DateTime(2026, 3, 20), ['late']));
      await repo.upsertDraft(doc(DateTime(2026, 3, 2), ['early']));
      final days = await repo.daysOfMonth(2026, 3);
      expect(days.map((d) => d.date.day), [2, 20]);
    });
  });

  group('InMemoryDiaryRepository.pruneEmptyBefore（§5.2 第 4 条）', () {
    test('删除 cutoff 之前判定为空的草稿，保留非空与今天', () async {
      final repo = repoAt(DateTime(2026, 12, 15));
      // 早于 cutoff 的空稿（判定由外部 predicate 决定）。
      await repo.upsertDraft(doc(DateTime(2026, 12, 13), ['']));
      await repo.upsertDraft(doc(DateTime(2026, 12, 14), ['']));
      // 早于 cutoff 但写过字。
      await repo.upsertDraft(doc(DateTime(2026, 12, 12), ['写过']));
      // 今天的空稿永不删。
      await repo.upsertDraft(doc(DateTime(2026, 12, 15), ['']));

      var notified = 0;
      repo.addListener(() => notified++);

      final removed = await repo.pruneEmptyBefore(
        DateTime(2026, 12, 15),
        (d) => d.blocks.every((b) => b.text.trim().isEmpty),
      );

      expect(removed, 2);
      expect(notified, 1);
      expect(await repo.findDay(DateTime(2026, 12, 13)), isNull);
      expect(await repo.findDay(DateTime(2026, 12, 14)), isNull);
      expect(await repo.findDay(DateTime(2026, 12, 12)), isNotNull);
      expect(await repo.findDay(DateTime(2026, 12, 15)), isNotNull);
    });

    test('没有可删项时不触发 notify，返回 0', () async {
      final repo = repoAt(DateTime(2026, 12, 15));
      await repo.upsertDraft(doc(DateTime(2026, 12, 14), ['写过']));
      var notified = 0;
      repo.addListener(() => notified++);

      final removed = await repo.pruneEmptyBefore(
        DateTime(2026, 12, 15),
        (d) => d.blocks.every((b) => b.text.trim().isEmpty),
      );
      expect(removed, 0);
      expect(notified, 0);
    });

    test('连续多天未打开：一次性清掉多天', () async {
      final repo = repoAt(DateTime(2026, 12, 15));
      await repo.upsertDraft(doc(DateTime(2026, 12, 10), ['']));
      await repo.upsertDraft(doc(DateTime(2026, 12, 11), ['']));
      await repo.upsertDraft(doc(DateTime(2026, 12, 12), ['']));
      final removed = await repo.pruneEmptyBefore(
        DateTime(2026, 12, 15),
        (d) => d.blocks.every((b) => b.text.trim().isEmpty),
      );
      expect(removed, 3);
      expect(await repo.daysOfMonth(2026, 12), isEmpty);
    });
  });

  group('InMemoryDiaryRepository 开发种子', () {
    test('固定时钟下安装昨天/上月两篇，今天不种子（自动成稿接管）', () async {
      final repo = repoAt(DateTime(2026, 12, 15, 12), seed: true);
      expect(await repo.findDay(DateTime(2026, 12, 15)), isNull);
      expect(await repo.findDay(DateTime(2026, 12, 14)), isNotNull);
      expect(await repo.findDay(DateTime(2026, 11, 15)), isNotNull);
    });

    test('年初回绕：上月落在去年 12 月', () async {
      final repo = repoAt(DateTime(2027, 1, 3, 12), seed: true);
      // 昨天 2027-01-02，上月 2026-12-03。
      expect(await repo.findDay(DateTime(2026, 12, 3)), isNotNull);
      expect(await repo.findDay(DateTime(2027, 1, 2)), isNotNull);
      expect(await repo.availableYears(), containsAll([2026, 2027]));
    });

    test('显式关闭时不安装种子', () async {
      final repo = repoAt(DateTime(2026, 12, 15));
      expect(await repo.findDay(DateTime(2026, 12, 15)), isNull);
    });
  });
}
