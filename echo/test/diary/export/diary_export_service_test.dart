import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:share_plus/share_plus.dart';

import 'package:echo/src/diary/data/diary_clock.dart';
import 'package:echo/src/diary/data/diary_repository.dart';
import 'package:echo/src/diary/data/in_memory_diary_repository.dart';
import 'package:echo/src/diary/export/diary_export_service.dart';
import 'package:echo/src/diary/sy/diary_model.dart';
import 'package:echo/src/diary/sy/sy_id.dart';
import 'package:echo/src/diary/sy/sy_serializer.dart';

/// 假分享通道：捕获传给系统分享面板的文件（不碰平台通道）。
class _RecordingShare {
  final List<List<XFile>> calls = [];

  /// 回调内立即读字节（服务成功返回后会删除临时 zip）。
  final List<List<int>> payloads = [];
  bool shouldThrow = false;

  Future<void> call(List<XFile> files) async {
    if (shouldThrow) throw StateError('用户取消分享');
    calls.add(files);
    for (final f in files) {
      payloads.add(await f.readAsBytes());
    }
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // 固定 2026-06-15，种子关闭，仓储内容完全由用例构造。
  final now = DateTime(2026, 6, 15, 20, 30, 0);
  late Directory tempDir;
  late InMemoryDiaryRepository repo;
  late _RecordingShare share;
  late DiaryExportService service;

  DiaryDocument draft(DateTime date, {String? mood, String text = '正文'}) {
    final day8 = SyIdGenerator.timestamp(
      DateTime(date.year, date.month, date.day, 21),
    ).substring(0, 8);
    return DiaryDocument(
      id: SyIdGenerator.dayContainer(date),
      date: DateTime(date.year, date.month, date.day),
      title: SySerializer.dayTitle(date),
      custom: mood == null ? null : {'custom-mood': mood},
      blocks: [
        // 22 位思源块 ID：8 位日期 + 6 位时刻 + '-' + 7 位随机串。
        DiaryBlock(id: '${day8}210000-daaaaaa', text: text),
      ],
    );
  }

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('echo-export-test');
    repo = InMemoryDiaryRepository(
      clock: DiaryClock(now: () => now),
      seedDebugData: false,
    );
    share = _RecordingShare();
    service = DiaryExportService(
      repository: repo,
      shareChannel: share.call,
      tempDirectory: () async => tempDir,
      now: () => now,
    );
  });

  tearDown(() async {
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  group('DiaryExportService.exportYear', () {
    test('打包当年 draft 分享成功：zip 结构正确、状态批量迁移、临时文件清理', () async {
      final d1 = DateTime(2026, 6, 14);
      final d2 = DateTime(2026, 6, 15);
      // 去年一篇不应入包。
      final otherYear = DateTime(2025, 12, 31);
      await repo.upsertDraft(draft(d1, mood: '🙂', text: '昨天写的'));
      await repo.upsertDraft(draft(d2, mood: '😄', text: '今天写的'));
      await repo.upsertDraft(draft(otherYear, mood: '😢'));

      final outcome = await service.exportYear(2026);
      expect(outcome.exportedCount, 2);
      expect(outcome.didShare, isTrue);
      expect(share.calls, hasLength(1));
      final files = share.calls.single;
      expect(files, hasLength(1));
      expect(files.single.mimeType, 'application/zip');

      // 文件名：日记-{年}-{yyyyMMdd-HHmmss}.sy.zip。
      final fileName = files.single.path.split(Platform.pathSeparator).last;
      expect(fileName, '日记-2026-20260615-203000.sy.zip');

      final archive = ZipDecoder().decodeBytes(share.payloads.single);
      final names = archive.files.map((f) => f.name).toList();
      // 金标准骨架：固定「日记」笔记本 + conf/sort。
      expect(names, contains('日记/.siyuan/conf.json'));
      expect(names, contains('日记/.siyuan/sort.json'));
      // 三级路径：年/月/日，仅当年（2026 年包一个年容器、一个 6 月容器）。
      expect(
        names.where((n) => n.endsWith('.sy') && !n.contains('.siyuan')),
        hasLength(4), // 年 + 月 + 2 日
      );
      final yearId = SyIdGenerator.yearContainer(2026);
      final monthId = SyIdGenerator.monthContainer(DateTime(2026, 6));
      expect(names, contains('日记/$yearId.sy'));
      expect(names, contains('日记/$yearId/$monthId.sy'));
      expect(
        names,
        contains('日记/$yearId/$monthId/${SyIdGenerator.dayContainer(d1)}.sy'),
      );
      expect(
        names,
        contains('日记/$yearId/$monthId/${SyIdGenerator.dayContainer(d2)}.sy'),
      );

      // 正文 custom-mood 进入 JSON（思源属性视图聚合的数据源）。
      final d2Raw = utf8.decode(
        archive.files
            .firstWhere(
              (f) => f.name.endsWith('${SyIdGenerator.dayContainer(d2)}.sy'),
            )
            .content,
      );
      expect(d2Raw, contains('"custom-mood":"😄"'));
      expect(d2Raw, contains('今天写的'));

      // conf.json 笔记本名固定「日记」。
      final conf = jsonDecode(
        utf8.decode(
          archive.files.firstWhere((f) => f.name.endsWith('conf.json')).content,
        ),
      ) as Map;
      expect(conf['name'], '日记');

      // 分享成功后两篇 draft → exported，去年草稿不受影响。
      expect(await repo.stateOfDay(d1), DiaryDocState.exported);
      expect(await repo.stateOfDay(d2), DiaryDocState.exported);
      expect(await repo.stateOfDay(otherYear), DiaryDocState.draft);
      // 临时 zip 已清理。
      expect(await File(files.single.path).exists(), isFalse);
    });

    test('当年无 draft：不分享、不迁移，返回 exportedCount=0', () async {
      await repo.upsertDraft(draft(DateTime(2025, 1, 1)));
      final outcome = await service.exportYear(2026);
      expect(outcome.exportedCount, 0);
      expect(outcome.didShare, isFalse);
      expect(share.calls, isEmpty);
      expect(tempDir.listSync(), isEmpty);
    });

    test('第二次导出：已 exported 不再入包，当年待导出为 0', () async {
      final d = DateTime(2026, 6, 15);
      await repo.upsertDraft(draft(d, mood: '🙂'));
      final first = await service.exportYear(2026);
      expect(first.exportedCount, 1);

      final second = await service.exportYear(2026);
      expect(second.exportedCount, 0);
      expect(share.calls, hasLength(1));
      expect(await repo.stateOfDay(d), DiaryDocState.exported);
    });

    test('分享抛错：draft 全部保留、临时 zip 不删除、错误上抛', () async {
      final d = DateTime(2026, 6, 15);
      await repo.upsertDraft(draft(d));
      share.shouldThrow = true;

      await expectLater(service.exportYear(2026), throwsStateError);
      expect(await repo.stateOfDay(d), DiaryDocState.draft);
      // 临时 zip 保留作排查。
      final zips = tempDir.listSync().whereType<File>().where(
        (f) => f.path.endsWith('.sy.zip'),
      );
      expect(zips, hasLength(1));
    });
  });
}
