import 'package:echo/src/services/console_stats_service.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ConsoleStatsService', () {
    test('refresh 解析通道 map 为快照并通知', () async {
      var calls = 0;
      final service = ConsoleStatsService(
        autoStart: false,
        reader: () async {
          calls++;
          return {'model': 'MIX 2S', 'tempC': 29.0, 'powerW': 2.9};
        },
      );
      addTearDown(service.dispose);

      var notified = 0;
      service.addListener(() => notified++);

      final s = await service.refresh();
      expect(s.model, 'MIX 2S');
      expect(s.tempC, 29.0);
      expect(s.powerW, 2.9);
      expect(service.snapshot, s);
      expect(notified, 1);
      expect(calls, 1);
    });

    test('缺字段/空 map 降级为 — 与 null', () async {
      final service = ConsoleStatsService(
        autoStart: false,
        reader: () async => {'tempC': 30},
      );
      addTearDown(service.dispose);

      final s = await service.refresh();
      expect(s.model, '—');
      expect(s.tempC, 30);
      expect(s.powerW, isNull);
      expect(s.toJson(), {'model': '—', 'tempC': 30, 'powerW': null});
    });

    test('相同快照不重复通知', () async {
      final service = ConsoleStatsService(
        autoStart: false,
        reader: () async => {'model': 'X', 'tempC': 1, 'powerW': 1},
      );
      addTearDown(service.dispose);
      var notified = 0;
      service.addListener(() => notified++);

      await service.refresh();
      await service.refresh();
      expect(notified, 1);
    });

    test('并发 refresh 共享同一次通道调用', () async {
      var calls = 0;
      final service = ConsoleStatsService(
        autoStart: false,
        reader: () async {
          calls++;
          await Future<void>.delayed(const Duration(milliseconds: 5));
          return {'model': 'X'};
        },
      );
      addTearDown(service.dispose);

      await Future.wait([service.refresh(), service.refresh()]);
      expect(calls, 1);
    });

    test('readRaw 直通原始 map（sys.info 同源）', () async {
      final service = ConsoleStatsService(
        autoStart: false,
        reader: () async => {
          'model': 'X',
          'osVersion': '10',
          'version': '0.10.0',
          'tempC': 29,
          'powerW': 2.9,
        },
      );
      addTearDown(service.dispose);

      final raw = await service.readRaw();
      expect(raw['version'], '0.10.0');
      expect(raw['osVersion'], '10');
    });

    test('start 后按周期轮询（fakeAsync）', () {
      fakeAsync((async) {
        var calls = 0;
        final service = ConsoleStatsService(
          pollInterval: const Duration(seconds: 5),
          reader: () async {
            calls++;
            return {'model': 'X', 'tempC': calls.toDouble()};
          },
        );
        // 构造 autoStart 已排队一次立即刷新。
        async.elapse(const Duration(milliseconds: 1));
        expect(calls, 1);
        async.elapse(const Duration(seconds: 10));
        expect(calls, 3); // 立即 1 次 + 两个周期
        async.elapse(const Duration(seconds: 5));
        expect(calls, 4);
        service.dispose();
      });
    });
  });
}
