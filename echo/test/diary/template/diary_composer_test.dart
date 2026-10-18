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
  "id": "daily-default-v2",
  "blocks": [
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
    test('空日成稿：单空段骨架 + 四个 custom-* + 立即落盘', () async {
      final provider = _CountingProvider();
      final composer = buildComposer(provider: provider);
      final repo = buildRepo();

      final doc = await composer.ensureDay(today, repo);

      expect(doc.blocks, hasLength(1));
      expect(doc.blocks.single.kind, DiaryBlockKind.paragraph);
      expect(doc.blocks.single.text, isEmpty);

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

    test('全源异常成稿：单空段骨架，文档无 custom-* 数据键', () async {
      final composer = buildComposer(
        provider: FakeDiaryDataProvider(throwOnCall: StateError('down')),
      );
      final doc = await composer.ensureDay(today, buildRepo());
      expect(doc.blocks, hasLength(1));
      expect(doc.blocks.single.text, isEmpty);
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

    test('磁盘往返后 custom-* 与单空段骨架保持一致，仍判空', () async {
      final doc = await composer.ensureDay(today, buildRepo());
      final restored = const SySerializer()
          .decodeBytes(const SySerializer().encodeBytes(doc))
          .document;
      expect(restored.blocks, hasLength(1));
      expect(restored.blocks.single.text, isEmpty);
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
    test('单空段编码为 NodeParagraph，custom 仅四数据键、骨架无底色', () async {
      final composer = buildComposer(provider: _CountingProvider());
      final doc = await composer.ensureDay(today, buildRepo());
      final json = const SySerializer().encodeJson(doc);

      expect(json, contains('NodeParagraph'));
      expect(json, isNot(contains('var(--b3-font-background')));
      expect(json, isNot(contains('custom-echo')));
      expect(json, contains('custom-iot-temp'));
      expect(json, contains('custom-schedule-count'));

      final decoded = const SySerializer().decode(json);
      expect(decoded.skippedTypes, isEmpty);
      expect(decoded.document.custom['custom-weather'], '多云');
      expect(decoded.document.blocks, hasLength(1));
      expect(decoded.document.blocks.single.kind, DiaryBlockKind.paragraph);
    });
  });
}
