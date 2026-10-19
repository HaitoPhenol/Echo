import 'package:flutter/scheduler.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:echo/src/control/protocol/control_error.dart';
import 'package:echo/src/diary/data/diary_repository.dart';
import 'package:echo/src/diary/diary_navigator.dart';
import 'package:echo/src/diary/sy/sy_id.dart';
import 'package:echo/src/navigation/nav_physics.dart';

import 'control_test_harness.dart';

/// P5｜ECP 笔记页功能：内层导航（`diary.goto`）、精确导出
/// （`diary.export --date`）、恢复导出状态（`diary.state.set`）、
/// 内容读写（`diary.block.set` / `diary.document.set` / `diary.custom.set`）。
///
/// 命令运行在 widget 树外，本组用**记录型假导航器**替代真实
/// DiaryPageState（机制断言到「命令调了哪一个 showX 方法」即可，
/// 真实栈行为由 UI 测试覆盖）。
void main() {
  late ControlHarness h;
  late _RecordingNavigator nav;

  setUp(() async {
    h = await ControlHarness.create(startTime: DateTime(2026, 10, 12, 10));
    nav = _RecordingNavigator();
    h.registry.set<DiaryNavigatorController>(nav);
  });
  tearDown(() => h.dispose());

  group('diary.goto', () {
    test('--date 直达该日编辑页', () async {
      final r = await h.execResult(
        'diary.goto',
        args: {'date': '2026-10-11'},
      );
      expect(r['page'], 'notes');
      expect(r['level'], 'editor');
      expect(r['date'], '2026-10-11');
      expect(nav.calls, ['editor:2026-10-11']);
    });

    test('--date 未来日拒绝（USAGE）；与 --level 互斥', () async {
      expect(
        (await h.exec(
          'diary.goto',
          args: {'date': '2026-10-13'},
        )).error!.code,
        ControlErrorCode.usage,
      );
      expect(
        (await h.exec(
          'diary.goto',
          args: {'date': '2026-10-11', 'level': 'month'},
        )).error!.code,
        ControlErrorCode.usage,
      );
      expect(nav.calls, isEmpty);
    });

    test('--level 各层级驱动对应栈操作', () async {
      await h.execResult('diary.goto', args: {'level': 'year'});
      await h.execResult(
        'diary.goto',
        args: {'level': 'month', 'year': 2026},
      );
      await h.execResult(
        'diary.goto',
        args: {'level': 'day', 'year': 2026, 'month': 10},
      );
      await h.execResult(
        'diary.goto',
        args: {'level': 'editor', 'year': 2026, 'month': 10, 'day': 11},
      );
      expect(nav.calls, [
        'year',
        'month:2026',
        'day:2026-10',
        'editor:2026-10-11',
      ]);
      // 缺省无 --date 时 = year。
      nav.calls.clear();
      await h.execResult('diary.goto');
      expect(nav.calls, ['year']);
    });

    test('参数缺失/非法分级与未来年份拒绝', () async {
      // level=month 缺 year。
      expect(
        (await h.exec('diary.goto', args: {'level': 'month'})).error!.code,
        ControlErrorCode.usage,
      );
      // 未知 level。
      expect(
        (await h.exec('diary.goto', args: {'level': 'bogus'})).error!.code,
        ControlErrorCode.usage,
      );
      // 非法日期组合 02-31。
      expect(
        (await h.exec(
          'diary.goto',
          args: {'level': 'editor', 'year': 2026, 'month': 2, 'day': 31},
        )).error!.code,
        ControlErrorCode.usage,
      );
      // 未来年份。
      expect(
        (await h.exec('diary.goto', args: {'level': 'month', 'year': 2027}))
            .error!
            .code,
        ControlErrorCode.usage,
      );
      expect(nav.calls, isEmpty);
    });

    test('顶层导航已注册时先 snap 到 notes', () async {
      final physics = NavPhysicsController(
        vsync: const _Ticker(),
        pageCount: 4,
      );
      h.registry.set(physics);
      await h.execResult('diary.goto', args: {'date': '2026-10-11'});
      // snapTo 生效不抛错、内层栈照常驱动（真实吸附动画由 nav 测试覆盖）。
      expect(nav.calls, ['editor:2026-10-11']);
    });

    test('笔记页未装配时 requireService 报 CONFLICT', () async {
      final fresh = await ControlHarness.create();
      addTearDown(fresh.dispose);
      final env = await fresh.exec(
        'diary.goto',
        args: {'date': '2026-10-11'},
      );
      expect(env.error!.code, ControlErrorCode.conflict);
    });
  });

  group('diary.export --date', () {
    test('按日打包 scope 命中该日', () async {
      await h.execResult('diary.ensure', args: {'date': '2026-10-10'});
      final r = await h.execResult(
        'diary.export',
        args: {'date': '2026-10-10'},
      );
      expect(r['entries'], greaterThanOrEqualTo(1));
      expect((r['path'] as String).contains('2026-10-10'), isTrue);
      expect((r['path'] as String).endsWith('.sy.zip'), isTrue);
    });

    test('无 draft 的日抛 EXPORT_EMPTY', () async {
      final env = await h.exec(
        'diary.export',
        args: {'date': '2020-01-01'},
      );
      expect(env.error!.code, ControlErrorCode.exportEmpty);
    });

    test('--date 与 --year 互斥（USAGE）', () async {
      expect(
        (await h.exec(
          'diary.export',
          args: {'date': '2026-10-10', 'year': 2026},
        )).error!.code,
        ControlErrorCode.usage,
      );
    });
  });

  group('diary.state.set', () {
    setUp(() async {
      await h.execResult('diary.ensure', args: {'date': '2026-10-10'});
    });

    test('draft→exported→draft（恢复导出状态）全链路', () async {
      final toExported = await h.execResult(
        'diary.state.set',
        args: {'date': '2026-10-10', 'state': 'exported'},
      );
      expect(toExported['from'], 'draft');
      expect(toExported['to'], 'exported');
      expect(
        await h.repo.stateOfDay(DateTime(2026, 10, 10)),
        DiaryDocState.exported,
      );
      // 已 exported 再标 exported：非法迁移 CONFLICT。
      expect(
        (await h.exec(
          'diary.state.set',
          args: {'date': '2026-10-10', 'state': 'exported'},
        )).error!.code,
        ControlErrorCode.conflict,
      );

      final restored = await h.execResult(
        'diary.state.set',
        args: {'date': '2026-10-10', 'state': 'draft'},
      );
      expect(restored['from'], 'exported');
      expect(restored['to'], 'draft');
      expect(
        await h.repo.stateOfDay(DateTime(2026, 10, 10)),
        DiaryDocState.draft,
      );
      // 已在 draft 再恢复：CONFLICT（仅 exported 可恢复）。
      expect(
        (await h.exec(
          'diary.state.set',
          args: {'date': '2026-10-10', 'state': 'draft'},
        )).error!.code,
        ControlErrorCode.conflict,
      );
    });

    test('目标不存在 NOT_FOUND；未知状态 USAGE', () async {
      expect(
        (await h.exec(
          'diary.state.set',
          args: {'date': '2020-01-01', 'state': 'draft'},
        )).error!.code,
        ControlErrorCode.notFound,
      );
      expect(
        (await h.exec(
          'diary.state.set',
          args: {'date': '2026-10-10', 'state': 'archived'},
        )).error!.code,
        ControlErrorCode.usage,
      );
    });
  });

  group('diary.block.set', () {
    late String day;
    late Map<String, Object?> doc;

    setUp(() async {
      day = '2026-10-10';
      await h.execResult('diary.ensure', args: {'date': day});
      doc = await h.execResult('diary.get', args: {'date': day});
    });

    test('带 id 就地补丁 text / background', () async {
      final blocks = (doc['blocks'] as List).cast<Map<String, Object?>>();
      final target = blocks.first;
      final id = target['id'] as String;

      final r = await h.execResult(
        'diary.block.set',
        args: {
          'date': day,
          'json': '{"id":"$id","text":"改了字","background":4}',
        },
      );
      final updated = (r['blocks'] as List)
          .cast<Map<String, Object?>>()
          .firstWhere((b) => b['id'] == id);
      expect(updated['text'], '改了字');
      expect(updated['background'], 4);
    });

    test('无 id 追加新块 / 带 index 插入', () async {
      final before = (doc['blocks'] as List).length;
      final appended = await h.execResult(
        'diary.block.set',
        args: {
          'date': day,
          'json': '{"kind":"heading","level":2,"text":"小标题"}',
        },
      );
      final afterAppend = (appended['blocks'] as List)
          .cast<Map<String, Object?>>();
      expect(afterAppend.length, before + 1);
      final last = afterAppend.last;
      expect(last['kind'], 'heading');
      expect(last['level'], 2);
      expect(last['text'], '小标题');

      final inserted = await h.execResult(
        'diary.block.set',
        args: {
          'date': day,
          'json': '{"index":0,"text":"插到最前"}',
        },
      );
      expect(
        ((inserted['blocks'] as List).first as Map)['text'],
        '插到最前',
      );
    });

    test('块不存在 NOT_FOUND；非法 JSON/底色 USAGE', () async {
      expect(
        (await h.exec(
          'diary.block.set',
          args: {'date': day, 'json': '{"id":"nope","text":"x"}'},
        )).error!.code,
        ControlErrorCode.notFound,
      );
      expect(
        (await h.exec(
          'diary.block.set',
          args: {'date': day, 'json': 'not-json'},
        )).error!.code,
        ControlErrorCode.usage,
      );
      final blocks = (doc['blocks'] as List).cast<Map<String, Object?>>();
      final id = blocks.first['id'] as String;
      expect(
        (await h.exec(
          'diary.block.set',
          args: {'date': day, 'json': '{"id":"$id","background":99}'},
        )).error!.code,
        ControlErrorCode.usage,
      );
    });

    test('exported 态只读 CONFLICT', () async {
      await h.execResult(
        'diary.state.set',
        args: {'date': day, 'state': 'exported'},
      );
      final blocks = (doc['blocks'] as List).cast<Map<String, Object?>>();
      final id = blocks.first['id'] as String;
      expect(
        (await h.exec(
          'diary.block.set',
          args: {'date': day, 'json': '{"id":"$id","text":"x"}'},
        )).error!.code,
        ControlErrorCode.conflict,
      );
    });
  });

  group('diary.document.set', () {
    test('整体替换 blocks + title（id 缺省自动生成）', () async {
      const day = '2026-10-10';
      await h.execResult('diary.ensure', args: {'date': day});
      final r = await h.execResult(
        'diary.document.set',
        args: {
          'date': day,
          'json':
              '{"title":"新标题","blocks":['
              '{"text":"A"},'
              '{"kind":"heading","level":3,"text":"B"}]}',
        },
      );
      expect(r['title'], '新标题');
      final blocks = (r['blocks'] as List).cast<Map<String, Object?>>();
      expect(blocks.length, 2);
      for (final b in blocks) {
        expect(SyIdGenerator.isValid(b['id'] as String), isTrue);
      }
      expect(blocks[1]['kind'], 'heading');
      expect(blocks[1]['level'], 3);
    });

    test('id 非法 USAGE；custom 一并合并；非对象 USAGE', () async {
      const day = '2026-10-10';
      await h.execResult('diary.ensure', args: {'date': day});
      expect(
        (await h.exec(
          'diary.document.set',
          args: {
            'date': day,
            'json': '{"blocks":[{"id":"bad-id","text":"x"}]}',
          },
        )).error!.code,
        ControlErrorCode.usage,
      );
      expect(
        (await h.exec('diary.document.set', args: {'date': day, 'json': '[]'}))
            .error!
            .code,
        ControlErrorCode.usage,
      );

      final r = await h.execResult(
        'diary.document.set',
        args: {
          'date': day,
          'json': '{"custom":{"custom-mood":"🙂"}}',
        },
      );
      expect((r['custom'] as Map)['custom-mood'], '🙂');
    });
  });

  group('diary.custom.set', () {
    const day = '2026-10-10';

    setUp(() async {
      await h.execResult('diary.ensure', args: {'date': day});
    });

    test('合并新增 / null 删键', () async {
      final add = await h.execResult(
        'diary.custom.set',
        args: {
          'date': day,
          'json': '{"custom-mood":"🙂","custom-temp":25,"custom-flag":true}',
        },
      );
      final custom = add['custom'] as Map;
      expect(custom['custom-mood'], '🙂');
      expect(custom['custom-temp'], '25'); // 数字转字符串落库
      expect(custom['custom-flag'], 'true');

      final del = await h.execResult(
        'diary.custom.set',
        args: {'date': day, 'json': '{"custom-mood":null}'},
      );
      expect((del['custom'] as Map).containsKey('custom-mood'), isFalse);
      expect((del['custom'] as Map)['custom-temp'], '25');
    });

    test('键前缀非法 / 值类型非法 USAGE', () async {
      expect(
        (await h.exec(
          'diary.custom.set',
          args: {'date': day, 'json': '{"mood":"🙂"}'},
        )).error!.code,
        ControlErrorCode.usage,
      );
      expect(
        (await h.exec(
          'diary.custom.set',
          args: {'date': day, 'json': '{"custom-x":{"a":1}}'},
        )).error!.code,
        ControlErrorCode.usage,
      );
    });
  });

  group('审计脱敏', () {
    test('block.set 的 --json 不入审计正文（只记长度）', () async {
      const day = '2026-10-10';
      await h.execResult('diary.ensure', args: {'date': day});
      final doc = await h.execResult('diary.get', args: {'date': day});
      final id = ((doc['blocks'] as List).first as Map)['id'] as String;
      const secret = '这是绝不能进审计的正文';

      await h.execResult(
        'diary.block.set',
        args: {'date': day, 'json': '{"id":"$id","text":"$secret"}'},
      );

      final entry = h.audit.list().firstWhere(
        (e) => e.cmd == 'diary.block.set',
      );
      final summary = entry.paramSummary['json'].toString();
      expect(summary.contains(secret), isFalse);
      expect(summary.startsWith('<redacted:'), isTrue);
    });
  });
}

/// 记录型假导航器：只记「命令调了哪一个 showX」，不驱动真实路由栈。
class _RecordingNavigator implements DiaryNavigatorController {
  final List<String> calls = [];

  @override
  Future<void> showYearList() async => calls.add('year');

  @override
  Future<void> showMonthList(int year) async => calls.add('month:$year');

  @override
  Future<void> showDayList(int year, int month) async =>
      calls.add('day:$year-$month');

  @override
  Future<void> showEditor(DateTime date) async =>
      calls.add('editor:${date.year}-${date.month}-${date.day}');
}

class _Ticker implements TickerProvider {
  const _Ticker();

  @override
  Ticker createTicker(TickerCallback onTick) => Ticker(onTick);
}
