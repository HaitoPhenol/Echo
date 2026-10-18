import 'dart:math';

import 'package:echo/src/diary/data/diary_clock.dart';
import 'package:echo/src/diary/data/diary_data_provider.dart';
import 'package:echo/src/diary/data/diary_repository.dart';
import 'package:echo/src/diary/data/in_memory_diary_repository.dart';
import 'package:echo/src/diary/sy/diary_model.dart';
import 'package:echo/src/diary/sy/sy_id.dart';
import 'package:echo/src/diary/sy/sy_serializer.dart';
import 'package:echo/src/diary/template/daily_default_template.dart';
import 'package:echo/src/diary/template/diary_composer.dart';
import 'package:echo/src/diary/template/diary_template_json.dart';
import 'package:flutter_test/flutter_test.dart';

const _json = '''
{
  "id": "daily-default-v2",
  "blocks": [
    { "type": "paragraph", "background": 12 },
    { "type": "paragraph" }
  ]
}
''';

/// 计数型 provider：包装 fake 值，记录三源调用次数。
class _CountingProvider implements DiaryDataProvider {
  _CountingProvider({this.delay = Duration.zero});

  HomeEnvironment? env = const (tempC: 21, humidityPct: 45);
  int? count = 3;
  String? weather = '多云';
  Duration delay;
  int envCalls = 0;
  int countCalls = 0;
  int weatherCalls = 0;

  @override
  Future<HomeEnvironment?> fetchHomeEnvironment(DateTime d) async {
    envCalls++;
    if (delay > Duration.zero) await Future<void>.delayed(delay);
    return env;
  }

  @override
  Future<int?> fetchScheduleCount(DateTime d) async {
    countCalls++;
    if (delay > Duration.zero) await Future<void>.delayed(delay);
    return count;
  }

  @override
  Future<String?> fetchWeather(DateTime d) async {
    weatherCalls++;
    if (delay > Duration.zero) await Future<void>.delayed(delay);
    return weather;
  }
}

/// 仅天气源抛异常：验证三源互不连坐。
class _WeatherThrowsProvider extends _CountingProvider {
  @override
  Future<String?> fetchWeather(DateTime d) async {
    weatherCalls++;
    throw StateError('天气源不可用');
  }
}

void main() {
  final today = DateTime(2026, 10, 10);

  DiaryComposer buildComposer({
    required DiaryDataProvider provider,
    SyIdGenerator? ids,
  }) {
    return DiaryComposer(
      template: DailyDefaultTemplate(spec: DiaryTemplateSpec.fromJson(_json)),
      provider: provider,
      idGenerator: ids ?? SyIdGenerator(random: Random(7), now: () => today),
      now: () => DateTime(2026, 10, 10, 8),
    );
  }

  InMemoryDiaryRepository buildRepo() => InMemoryDiaryRepository(
    clock: DiaryClock(now: () => DateTime(2026, 10, 10, 9)),
    seedDebugData: false,
  );

  group('DiaryComposer.ensureDay 成稿', () {
    test('空日成稿：概述段 + 空正文段骨架 + 四个 custom-* + 立即落盘', () async {
      final provider = _CountingProvider();
      final composer = buildComposer(provider: provider);
      final repo = buildRepo();

      final doc = await composer.ensureDay(today, repo);

      expect(doc.blocks, hasLength(2));
      expect(doc.blocks.first.background, DiaryComposer.summaryBackground);
      expect(doc.blocks.first.text, isEmpty);
      expect(doc.blocks.last.kind, DiaryBlockKind.paragraph);
      expect(doc.blocks.last.background, isNull);
      expect(doc.blocks.last.text, isEmpty);

      expect(doc.custom, {
        'custom-iot-temp': '21',
        'custom-iot-humidity': '45',
        'custom-schedule-count': '3',
        'custom-weather': '多云',
      });
      expect(doc.custom.containsKey('custom-echo-template'), isFalse);

      // 已落盘：仓储命中同一篇。
      final again = await repo.findDay(today);
      expect(again, same(doc));
    });

    test('成稿即占月篇数（落盘语义）', () async {
      final composer = buildComposer(provider: _CountingProvider());
      final repo = buildRepo();
      expect(await repo.draftCountOfMonth(2026, 10), 0);
      await composer.ensureDay(today, repo);
      expect(await repo.draftCountOfMonth(2026, 10), 1);
    });

    test('已有草稿：不重拉 provider、不覆盖，原样返回', () async {
      final provider = _CountingProvider();
      final composer = buildComposer(provider: provider);
      final repo = buildRepo();
      final first = await composer.ensureDay(today, repo);

      final second = await composer.ensureDay(today, repo);
      expect(second, same(first));
      expect(provider.envCalls, 1);
      expect(provider.countCalls, 1);
      expect(provider.weatherCalls, 1);
    });

    test('并发双 ensureDay：in-flight 去重，只拉一次数、只落盘一次', () async {
      final provider = _CountingProvider(
        delay: const Duration(milliseconds: 30),
      );
      final composer = buildComposer(provider: provider);
      final repo = buildRepo();
      var notifies = 0;
      repo.addListener(() => notifies++);

      final f1 = composer.ensureDay(today, repo);
      final f2 = composer.ensureDay(today, repo);
      final results = await Future.wait([f1, f2]);

      expect(identical(results[0], results[1]), isTrue);
      expect(provider.envCalls, 1);
      expect(provider.countCalls, 1);
      expect(provider.weatherCalls, 1);
      expect(notifies, 1);
    });

    test('补记过去空日可以成稿', () async {
      final composer = buildComposer(provider: _CountingProvider());
      final repo = buildRepo();
      final past = DateTime(2026, 9, 28);
      final doc = await composer.ensureDay(past, repo);
      expect(doc.date, past);
      expect(doc.id, SyIdGenerator.dayContainer(past));
    });

    test('未来日期拒绝成稿', () async {
      final composer = buildComposer(provider: _CountingProvider());
      final repo = buildRepo();
      await expectLater(
        composer.ensureDay(DateTime(2026, 10, 11), repo),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('带时分秒的查询归一到日记日', () async {
      final provider = _CountingProvider();
      final composer = buildComposer(provider: provider);
      final repo = buildRepo();
      await composer.ensureDay(DateTime(2026, 10, 10, 15, 42), repo);
      expect(await repo.findDay(DateTime(2026, 10, 10, 1, 1)), isNotNull);
    });
  });

  group('DiaryComposer.fetchCustomPatch 容错', () {
    test('四数据键：温度/湿度/日程/天气（不带单位）', () async {
      final composer = buildComposer(provider: _CountingProvider());
      final patch = await composer.fetchCustomPatch(today);
      expect(patch, {
        'custom-iot-temp': '21',
        'custom-iot-humidity': '45',
        'custom-schedule-count': '3',
        'custom-weather': '多云',
      });
    });

    test('部分源缺失：仅对应键为 null，其余键正常', () async {
      final composer = buildComposer(
        provider: _CountingProvider()
          ..env = null
          ..weather = null,
      );
      final patch = await composer.fetchCustomPatch(today);
      expect(patch['custom-iot-temp'], isNull);
      expect(patch['custom-iot-humidity'], isNull);
      expect(patch['custom-schedule-count'], '3');
      expect(patch['custom-weather'], isNull);
    });

    test('单源抛异常：只有该键为 null，其余键正常（不连坐）', () async {
      final composer = buildComposer(provider: _WeatherThrowsProvider());
      final patch = await composer.fetchCustomPatch(today);
      expect(patch['custom-weather'], isNull);
      expect(patch['custom-iot-temp'], '21');
      expect(patch['custom-iot-humidity'], '45');
      expect(patch['custom-schedule-count'], '3');
    });

    test('weather 为空白串：该键判 null（调用方删键）', () async {
      final composer = buildComposer(
        provider: _CountingProvider()..weather = '   ',
      );
      final patch = await composer.fetchCustomPatch(today);
      expect(patch['custom-weather'], isNull);
      expect(patch['custom-iot-temp'], '21');
    });

    test('全源异常：四键全 null（互不连坐、不抛）', () async {
      final composer = buildComposer(
        provider: FakeDiaryDataProvider(throwOnCall: StateError('iot down')),
      );
      final patch = await composer.fetchCustomPatch(today);
      expect(patch.values, everyElement(isNull));
    });

    test('全源异常成稿：概述段 + 空正文段骨架，文档无 custom-* 数据键', () async {
      final composer = buildComposer(
        provider: FakeDiaryDataProvider(throwOnCall: StateError('down')),
      );
      final doc = await composer.ensureDay(today, buildRepo());
      expect(doc.blocks, hasLength(2));
      expect(doc.blocks.every((b) => b.text.isEmpty), isTrue);
      expect(doc.custom, isEmpty);
    });

    test('刷新结果带移除语义（上次有值、本次源返回 null）', () async {
      final provider = _CountingProvider();
      final composer = buildComposer(provider: provider);
      final first = await composer.fetchCustomPatch(today);
      expect(first['custom-weather'], '多云');
      provider.weather = null;
      final second = await composer.fetchCustomPatch(today);
      expect(second['custom-weather'], isNull);
    });
  });

  group('DiaryComposer.isUserEmpty 清理判定', () {
    late DiaryComposer composer;
    setUp(() {
      composer = buildComposer(provider: _CountingProvider());
    });

    test('刚成稿（单空段 + custom-* 数据）判为空', () async {
      final doc = await composer.ensureDay(today, buildRepo());
      expect(doc.custom, isNotEmpty); // 数据在文档根，不占块。
      expect(composer.isUserEmpty(doc), isTrue);
    });

    test('磁盘往返后 custom-* 与骨架（概述段+空正文段）保持一致，仍判空', () async {
      final doc = await composer.ensureDay(today, buildRepo());
      final restored = const SySerializer()
          .decodeBytes(const SySerializer().encodeBytes(doc))
          .document;
      expect(restored.blocks, hasLength(2));
      expect(restored.blocks.first.background, DiaryComposer.summaryBackground);
      expect(restored.blocks.every((b) => b.text.isEmpty), isTrue);
      expect(restored.custom['custom-iot-temp'], '21');
      expect(composer.isUserEmpty(restored), isTrue);
    });

    test('磁盘往返：用户写过字的稿仍判非空', () async {
      final doc = await composer.ensureDay(today, buildRepo());
      doc.blocks.first.text = '今天写了一句';
      final restored = const SySerializer()
          .decodeBytes(const SySerializer().encodeBytes(doc))
          .document;
      expect(composer.isUserEmpty(restored), isFalse);
    });

    test('写过字判为非空', () {
      final doc = DailyDefaultTemplate(spec: DiaryTemplateSpec.fromJson(_json))
          .instantiate(today, SyIdGenerator(random: Random(1)));
      doc.blocks.first.text = '写了一句今天的事';
      expect(composer.isUserEmpty(doc), isFalse);
    });

    test('写了字又删光判为空（次日可清）', () {
      final doc = DailyDefaultTemplate(spec: DiaryTemplateSpec.fromJson(_json))
          .instantiate(today, SyIdGenerator(random: Random(1)));
      doc.blocks.first.text = '   ';
      expect(composer.isUserEmpty(doc), isTrue);
    });

    test('仅多拆了空块仍判为空', () {
      final doc = DailyDefaultTemplate(spec: DiaryTemplateSpec.fromJson(_json))
          .instantiate(today, SyIdGenerator(random: Random(1)));
      doc.blocks.add(
        DiaryBlock(id: SyIdGenerator(random: Random(2)).next(), text: ''),
      );
      expect(composer.isUserEmpty(doc), isTrue);
    });

    test('骨架空段被删掉仍判为空', () {
      final doc = DailyDefaultTemplate(spec: DiaryTemplateSpec.fromJson(_json))
          .instantiate(today, SyIdGenerator(random: Random(1)));
      doc.blocks.clear();
      expect(composer.isUserEmpty(doc), isTrue);
    });

    test('在任意新增块里写了字判为非空', () {
      final doc = DailyDefaultTemplate(spec: DiaryTemplateSpec.fromJson(_json))
          .instantiate(today, SyIdGenerator(random: Random(1)));
      doc.blocks.add(
        DiaryBlock(
          id: SyIdGenerator(random: Random(2)).next(),
          text: '补一句',
        ),
      );
      expect(composer.isUserEmpty(doc), isFalse);
    });
  });

  group('成稿序列化落在金标准子集内', () {
    test('概述段+空段编码为 NodeParagraph：概述段带 12 号底色、无超级块', () async {
      final composer = buildComposer(provider: _CountingProvider());
      final doc = await composer.ensureDay(today, buildRepo());
      final json = const SySerializer().encodeJson(doc);

      expect(json, contains('NodeParagraph'));
      expect(json, contains('var(--b3-font-background12)'));
      expect(json, isNot(contains('NodeSuperBlock')));
      expect(json, isNot(contains('custom-echo-stamp')));
      expect(json, contains('custom-iot-temp'));
      expect(json, contains('custom-schedule-count'));

      final decoded = const SySerializer().decode(json);
      expect(decoded.skippedTypes, isEmpty);
      expect(decoded.document.custom['custom-weather'], '多云');
      expect(decoded.document.blocks, hasLength(2));
      expect(decoded.document.blocks.first.background, 12);
      expect(decoded.document.blocks.last.kind, DiaryBlockKind.paragraph);
    });
  });

  group('DiaryComposer.ensureStamp 时间戳段（30 分钟规则）', () {
    late DateTime nowValue;

    DiaryComposer stampComposer() => DiaryComposer(
      template: DailyDefaultTemplate(spec: DiaryTemplateSpec.fromJson(_json)),
      provider: _CountingProvider(),
      idGenerator: SyIdGenerator(random: Random(3), now: () => nowValue),
      now: () => nowValue,
    );

    /// 「一句话概述今日」段（12 号底色，恒在文档首位）。
    DiaryBlock summaryBlock(String id) =>
        DiaryBlock(id: id, background: DiaryComposer.summaryBackground);

    DiaryDocument buildDoc({List<DiaryBlock>? blocks}) => DiaryDocument(
      id: SyIdGenerator.dayContainer(DateTime(2026, 10, 18)),
      date: DateTime(2026, 10, 18),
      title: '10月18日 周日',
      blocks:
          blocks ??
          [
            summaryBlock('20261018080000-zzzzzz1'),
            DiaryBlock(id: '20261018080000-aaaaaaa'),
          ],
      updatedAt: DateTime(2026, 10, 18, 8),
    );

    DiaryBlock stampBlock(DateTime at, String id) => DiaryBlock(
      id: id,
      text: '2026-10-18 10:00',
      custom: {kEchoStampAttr: '1'},
      updatedAt: at,
    );

    setUp(() => nowValue = DateTime(2026, 10, 18, 10, 0));

    test('无时间戳：概述段后插时间戳，文本 yyyy-MM-dd HH:mm，带 custom 标志，保留正文行', () {
      final composer = stampComposer();
      final doc = buildDoc();

      expect(composer.ensureStamp(doc), isTrue);

      expect(doc.blocks, hasLength(3));
      // 概述段恒在首位（非时间戳）。
      expect(doc.blocks[0].background, DiaryComposer.summaryBackground);
      expect(doc.blocks[0].isStamp, isFalse);
      // 时间戳紧随概述段。
      final stamp = doc.blocks[1];
      expect(stamp.isStamp, isTrue);
      expect(stamp.text, '2026-10-18 10:00');
      expect(stamp.custom[kEchoStampAttr], '1');
      // 模板原有空段落落在时间戳之后，成为本段正文行。
      expect(doc.blocks[2].isStamp, isFalse);
      expect(doc.blocks[2].text, isEmpty);
    });

    test('旧稿缺概述段：复用时间戳时补建概述段并返回 true（不新建时间戳）', () {
      final composer = stampComposer();
      final doc = buildDoc(
        blocks: [
          stampBlock(DateTime(2026, 10, 18, 10, 0), '20261018100000-ssssss7'),
          DiaryBlock(id: '20261018100001-hhhhhhh', text: '正文'),
        ],
      );
      nowValue = DateTime(2026, 10, 18, 10, 10); // 距上次 10 分钟：复用

      expect(composer.ensureStamp(doc), isTrue);
      expect(doc.blocks.first.background, DiaryComposer.summaryBackground);
      expect(doc.blocks.where((b) => b.isStamp), hasLength(1));
    });

    test('距上次 < 30 分钟：复用不新建，返回 false 且文档不变', () {
      final composer = stampComposer();
      final doc = buildDoc(
        blocks: [
          summaryBlock('20261018080000-zzzzzz2'),
          stampBlock(DateTime(2026, 10, 18, 10, 0), '20261018100000-ssssss1'),
          DiaryBlock(id: '20261018100001-bbbbbbb', text: '正文'),
        ],
      );
      nowValue = DateTime(2026, 10, 18, 10, 29);

      expect(composer.ensureStamp(doc), isFalse);
      expect(doc.blocks, hasLength(3));
      expect(doc.blocks.where((b) => b.isStamp), hasLength(1));
    });

    test('距上次恰好 30 分钟：阈值含边界，新建新段并补空正文行', () {
      final composer = stampComposer();
      final doc = buildDoc(
        blocks: [
          summaryBlock('20261018080000-zzzzzz3'),
          stampBlock(DateTime(2026, 10, 18, 10, 0), '20261018100000-ssssss2'),
          DiaryBlock(id: '20261018100001-ddddddd', text: '正文'),
        ],
      );
      nowValue = DateTime(2026, 10, 18, 10, 30);

      expect(composer.ensureStamp(doc), isTrue);
      expect(doc.blocks, hasLength(5));
      final newStamp = doc.blocks[3];
      expect(newStamp.isStamp, isTrue);
      expect(newStamp.text, '2026-10-18 10:30');
      expect(doc.blocks[4].isStamp, isFalse);
      expect(doc.blocks[4].text, isEmpty);
    });

    test('已导出（locked）文档：不生成时间戳，返回 false', () {
      final composer = stampComposer();
      final doc = buildDoc()..locked = true;

      expect(composer.ensureStamp(doc), isFalse);
      expect(doc.blocks.any((b) => b.isStamp), isFalse);
    });

    test('isUserEmpty：自动时间戳不参与「是否写了字」判定', () {
      final composer = stampComposer();
      final empty = buildDoc(
        blocks: [
          stampBlock(DateTime(2026, 10, 18, 10, 0), '20261018100000-ssssss3'),
          DiaryBlock(id: '20261018100001-eeeeeee', text: ''),
        ],
      );
      expect(composer.isUserEmpty(empty), isTrue);

      final written = buildDoc(
        blocks: [
          stampBlock(DateTime(2026, 10, 18, 10, 0), '20261018100000-ssssss4'),
          DiaryBlock(id: '20261018100001-fffffff', text: '写了一句'),
        ],
      );
      expect(composer.isUserEmpty(written), isFalse);
    });

    test('previewOf：列表预览跳过时间戳，取第一段用户文字', () {
      final doc = buildDoc(
        blocks: [
          stampBlock(DateTime(2026, 10, 18, 10, 0), '20261018100000-ssssss5'),
          DiaryBlock(id: '20261018100001-ggggggg', text: '今天的第一句'),
        ],
      );
      expect(DiaryDaySummary.previewOf(doc), '今天的第一句');
      // 只有时间戳、无正文时预览为空串（不把时间戳当摘要）。
      final stampOnly = buildDoc(
        blocks: [
          stampBlock(DateTime(2026, 10, 18, 10, 0), '20261018100000-ssssss6'),
        ],
      );
      expect(DiaryDaySummary.previewOf(stampOnly), isEmpty);
    });
  });
}
