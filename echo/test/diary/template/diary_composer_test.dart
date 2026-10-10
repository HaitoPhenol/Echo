import 'dart:math';

import 'package:echo/src/diary/data/diary_clock.dart';
import 'package:echo/src/diary/data/diary_data_provider.dart';
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
  "id": "daily-default-v1",
  "blocks": [
    { "type": "heading", "level": 2, "text": "📈 自动记录" },
    { "type": "data", "role": 1, "placeholder": "数据暂不可用，点 ↻ 重试" },
    { "type": "heading", "level": 2, "text": "💭 今天" },
    { "type": "paragraph" },
    { "type": "heading", "level": 2, "text": "🌙 睡前" },
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
  bool get isSampleData => true;

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
    test('空日成稿：六块骨架 + 快照文本 + 四个 custom + 立即落盘', () async {
      final provider = _CountingProvider();
      final composer = buildComposer(provider: provider);
      final repo = buildRepo();

      final doc = await composer.ensureDay(today, repo);

      expect(doc.blocks, hasLength(6));
      final data = doc.blocks[1];
      expect(SyIdGenerator.isDataBlockId(data.id), isTrue);
      expect(data.readonly, isTrue);
      expect(data.background, 3);
      expect(
        data.text,
        '🌡️ 21°C　💧 45%　📅 3 条日程　☁️ 多云　（示例数据）',
      );

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
      final provider = _CountingProvider(delay: const Duration(milliseconds: 30));
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

  group('DiaryComposer.fetchSnapshot 容错', () {
    test('部分源缺失：省略片段，对应 custom 键不写', () async {
      final composer = buildComposer(
        provider: _CountingProvider()
          ..env = null
          ..weather = null,
      );
      final r = await composer.fetchSnapshot(today);
      expect(r.text, '📅 3 条日程　（示例数据）');
      expect(r.customPatch['custom-iot-temp'], isNull);
      expect(r.customPatch['custom-iot-humidity'], isNull);
      expect(r.customPatch['custom-schedule-count'], '3');
      expect(r.customPatch['custom-weather'], isNull);
    });

    test('全源异常：占位文案 + 全 null patch', () async {
      final composer = buildComposer(
        provider: FakeDiaryDataProvider(throwOnCall: StateError('iot down')),
      );
      final r = await composer.fetchSnapshot(today);
      expect(r.text, '数据暂不可用，点 ↻ 重试');
      expect(r.customPatch.values, everyElement(isNull));
    });

    test('全源异常成稿：data 块落占位文案，文档无 custom-* 数据键',
        () async {
      final composer = buildComposer(
        provider: FakeDiaryDataProvider(throwOnCall: StateError('down')),
      );
      final doc = await composer.ensureDay(today, buildRepo());
      expect(doc.blocks[1].text, '数据暂不可用，点 ↻ 重试');
      expect(doc.custom, isEmpty);
    });

    test('刷新结果带移除语义（上次有值、本次源返回 null）', () async {
      final provider = _CountingProvider();
      final composer = buildComposer(provider: provider);
      final first = await composer.fetchSnapshot(today);
      expect(first.customPatch['custom-weather'], '多云');
      provider.weather = null;
      final second = await composer.fetchSnapshot(today);
      expect(second.customPatch['custom-weather'], isNull);
      expect(second.text, isNot(contains('☁️')));
    });
  });

  group('DiaryComposer.isUserEmpty 清理判定', () {
    late DiaryComposer composer;
    setUp(() {
      composer = buildComposer(provider: _CountingProvider());
    });

    test('刚成稿（含已填 data 快照）判为空', () async {
      final doc = await composer.ensureDay(today, buildRepo());
      expect(composer.isUserEmpty(doc), isTrue);
    });

    test('写过字判为非空', () {
      final doc = DailyDefaultTemplate(
        spec: DiaryTemplateSpec.fromJson(_json),
      ).instantiate(today, SyIdGenerator(random: Random(1)));
      doc.blocks[3].text = '写了一句今天的事';
      expect(composer.isUserEmpty(doc), isFalse);
    });

    test('写了字又删光判为空（次日可清）', () {
      final doc = DailyDefaultTemplate(
        spec: DiaryTemplateSpec.fromJson(_json),
      ).instantiate(today, SyIdGenerator(random: Random(1)));
      doc.blocks[3].text = '   ';
      expect(composer.isUserEmpty(doc), isTrue);
    });

    test('仅多拆了空块仍判为空', () {
      final doc = DailyDefaultTemplate(
        spec: DiaryTemplateSpec.fromJson(_json),
      ).instantiate(today, SyIdGenerator(random: Random(1)));
      doc.blocks.add(DiaryBlock(
        id: SyIdGenerator(random: Random(2)).next(),
        text: '',
      ));
      expect(composer.isUserEmpty(doc), isTrue);
    });

    test('删掉一个标题但无文字仍判为空', () {
      final doc = DailyDefaultTemplate(
        spec: DiaryTemplateSpec.fromJson(_json),
      ).instantiate(today, SyIdGenerator(random: Random(1)));
      doc.blocks.removeAt(4); // 🌙 睡前标题
      expect(composer.isUserEmpty(doc), isTrue);
    });

    test('在任意新增块里写了字判为非空', () {
      final doc = DailyDefaultTemplate(
        spec: DiaryTemplateSpec.fromJson(_json),
      ).instantiate(today, SyIdGenerator(random: Random(1)));
      doc.blocks.add(DiaryBlock(
        id: SyIdGenerator(random: Random(2)).next(),
        text: '补一句',
      ));
      expect(composer.isUserEmpty(doc), isFalse);
    });
  });

  group('成稿序列化落在金标准子集内', () {
    test('data 块编码为 background=3 段落，custom 仅四数据键', () async {
      final composer = buildComposer(provider: _CountingProvider());
      final doc = await composer.ensureDay(today, buildRepo());
      final json = const SySerializer().encodeJson(doc);

      expect(json, contains('NodeParagraph'));
      expect(json, contains('var(--b3-font-background3)'));
      expect(json, isNot(contains('custom-echo')));
      expect(json, contains('custom-iot-temp'));
      expect(json, contains('custom-schedule-count'));

      final decoded = const SySerializer().decode(json);
      expect(decoded.skippedTypes, isEmpty);
      expect(decoded.document.custom['custom-weather'], '多云');
      final data = decoded.document.blocks
          .firstWhere((b) => SyIdGenerator.isDataBlockId(b.id));
      expect(data.kind, DiaryBlockKind.paragraph);
      expect(data.background, 3);
    });
  });
}
