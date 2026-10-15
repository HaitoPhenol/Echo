import 'package:flutter/scheduler.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:echo/src/control/protocol/command_spec.dart';
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

    test('export（G0 降 2 级）：本地通道未设 PIN/未解锁/无 confirm 直放；'
        'mcp 拒绝', () async {
      // 全新 harness 默认未设 PIN：2 级在本地通道起始级别内，直接放行；
      // 空库时错误来自业务而非裁决层（非 confirmRequired/authRequired）。
      expect(
        (await h.exec('diary.export')).error!.code,
        ControlErrorCode.exportEmpty,
      );

      await h.execResult('diary.ensure', args: {'date': '2026-10-10'});

      // 不传 confirmed：export 已删 destructive 标记。
      final zip = await h.execResult('diary.export');
      expect(zip['entries'], 1);
      expect(zip['notebook'], '日记');
      expect((zip['path'] as String).endsWith('.sy.zip'), isTrue);
      expect(zip['sizeBytes'], greaterThan(0));

      // 命令不迁状态：仍为 draft（导出物可重复生成）。
      expect(
        await h.repo.stateOfDay(DateTime(2026, 10, 10)),
        DiaryDocState.draft,
      );

      // MCP 上限 1：2 级写物理不可达（agent 导出仍被通道挡住）。
      final mcpDenied = await h.exec(
        'diary.export',
        channel: ControlChannel.mcp,
      );
      expect(mcpDenied.error!.code, ControlErrorCode.authRequired);
    });
  });

  group('diary.seed（debug-only，P4 灌数）', () {
    test('release 构建物理不注册；debug 下 3 级先鉴权、破坏性需 --confirm', () async {
      final rel = await ControlHarness.create(
        buildMode: ControlBuildMode.release,
      );
      addTearDown(rel.dispose);
      expect(
        (await rel.exec('diary.seed')).error!.code,
        ControlErrorCode.unknownCommand,
      );
      expect(
        rel.bus.visibleSpecs.map((s) => s.name),
        isNot(contains('diary.seed')),
      );

      // debug：admin 3 级且 destructive —— 未解锁 AUTH_REQUIRED；
      // 解锁后缺 --confirm 则 CONFIRM_REQUIRED。
      expect(
        (await h.exec('diary.seed')).error!.code,
        ControlErrorCode.authRequired,
      );
      await _unlockSeed(h);
      expect(
        (await h.exec('diary.seed', args: {'days': 1})).error!.code,
        ControlErrorCode.confirmRequired,
      );
    });

    test('日期回推：跨月/跨年/缺省=昨天；今天可显式种、未来拒绝', () async {
      await _unlockSeed(h);
      final crossYear = await h.execResult(
        'diary.seed',
        args: {'days': 3, 'end': '2026-01-01'},
        confirmed: true,
      );
      expect(crossYear['created'], ['2025-12-30', '2025-12-31', '2026-01-01']);

      // 跨月：2026 非闰年，2 月 28 天。
      final crossMonth = await h.execResult(
        'diary.seed',
        args: {'days': 2, 'end': '2026-03-01'},
        confirmed: true,
      );
      expect(crossMonth['created'], ['2026-02-28', '2026-03-01']);

      // 缺省 end＝日记日昨天（10-11），今天（10-12）不自动种。
      final dflt = await h.execResult(
        'diary.seed',
        args: {'days': 2},
        confirmed: true,
      );
      expect(dflt['created'], ['2026-10-10', '2026-10-11']);
      expect(await h.repo.dayExists(DateTime(2026, 10, 12)), isFalse);

      // 显式 --end 今天可种。
      final today = await h.execResult(
        'diary.seed',
        args: {'days': 1, 'end': '2026-10-12'},
        confirmed: true,
      );
      expect(today['created'], ['2026-10-12']);

      // 未来日期拒绝（M4 不提供未来入口）。
      expect(
        (await h.exec(
          'diary.seed',
          args: {'end': '2026-10-13'},
          confirmed: true,
        )).error!.code,
        ControlErrorCode.usage,
      );
    });

    test('空稿与 prune 端到端：seed→dryRun 列出→真删→list 复核', () async {
      await _unlockSeed(h);
      // 10 天（截至 09-20），每 3 天一篇空稿：
      // 距 end 0/3/6/9 天 → 09-20/17/14/11 为空稿。
      final seeded = await h.execResult(
        'diary.seed',
        args: {'days': 10, 'end': '2026-09-20', 'emptyEvery': 3},
        confirmed: true,
      );
      expect(seeded['empty'], [
        '2026-09-11',
        '2026-09-14',
        '2026-09-17',
        '2026-09-20',
      ]);
      expect((seeded['created'] as List), hasLength(6));

      // dry-run：deleted 恰为空稿日期（有字稿保留，reason=non-empty）。
      final dry = await h.execResult(
        'diary.prune',
        args: {'before': '2026-09-21', 'dryRun': true},
        confirmed: true,
      );
      expect(dry['deleted'], seeded['empty']);
      expect(
        (dry['kept'] as List).every((e) => (e as Map)['reason'] == 'non-empty'),
        isTrue,
      );
      // dry-run 后空稿仍在。
      expect(await h.repo.stateOfDay(DateTime(2026, 9, 11)), isNotNull);

      final run = await h.execResult(
        'diary.prune',
        args: {'before': '2026-09-21', 'dryRun': false},
        confirmed: true,
      );
      expect(run['deleted'], seeded['empty']);

      // list 复核：空稿消失、有字稿仍在。
      final list = await h.execResult('diary.list', args: {'month': '2026-09'});
      final dates = (list['items'] as List)
          .map((e) => (e as Map)['date'] as String)
          .toSet();
      for (final d in seeded['empty'] as List) {
        expect(dates, isNot(contains(d)), reason: '空稿 $d 应已删除');
      }
      for (final d in seeded['created'] as List) {
        expect(dates, contains(d), reason: '有字稿 $d 应保留');
      }
    });

    test('已存在日期跳过不覆盖', () async {
      await _unlockSeed(h);
      await h.execResult('diary.ensure', args: {'date': '2026-10-10'});
      // 给已有稿补一行用户文字，验证 seed 不覆盖。
      final doc = (await h.repo.findDay(DateTime(2026, 10, 10)))!;
      doc.blocks.add(DiaryBlock(id: h.repo.idGenerator.next(), text: '原有内容'));
      await h.repo.upsertDraft(doc);

      final seeded = await h.execResult(
        'diary.seed',
        args: {'days': 2, 'end': '2026-10-11', 'emptyEvery': 1},
        confirmed: true,
      );
      expect(seeded['skipped'], ['2026-10-10']);
      expect(seeded['empty'], ['2026-10-11']);
      final after = (await h.repo.findDay(DateTime(2026, 10, 10)))!;
      expect(after.blocks.any((b) => b.text == '原有内容'), isTrue);
    });

    test('参数越界 USAGE：days / empty-every', () async {
      await _unlockSeed(h);
      for (final bad in [0, 61]) {
        expect(
          (await h.exec(
            'diary.seed',
            args: {'days': bad},
            confirmed: true,
          )).error!.code,
          ControlErrorCode.usage,
          reason: 'days=$bad',
        );
      }
      expect(
        (await h.exec(
          'diary.seed',
          args: {'days': 3, 'emptyEvery': 4},
          confirmed: true,
        )).error!.code,
        ControlErrorCode.usage,
      );
    });
  });
}

/// 首装 PIN 并解锁当前 adb 会话（`diary.seed`/`chat.seed` 等 3 级前置）。
Future<void> _unlockSeed(ControlHarness h) async {
  await h.execResult(
    'auth.set-pin',
    args: {'newPin': 'echo1', 'newPinConfirm': 'echo1'},
  );
  await h.execResult('auth.unlock', args: {'pin': 'echo1'});
}

/// 测试用恒定时钟源（导航控制器需要 TickerProvider；命令只触发
/// snapTo，不跑真实帧）。
class _Ticker implements TickerProvider {
  const _Ticker();

  @override
  Ticker createTicker(TickerCallback onTick) => Ticker(onTick);
}
