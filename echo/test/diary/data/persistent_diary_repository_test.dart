import 'dart:io';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_common_ffi.dart';

import 'package:echo/src/diary/data/diary_clock.dart';
import 'package:echo/src/diary/data/diary_data_provider.dart';
import 'package:echo/src/diary/data/persistent_diary_repository.dart';
import 'package:echo/src/diary/data/diary_repository.dart';
import 'package:echo/src/diary/sy/diary_model.dart';
import 'package:echo/src/diary/sy/sy_id.dart';
import 'package:echo/src/diary/template/daily_default_template.dart';
import 'package:echo/src/diary/template/diary_composer.dart';

void main() {
  setUpAll(() {
    TestWidgetsFlutterBinding.ensureInitialized(); // loadAsset 需要
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  final fixedNow = DateTime(2026, 10, 11, 12);
  final ids = SyIdGenerator(random: Random(7), now: () => fixedNow);

  DiaryDocument doc(
    DateTime date,
    List<String> paragraphs, {
    Map<String, String>? custom,
  }) {
    return DiaryDocument(
      id: SyIdGenerator.dayContainer(date),
      date: date,
      title: '${date.month}月${date.day}日',
      custom: custom ?? {},
      blocks: [for (final t in paragraphs) DiaryBlock(id: ids.next(), text: t)],
    );
  }

  Future<Directory> tempRoot() =>
      Directory.systemTemp.createTemp('echo_persist_m5_');

  Future<PersistentDiaryRepository> open(
    Directory root, {
    DateTime? now,
    bool seed = false,
  }) => PersistentDiaryRepository.open(
    root: root,
    clock: DiaryClock(now: () => now ?? fixedNow),
    seedDebugData: seed,
    dbFactory: databaseFactoryFfi,
  );

  group('PersistentDiaryRepository 跨进程持久化', () {
    test('upsert → 关闭 → 重开：正文/custom/底色逐字段往返', () async {
      final root = await tempRoot();
      addTearDown(() => root.delete(recursive: true));
      final date = DateTime(2026, 10, 10);
      final original = DiaryDocument(
        id: SyIdGenerator.dayContainer(date),
        date: date,
        title: '10月10日',
        custom: const {'custom-mood': '🙂', 'custom-weather': '多云'},
        blocks: [
          DiaryBlock(id: ids.next(), text: '第一段'),
          DiaryBlock(id: ids.next(), text: '第一行\n第二行'),
          DiaryBlock(
            id: ids.next(),
            kind: DiaryBlockKind.heading,
            level: 2,
            text: '小标题',
          ),
          DiaryBlock(id: ids.next(), text: '', background: 12),
        ],
      );
      final repo1 = await open(root);
      await repo1.upsertDraft(original);
      await repo1.close();

      final repo2 = await open(root);
      addTearDown(repo2.close);
      final found = await repo2.findDay(date);
      expect(found, isNotNull);
      expect(found!.id, original.id);
      expect(found.title, '10月10日');
      expect(found.custom, {'custom-mood': '🙂', 'custom-weather': '多云'});
      expect(found.blocks, hasLength(4));
      expect(found.blocks[0].text, '第一段');
      expect(found.blocks[1].text, '第一行\n第二行');
      expect(found.blocks[2].kind, DiaryBlockKind.heading);
      expect(found.blocks[2].level, 2);
      expect(found.blocks[3].background, 12);
      expect(found.locked, isFalse);

      // 列表来自 meta 反范式列，不读正文文件；预览取首个非空段落。
      final summary = (await repo2.daysOfMonth(2026, 10)).single;
      expect(summary.preview, '第一段');
      expect(summary.blockCount, 4);
      expect(summary.state, DiaryDocState.draft);
    });

    test('年月聚合与月篇数跨重开保留，含三态计数', () async {
      final root = await tempRoot();
      addTearDown(() => root.delete(recursive: true));
      final repo1 = await open(root);
      await repo1.upsertDraft(doc(DateTime(2026, 9, 30), ['九月']));
      await repo1.upsertDraft(doc(DateTime(2026, 10, 1), ['十月一']));
      await repo1.upsertDraft(doc(DateTime(2026, 10, 2), ['十月二']));
      await repo1.markExported([DateTime(2026, 10, 2)], exportedAt: fixedNow);
      await repo1.upsertDraft(doc(DateTime(2026, 10, 3), ['十月三']));
      await repo1.markExported([DateTime(2026, 10, 3)], exportedAt: fixedNow);
      await repo1.archiveDay(DateTime(2026, 10, 3));
      await repo1.close();

      final repo2 = await open(root);
      addTearDown(repo2.close);
      expect(await repo2.availableYears(), [2026]);
      expect(await repo2.monthsOfYear(2026), [9, 10]);
      expect(await repo2.draftCountOfMonth(2026, 10), 3);
      final summaries = await repo2.daysOfMonth(2026, 10);
      expect(summaries.map((s) => s.state), [
        DiaryDocState.draft,
        DiaryDocState.exported,
        DiaryDocState.archived,
      ]);
    });

    test('原子写：无 .tmp 残留，正文文件即最终内容', () async {
      final root = await tempRoot();
      addTearDown(() => root.delete(recursive: true));
      final repo = await open(root);
      addTearDown(repo.close);
      await repo.upsertDraft(doc(DateTime(2026, 10, 9), ['原子写']));
      final files = await root
          .list(recursive: true)
          .where((e) => e is File)
          .map((e) => e.path)
          .toList();
      expect(files.any((p) => p.endsWith('.tmp')), isFalse);
      expect(files.where((p) => p.endsWith('.sy')), hasLength(1));
    });

    test('孤儿自愈：无 meta 的 .sy 与遗留 .tmp 在重开时清除', () async {
      final root = await tempRoot();
      addTearDown(() => root.delete(recursive: true));
      final repo1 = await open(root);
      await repo1.upsertDraft(doc(DateTime(2026, 10, 8), ['在册']));
      await repo1.close();

      final strayDir = await Directory('${root.path}/diary/2025')
          .create(recursive: true);
      File('${strayDir.path}/20250101080000-echo000.sy')
          .writeAsStringSync('{}');
      File('${strayDir.path}/20250102080000-echo000.sy.tmp')
          .writeAsStringSync('half');

      final repo2 = await open(root);
      addTearDown(repo2.close);
      expect(
        File('${strayDir.path}/20250101080000-echo000.sy').existsSync(),
        isFalse,
      );
      expect(
        File('${strayDir.path}/20250102080000-echo000.sy.tmp').existsSync(),
        isFalse,
      );
      // 在册文件安然无恙。
      expect(await repo2.findDay(DateTime(2026, 10, 8)), isNotNull);
    });
  });

  group('PersistentDiaryRepository 状态机', () {
    test('draft→exported：只读并排除出增量打包', () async {
      final root = await tempRoot();
      addTearDown(() => root.delete(recursive: true));
      final repo = await open(root);
      addTearDown(repo.close);
      await repo.upsertDraft(doc(DateTime(2026, 10, 1), ['一']));
      await repo.upsertDraft(doc(DateTime(2026, 10, 2), ['二']));

      final drafts = await repo.draftDocumentsOfYear(2026);
      expect(drafts.map((d) => d.date.day), [1, 2]);

      await repo.markExported([DateTime(2026, 10, 1)], exportedAt: fixedNow);
      expect(
        await repo.stateOfDay(DateTime(2026, 10, 1)),
        DiaryDocState.exported,
      );
      final exported = await repo.findDay(DateTime(2026, 10, 1));
      expect(exported!.locked, isTrue);
      final stillDraft = await repo.draftDocumentsOfYear(2026);
      expect(stillDraft.map((d) => d.date.day), [2]);

      expect(
        () => repo.upsertDraft(doc(DateTime(2026, 10, 1), ['改'])),
        throwsA(isA<StateError>()),
      );
    });

    test('exported→archived：删正文文件、留 meta 索引、终态不可写', () async {
      final root = await tempRoot();
      addTearDown(() => root.delete(recursive: true));
      final repo = await open(root);
      addTearDown(repo.close);
      final date = DateTime(2026, 10, 1);
      await repo.upsertDraft(doc(date, ['归档前正文']));
      await repo.markExported([date], exportedAt: fixedNow);
      final relative = 'diary/2026/10/${SyIdGenerator.dayContainer(date)}.sy';
      expect(File('${root.path}/$relative').existsSync(), isTrue);

      await repo.archiveDay(date);
      expect(File('${root.path}/$relative').existsSync(), isFalse);
      expect(await repo.findDay(date), isNull);
      expect(await repo.dayExists(date), isTrue);
      expect(await repo.stateOfDay(date), DiaryDocState.archived);
      final summary = (await repo.daysOfMonth(2026, 10)).single;
      expect(summary.state, DiaryDocState.archived);
      expect(await repo.draftCountOfMonth(2026, 10), 1);

      expect(
        () => repo.upsertDraft(doc(date, ['复活'])),
        throwsA(isA<StateError>()),
      );
      expect(() => repo.archiveDay(date), throwsA(isA<StateError>()));
    });

    test('非法迁移：缺行导致整批不动；draft 不可直接归档', () async {
      final root = await tempRoot();
      addTearDown(() => root.delete(recursive: true));
      final repo = await open(root);
      addTearDown(repo.close);
      await repo.upsertDraft(doc(DateTime(2026, 10, 1), ['一']));

      await expectLater(
        repo.markExported([
          DateTime(2026, 10, 1),
          DateTime(2026, 10, 2),
        ], exportedAt: fixedNow),
        throwsA(isA<StateError>()),
      );
      // 整批不迁移。
      expect(await repo.stateOfDay(DateTime(2026, 10, 1)), DiaryDocState.draft);

      expect(
        () => repo.archiveDay(DateTime(2026, 10, 1)),
        throwsA(isA<StateError>()),
      );
    });
  });

  group('PersistentDiaryRepository.pruneEmptyBefore 跨进程', () {
    test('重开后按新今天清理：空 draft 连文件删除，有字稿/导出稿保留', () async {
      final root = await tempRoot();
      addTearDown(() => root.delete(recursive: true));
      // 第一次启动（10-11）：前天空稿 + 前天有字稿 + 昨天导出稿。
      final repo1 = await open(root, now: DateTime(2026, 10, 11, 12));
      final empty = DateTime(2026, 10, 9);
      final written = DateTime(2026, 10, 8);
      final exported = DateTime(2026, 10, 10);
      await repo1.upsertDraft(doc(empty, ['']));
      await repo1.upsertDraft(doc(written, ['写过字']));
      await repo1.upsertDraft(doc(exported, ['已导出']));
      await repo1.markExported([exported], exportedAt: fixedNow);
      await repo1.close();

      // 次日跨 04:00 冷启：bootstrap 调 prune。
      final repo2 = await open(root, now: DateTime(2026, 10, 12, 12));
      final result = await repo2.pruneEmptyBefore(
        DateTime(2026, 10, 12),
        (d) => d.blocks.every((b) => b.text.trim().isEmpty),
      );
      expect(result.deletedCount, 1);
      expect(result.kept.map((e) => (e.$1.day, e.$2)), [
        (8, 'non-empty'),
        (10, 'exported'),
      ]);
      expect(await repo2.dayExists(empty), isFalse);
      expect(await repo2.findDay(written), isNotNull);
      expect(await repo2.stateOfDay(exported), DiaryDocState.exported);
      await repo2.close();

      // 第三个实例确认删除已落盘（meta + 文件都不在）。
      final repo3 = await open(root, now: DateTime(2026, 10, 12, 12));
      addTearDown(repo3.close);
      expect(await repo3.dayExists(empty), isFalse);
      expect(await repo3.draftCountOfMonth(2026, 10), 2);
    });

    test('真实 composer 谓词经磁盘往返：单空段骨架被清、有字稿保留', () async {
      // 2026-10-18 模板重设后成稿为「单空段骨架 + custom-* 数据」：
      // custom-* 不占块，prune 从 .sy 直读也应稳定判空并清理。
      final root = await tempRoot();
      addTearDown(() => root.delete(recursive: true));
      final composer = DiaryComposer(
        template: await DailyDefaultTemplate.loadAsset(),
        provider: FakeDiaryDataProvider(),
        idGenerator: SyIdGenerator(random: Random(1), now: () => fixedNow),
      );

      final empty = DateTime(2026, 10, 9);
      final written = DateTime(2026, 10, 8);
      final repo1 = await open(root, now: DateTime(2026, 10, 10, 12));
      await composer.ensureDay(empty, repo1); // 仅单空段骨架 + custom-*。
      final withText = await composer.ensureDay(written, repo1);
      withText.blocks.first.text = '写了内容';
      await repo1.upsertDraft(withText);
      await repo1.close();

      // 次日冷启：bootstrap 的真实调用形态。
      final repo2 = await open(root, now: DateTime(2026, 10, 11, 12));
      addTearDown(repo2.close);
      final result = await repo2.pruneEmptyBefore(
        DateTime(2026, 10, 11),
        composer.isUserEmpty,
      );
      expect(result.deletedCount, 1);
      expect(await repo2.dayExists(empty), isFalse);
      expect(await repo2.dayExists(written), isTrue);
      expect((await repo2.findDay(written))!.blocks.first.text, '写了内容');
    });
  });

  group('PersistentDiaryRepository.wipeAll（ECP diary.reset）', () {
    test('meta 与 diary/ 目录全清，库仍可写；重开后为空仓', () async {
      final root = await tempRoot();
      addTearDown(() => root.delete(recursive: true));
      final repo = await open(root, now: fixedNow);
      await repo.upsertDraft(doc(DateTime(2026, 10, 10), ['a']));
      await repo.upsertDraft(doc(DateTime(2026, 9, 9), ['b']));

      final result = await repo.wipeAll();
      expect(result.removedDocs, 2);
      expect(result.removedFiles, 2);
      expect(Directory('${root.path}/diary').existsSync(), isFalse);
      expect(await repo.availableYears(), isEmpty);

      // 同一连接继续写；随后重开确认落盘为空。
      await repo.upsertDraft(doc(DateTime(2026, 10, 11), ['新的']));
      await repo.close();
      final reopened = await open(root, now: fixedNow);
      addTearDown(reopened.close);
      expect(await reopened.draftCountOfMonth(2026, 10), 1);
      expect(await reopened.draftCountOfMonth(2026, 9), 0);
    });
  });

  group('PersistentDiaryRepository debug 种子', () {
    test('seedDebugData 首装注入两篇；重开不重复注入', () async {
      final root = await tempRoot();
      addTearDown(() => root.delete(recursive: true));
      final repo1 = await open(root, now: fixedNow, seed: true);
      expect(await repo1.findDay(DateTime(2026, 10, 10)), isNotNull);
      expect(
        await repo1.findDay(DateTime(2026, 9, min(fixedNow.day, 28))),
        isNotNull,
      );
      await repo1.close();

      final repo2 = await open(root, now: fixedNow, seed: true);
      addTearDown(repo2.close);
      expect(await repo2.draftCountOfMonth(2026, 10), 1);
    });

    test('默认不注入', () async {
      final root = await tempRoot();
      addTearDown(() => root.delete(recursive: true));
      final repo = await open(root, now: fixedNow);
      addTearDown(repo.close);
      expect(await repo.availableYears(), isEmpty);
    });
  });
}
