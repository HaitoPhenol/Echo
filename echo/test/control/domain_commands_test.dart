import 'package:flutter/scheduler.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:echo/src/control/protocol/control_error.dart';
import 'package:echo/src/diary/data/diary_repository.dart';
import 'package:echo/src/diary/sy/diary_model.dart';
import 'package:echo/src/navigation/nav_physics.dart';

import 'control_test_harness.dart';

void main() {
  late ControlHarness h;

  setUp(() async {
    h = await ControlHarness.create(startTime: DateTime(2026, 10, 12, 10));
  });
  tearDown(() => h.dispose());

  group('sys 域', () {
    test('ping / help / info / status', () async {
      final ping = await h.execResult('sys.ping');
      expect(ping['alive'], isTrue);
      expect(ping['pid'], isA<int>());

      final help = await h.execResult('sys.help');
      final names = (help['commands'] as List).map((c) => (c as Map)['name']);
      expect(names, containsAll(['sys.ping', 'diary.list', 'nav.goto']));
      // debug-only 命令只在 debug 清单。
      expect(names, contains('sys.clock.set'));
      expect(names, contains('diary.reset'));

      final one = await h.execResult(
        'sys.help',
        args: {'command': 'diary.get'},
      );
      expect(one['name'], 'diary.get');
      expect(
        (await h.exec('sys.help', args: {'command': 'nope.x'})).error!.code,
        ControlErrorCode.notFound,
      );

      final info = await h.execResult('sys.info');
      expect(info['version'], '0.9.0');
      expect(info['flavor'], 'debug');
      expect(info['channel'], 'adb');
      expect(info['model'], 'test-phone');

      // status：导航未注册时 nav=false；日记已注册。
      final beforeNav = await h.execResult('sys.status');
      expect((beforeNav['services'] as Map)['nav'], isFalse);
      expect((beforeNav['diary'] as Map)['ready'], isTrue);
    });

    test('audit 倒序且不含正文', () async {
      final nav = NavPhysicsController(vsync: const _Ticker(), pageCount: 4);
      h.registry.set(nav);
      await h.execResult('nav.goto', args: {'page': 'notes'});
      await h.execResult('sys.audit', args: {'limit': 10});
      // 不直接断结构（审计测试在总线组已做），至少命令本身成功。
    });

    test('clock.set：拨钟/复位 + 04:00 日界，不碰墙钟', () async {
      final r = await h.execResult(
        'sys.clock.set',
        args: {'time': '2026-10-13T03:59'},
      );
      expect(r['diaryDate'], '2026-10-12');
      expect(h.clock.isOverridden, isTrue);

      // 03:59 的「今天」仍是 10-12；ensure 10-13 是未来日 → USAGE。
      expect(
        (await h.exec(
          'diary.ensure',
          args: {'date': '2026-10-13'},
        )).error!.code,
        ControlErrorCode.usage,
      );

      final created = await h.execResult(
        'diary.ensure',
        args: {'date': '2026-10-12'},
      );
      expect(created['created'], isTrue);

      // 墙钟变量未被改（拨钟只动注入值）。
      expect(h.wallTime, DateTime(2026, 10, 12, 10));

      final reset = await h.execResult('sys.clock.set', args: {'reset': true});
      expect(reset['diaryDate'], '2026-10-12');
      expect(h.clock.isOverridden, isFalse);

      // 二选一校验。
      expect(
        (await h.exec('sys.clock.set')).error!.code,
        ControlErrorCode.usage,
      );
    });
  });

  group('auth 域（总线裁决）', () {
    test('status 默认未设 PIN', () async {
      final fresh = await ControlHarness.create();
      addTearDown(fresh.dispose);
      final s = await fresh.execResult('auth.status');
      expect(s['pinSet'], isFalse);
      expect(s['level'], 2); // adb 起始 2 级
    });

    test('set-pin 首装 → unlock 全链路', () async {
      await h.execResult(
        'auth.set-pin',
        args: {'newPin': 'echo1', 'newPinConfirm': 'echo1'},
      );
      final status = await h.execResult('auth.status');
      expect(status['pinSet'], isTrue);

      expect(
        (await h.exec('auth.unlock', args: {'pin': 'bad'})).error!.code,
        ControlErrorCode.authDenied,
      );
      await h.execResult('auth.unlock', args: {'pin': 'echo1'});

      // 解锁后 3 级命令免 --confirm 之外可直接跑（dry-run）。
      final r = await h.execResult(
        'diary.prune',
        args: {'dryRun': true},
        confirmed: true,
      );
      expect(r, containsPair('dryRun', true));
    });
  });

  group('nav 域', () {
    setUp(() {
      h.registry.set(
        NavPhysicsController(vsync: const _Ticker(), pageCount: 4),
      );
    });

    test('page / goto（稳定 id 与下标）', () async {
      final page = await h.execResult('nav.page');
      expect(page, {'index': 0, 'name': 'console'});

      final toNotes = await h.execResult('nav.goto', args: {'page': 'notes'});
      expect((toNotes['to'] as Map)['name'], 'notes');
      expect((toNotes['from'] as Map)['name'], 'console');
      expect(toNotes['warnings'], isEmpty);

      await h.execResult('nav.goto', args: {'page': '0'});
      final back = await h.execResult('nav.page');
      expect(back['name'], 'console');

      expect(
        (await h.exec('nav.goto', args: {'page': 'nope'})).error!.code,
        ControlErrorCode.usage,
      );
    });
  });

  group('diary 域', () {
    test('ensure + list 倒序游标分页', () async {
      await h.execResult('diary.ensure', args: {'date': '2026-10-10'});
      await h.execResult('diary.ensure', args: {'date': '2026-10-11'});

      final month = await h.execResult(
        'diary.list',
        args: {'month': '2026-10', 'limit': 1},
      );
      final items = month['items'] as List;
      expect(items, hasLength(1));
      expect((items.single as Map)['date'], '2026-10-11');
      expect(month['hasMore'], isTrue);
      final cursor = month['cursor'];

      final page2 = await h.execResult(
        'diary.list',
        args: {'month': '2026-10', 'limit': 1, 'cursor': cursor},
      );
      expect(((page2['items'] as List).single as Map)['date'], '2026-10-10');
    });

    test('get：草稿/不存在/归档三态', () async {
      await h.execResult('diary.ensure', args: {'date': '2026-10-10'});
      final doc = await h.execResult('diary.get', args: {'date': '2026-10-10'});
      expect(doc['state'], 'draft');
      expect(doc['blocks'], isA<List>());
      // filePath 由注入的沙盒根按持久仓储同款相对规则拼出
      //（harness 设了 diaryRoot；widget 注入内存仓储时生产端会置 null）。
      expect((doc['filePath'] as String).endsWith('.sy'), isTrue);

      expect(
        (await h.exec('diary.get', args: {'date': '2020-01-01'})).error!.code,
        ControlErrorCode.notFound,
      );

      await h.repo.markExported([
        DateTime(2026, 10, 10),
      ], exportedAt: DateTime(2026, 10, 12));
      await h.repo.archiveDay(DateTime(2026, 10, 10));
      final archived = await h.execResult(
        'diary.get',
        args: {'date': '2026-10-10'},
      );
      expect(archived['state'], 'archived');
      expect(archived['blocks'], isNull);
    });

    test('ensure 对已归档日抛 CONFLICT', () async {
      await h.execResult('diary.ensure', args: {'date': '2026-10-10'});
      await h.repo.markExported([
        DateTime(2026, 10, 10),
      ], exportedAt: DateTime(2026, 10, 12));
      await h.repo.archiveDay(DateTime(2026, 10, 10));
      expect(
        (await h.exec(
          'diary.ensure',
          args: {'date': '2026-10-10'},
        )).error!.code,
        ControlErrorCode.conflict,
      );
    });

    test('prune：dry-run 与执行同口径（空稿删、有字稿留）', () async {
      await h.execResult('diary.ensure', args: {'date': '2026-10-10'});
      final filled = await h.execResult(
        'diary.ensure',
        args: {'date': '2026-10-11'},
      );
      final docId = (filled['document'] as Map)['id'] as String;
      await h.repo.upsertDraft(
        DiaryDocument(
          id: docId,
          date: DateTime(2026, 10, 11),
          title: 't',
          blocks: [DiaryBlock(id: docId, text: '写了字')],
        ),
      );

      // 3 级命令：未解锁先验证认证墙。
      final locked = await h.exec(
        'diary.prune',
        args: {'before': '2026-10-12', 'dryRun': true},
      );
      expect(locked.error!.code, ControlErrorCode.authRequired);

      await h.execResult(
        'auth.set-pin',
        args: {'newPin': 'echo1', 'newPinConfirm': 'echo1'},
      );
      await h.execResult('auth.unlock', args: {'pin': 'echo1'});

      final dry = await h.execResult(
        'diary.prune',
        args: {'before': '2026-10-12', 'dryRun': true},
        confirmed: true,
      );
      expect(dry['deleted'], ['2026-10-10']);
      expect((dry['kept'] as List).single, {
        'date': '2026-10-11',
        'reason': 'non-empty',
      });
      // dry-run 后数据仍在。
      expect(await h.repo.stateOfDay(DateTime(2026, 10, 10)), isNotNull);

      final run = await h.execResult(
        'diary.prune',
        args: {'before': '2026-10-12', 'dryRun': false},
        confirmed: true,
      );
      expect(run['deleted'], ['2026-10-10']);
      expect(await h.repo.stateOfDay(DateTime(2026, 10, 10)), isNull);
    });

    test('reset（debug-only）：清空 + 重灌种子', () async {
      await h.execResult('diary.ensure', args: {'date': '2026-10-10'});
      await h.execResult(
        'auth.set-pin',
        args: {'newPin': 'echo1', 'newPinConfirm': 'echo1'},
      );
      await h.execResult('auth.unlock', args: {'pin': 'echo1'});

      final wiped = await h.execResult(
        'diary.reset',
        args: {'keepSeeds': true},
        confirmed: true,
      );
      expect(wiped['removedDocs'], greaterThanOrEqualTo(1));
      expect(wiped['reseeded'], 2); // 上月 28 + 昨天（10-11）
      final years = await h.repo.availableYears();
      expect(years, isNotEmpty);
    });

    test('export：无 draft → EXPORT_EMPTY；有 draft → 落 zip', () async {
      await h.execResult(
        'auth.set-pin',
        args: {'newPin': 'echo1', 'newPinConfirm': 'echo1'},
      );
      await h.execResult('auth.unlock', args: {'pin': 'echo1'});

      // 已解锁 + 已确认：空库时错误来自业务而非裁决层。
      expect(
        (await h.exec('diary.export', confirmed: true)).error!.code,
        ControlErrorCode.exportEmpty,
      );

      await h.execResult('diary.ensure', args: {'date': '2026-10-10'});

      final zip = await h.execResult('diary.export', confirmed: true);
      expect(zip['entries'], 1);
      expect(zip['notebook'], '日记');
      expect((zip['path'] as String).endsWith('.sy.zip'), isTrue);
      expect(zip['sizeBytes'], greaterThan(0));

      // 命令不迁状态：仍为 draft（导出物可重复生成）。
      expect(
        await h.repo.stateOfDay(DateTime(2026, 10, 10)),
        DiaryDocState.draft,
      );
    });
  });
}

/// 测试用恒定时钟源（导航控制器需要 TickerProvider；命令只触发
/// snapTo，不跑真实帧）。
class _Ticker implements TickerProvider {
  const _Ticker();

  @override
  Ticker createTicker(TickerCallback onTick) => Ticker(onTick);
}
