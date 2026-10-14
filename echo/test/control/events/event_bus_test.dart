import 'package:flutter_test/flutter_test.dart';

import 'package:echo/src/control/events/event.dart';
import 'package:echo/src/control/events/event_bus.dart';
import 'package:echo/src/control/protocol/command_spec.dart';
import 'package:echo/src/control/protocol/control_error.dart';

/// P4-G0 事件核心单测（交接单 §G0 第 3 条逐条对应）：
/// seq/环、since 空洞、ceiling 过滤、types 过滤、poll 命中即返回、
/// wait 超时/提前唤醒、stream 过滤与历史不补发。
void main() {
  late ControlEventBus bus;

  setUp(() => bus = ControlEventBus());
  tearDown(() => bus.close());

  ControlEvent emitAt(
    ControlLevel level, {
    String type = 'test.event',
    int? v,
  }) {
    return bus.emit(type: type, level: level, data: {'v': ?v});
  }

  group('seq 与环形缓冲', () {
    test('seq 从 1 单调递增；toJson 形状稳定', () {
      final a = emitAt(ControlLevel.guest);
      final b = emitAt(ControlLevel.guest);
      expect(a.seq, 1);
      expect(b.seq, 2);
      expect(b.time, isA<DateTime>());
      expect(b.toJson(), {
        'seq': 2,
        'time': b.time.toIso8601String(),
        'type': 'test.event',
        'level': 0,
        'data': <String, Object?>{},
      });
      expect(bus.lastSeq, 2);
    });

    test('容量 256：超容量丢最旧，seq 不回收（出现空洞）', () async {
      for (var i = 0; i < 257; i++) {
        emitAt(ControlLevel.guest, v: i);
      }
      expect(bus.length, 256);
      expect(bus.lastSeq, 257);

      // seq 1 已被淘汰；现存最旧是 seq 2，游标 1 只返回活着的事件。
      // limit 给足整环容量（poll 默认只取 50）。
      final afterHole = await bus.poll(
        since: 1,
        ceiling: ControlLevel.admin,
        limit: 300,
      );
      expect(afterHole.first.seq, 2);
      expect(afterHole.last.seq, 257);
      expect(afterHole, hasLength(256));
    });

    test('容量构造下限 256（测试钉死）', () {
      expect(() => ControlEventBus(capacity: 255), throwsAssertionError);
    });
  });

  group('poll 过滤', () {
    test('since 空洞语义：游标落在淘汰区只返现存，不报错', () async {
      for (var i = 0; i < 300; i++) {
        emitAt(ControlLevel.guest);
      }
      final r = await bus.poll(
        since: 0,
        ceiling: ControlLevel.admin,
        limit: 300,
      );
      // 环只剩 256 条（seq 45..300）；since=0 也拿不回淘汰部分。
      expect(r, hasLength(256));
      expect(r.first.seq, 45);

      // 游标在尾：立即空集，不挂起。
      final tail = await bus.poll(
        since: bus.lastSeq,
        ceiling: ControlLevel.admin,
      );
      expect(tail, isEmpty);
    });

    test('ceiling 物理过滤：级别高于 ceiling 的事件直接消失', () async {
      emitAt(ControlLevel.guest); // 1
      emitAt(ControlLevel.owner); // 2
      emitAt(ControlLevel.user); // 3
      emitAt(ControlLevel.admin); // 4

      final ownerView = await bus.poll(since: 0, ceiling: ControlLevel.owner);
      expect(ownerView.map((e) => e.seq), [1, 2]);

      final adminView = await bus.poll(since: 0, ceiling: ControlLevel.admin);
      expect(adminView.map((e) => e.seq), [1, 2, 3, 4]);

      final guestView = await bus.poll(since: 0, ceiling: ControlLevel.guest);
      expect(guestView.map((e) => e.seq), [1]);
    });

    test('types 白名单过滤（null ＝ 全部）', () async {
      emitAt(ControlLevel.guest, type: 'audit.entry');
      emitAt(ControlLevel.guest, type: 'nav.changed');
      emitAt(ControlLevel.guest, type: 'audit.entry');

      final only = await bus.poll(
        since: 0,
        ceiling: ControlLevel.admin,
        types: {'audit.entry'},
      );
      expect(only.map((e) => e.seq), [1, 3]);

      final all = await bus.poll(since: 0, ceiling: ControlLevel.admin);
      expect(all, hasLength(3));
    });

    test('limit 默认 50 且可裁剪', () async {
      for (var i = 0; i < 60; i++) {
        emitAt(ControlLevel.guest);
      }
      expect(
        await bus.poll(since: 0, ceiling: ControlLevel.admin),
        hasLength(50),
      );
      expect(
        await bus.poll(since: 0, ceiling: ControlLevel.admin, limit: 10),
        hasLength(10),
      );
    });

    test('命中即返回：不等待、按 seq 升序', () async {
      emitAt(ControlLevel.guest);
      emitAt(ControlLevel.guest);
      // 给 wait 也必须立即回（命中优先于挂起）。
      final sw = Stopwatch()..start();
      final r = await bus.poll(
        since: 0,
        ceiling: ControlLevel.admin,
        wait: const Duration(seconds: 2),
      );
      sw.stop();
      expect(r.map((e) => e.seq), [1, 2]);
      expect(sw.elapsedMilliseconds, lessThan(500));
    });
  });

  group('poll 长轮询', () {
    test('wait 超过 8000ms 上限 → USAGE', () async {
      expect(
        () => bus.poll(
          since: 0,
          ceiling: ControlLevel.admin,
          wait: const Duration(milliseconds: 8001),
        ),
        throwsA(
          isA<ControlException>().having(
            (e) => e.code,
            'code',
            ControlErrorCode.usage,
          ),
        ),
      );
    });

    test('无事件：等到截止返回空列表', () async {
      final sw = Stopwatch()..start();
      final r = await bus.poll(
        since: bus.lastSeq,
        ceiling: ControlLevel.admin,
        wait: const Duration(milliseconds: 40),
      );
      sw.stop();
      expect(r, isEmpty);
      expect(sw.elapsedMilliseconds, greaterThanOrEqualTo(30));
    });

    test('新命中事件提前唤醒（远早于 wait 截止）', () async {
      Future<void>.delayed(const Duration(milliseconds: 30), () {
        emitAt(ControlLevel.owner);
      });
      final sw = Stopwatch()..start();
      final r = await bus.poll(
        since: bus.lastSeq,
        ceiling: ControlLevel.owner,
        wait: const Duration(seconds: 5),
      );
      sw.stop();
      expect(r, hasLength(1));
      expect(r.single.level, ControlLevel.owner);
      expect(sw.elapsedMilliseconds, lessThan(1000));
    });

    test('无权看的新事件不提前返回；命中事件随后才唤醒', () async {
      // 30ms 后来一条 admin 事件（owner ceiling 看不见），
      // 80ms 后来 owner 事件，第二次才应返回。
      Future<void>.delayed(const Duration(milliseconds: 30), () {
        emitAt(ControlLevel.admin);
      });
      Future<void>.delayed(const Duration(milliseconds: 80), () {
        emitAt(ControlLevel.owner);
      });
      final sw = Stopwatch()..start();
      final r = await bus.poll(
        since: bus.lastSeq,
        ceiling: ControlLevel.owner,
        types: {'test.event'},
        wait: const Duration(seconds: 5),
      );
      sw.stop();
      expect(r, hasLength(1));
      expect(r.single.seq, 2);
      expect(sw.elapsedMilliseconds, greaterThanOrEqualTo(60));
    });

    test('多个等待者被同一条事件同时唤醒', () async {
      Future<void>.delayed(const Duration(milliseconds: 30), () {
        emitAt(ControlLevel.guest);
      });
      final results = await Future.wait([
        bus.poll(
          since: bus.lastSeq,
          ceiling: ControlLevel.guest,
          wait: const Duration(seconds: 2),
        ),
        bus.poll(
          since: bus.lastSeq,
          ceiling: ControlLevel.guest,
          wait: const Duration(seconds: 2),
        ),
      ]);
      expect(results[0].single.seq, results[1].single.seq);
    });
  });

  group('stream 广播', () {
    test('不补历史：订阅前事件不重放；订阅后按 ceiling/types 过滤', () async {
      emitAt(ControlLevel.guest, type: 'nav.changed'); // 1：历史
      emitAt(ControlLevel.user, type: 'diary.export.completed'); // 2：历史

      final got = <ControlEvent>[];
      final sub = bus
          .stream(
            ceiling: ControlLevel.owner,
            types: {'nav.changed', 'audit.entry'},
          )
          .listen(got.add);

      emitAt(ControlLevel.guest, type: 'nav.changed'); // 3：命中
      emitAt(ControlLevel.user, type: 'diary.export.completed'); // 4：ceiling 挡住
      emitAt(ControlLevel.owner, type: 'audit.entry'); // 5：命中
      emitAt(ControlLevel.owner, type: 'chat.incoming'); // 6：types 挡住

      await Future<void>.delayed(Duration.zero);
      expect(got.map((e) => e.seq), [3, 5]);

      await sub.cancel();
    });

    test('两个独立订阅者各自收全量广播', () async {
      final a = <ControlEvent>[];
      final b = <ControlEvent>[];
      final sa = bus.stream(ceiling: ControlLevel.admin).listen(a.add);
      final sb = bus.stream(ceiling: ControlLevel.admin).listen(b.add);
      emitAt(ControlLevel.guest);
      await Future<void>.delayed(Duration.zero);
      expect(a, hasLength(1));
      expect(b, hasLength(1));
      await sa.cancel();
      await sb.cancel();
    });
  });

  group('收口', () {
    test('close 后再 emit 抛 StateError；close 幂等', () {
      bus.close();
      bus.close();
      expect(() => emitAt(ControlLevel.guest), throwsStateError);
    });

    test('data 浅不可变：emit 后外部修改入参不影响事件', () {
      final payload = {'k': 'v'};
      final e = bus.emit(type: 't', level: ControlLevel.guest, data: payload);
      payload['k'] = 'mutated';
      expect(e.data['k'], 'v');
      expect(() => e.data['x'] = 1, throwsUnsupportedError);
    });
  });
}
