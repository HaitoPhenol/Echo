import 'dart:io';

import 'package:flutter/scheduler.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:echo/src/control/control_event_bridge.dart';
import 'package:echo/src/control/events/event_bus.dart';
import 'package:echo/src/control/events/event_types.dart';
import 'package:echo/src/control/protocol/command_spec.dart';
import 'package:echo/src/control/protocol/control_envelope.dart';
import 'package:echo/src/control/protocol/control_error.dart';
import 'package:echo/src/navigation/nav_destination_specs.dart';
import 'package:echo/src/navigation/nav_physics.dart';
import 'package:echo/src/services/chat_store.dart';

import '../control_test_harness.dart';

/// P4-G2 事件接入集成测试（交接单 §H G2）：
/// 1. 五个冻结事件的真实发射点（审计回调 / 总线唯一收口 / 导出
///    handler / ChatStore 与导航的装配适配器）；
/// 2. `sys.events` 命令契约：游标/nextSeq、长轮询提前唤醒与无关
///    事件不唤醒、limit/types、USAGE 矩阵、ceiling 物理过滤；
/// 3. 装配适配器幂等/页号 diff/生命周期；
/// 4. services/navigation 零 control 反向 import 的源码断言；
/// 5. G0 挂账 nit①：close 时在飞 poll 返空集。
void main() {
  /// 取 sys.events 返回里的事件 JSON 列表。
  List<Map<String, Object?>> eventsOf(Map<String, Object?> r) =>
      (r['events'] as List)
          .cast<Map>()
          .map((e) => e.cast<String, Object?>())
          .toList();

  /// 按类型（可选 cmd）过滤事件。
  List<Map<String, Object?>> typed(
    List<Map<String, Object?>> events,
    String type, {
    String? cmd,
  }) => events.where((e) {
    if (e['type'] != type) return false;
    if (cmd == null) return true;
    return (e['data'] as Map?)?.cast<String, Object?>()['cmd'] == cmd;
  }).toList();

  group('五个冻结事件发射点', () {
    test('audit.entry：≥2 级命令成败落审计即转发，先于 command.finished', () async {
      final h = await ControlHarness.create();
      addTearDown(h.dispose);

      await h.execResult('diary.ensure', args: {'date': '2026-10-10'});
      final r = await h.execResult('sys.events', args: {'since': 0});
      final events = eventsOf(r);

      final audits = typed(events, ControlEventType.auditEntry);
      expect(audits, isNotEmpty);
      final audit = audits.first;
      expect(audit['level'], ControlLevel.owner.value);
      final auditData = (audit['data'] as Map).cast<String, Object?>();
      expect(auditData['cmd'], 'diary.ensure');
      expect(auditData['ok'], isTrue);
      // 审计载荷走 AuditEntry.toJson 线形状（params/ms/channel）。
      expect(auditData['params'], isA<Map>());
      expect(auditData['ms'], isA<int>());

      // 同一调用的收口事件在审计之后（handler 成功 → 先落审计再发事件）。
      final finished = typed(
        events,
        ControlEventType.commandFinished,
        cmd: 'diary.ensure',
      ).single;
      expect(finished['seq'], greaterThan(audit['seq'] as int));
    });

    test('command.finished：成功/业务失败都发；裁决前失败（USAGE/未知/'
        '鉴权拒绝）不发', () async {
      final h = await ControlHarness.create();
      addTearDown(h.dispose);

      // 成功路径。
      await h.execResult('sys.ping');

      // 业务失败：空库导出 exportEmpty（已过裁决、进过收口）。
      final empty = await h.exec('diary.export');
      expect(empty.ok, isFalse);
      expect(empty.error!.code, ControlErrorCode.exportEmpty);

      // 裁决前失败三类：参数解析 USAGE（类型不符，进不了收口）、
      // 未知命令、鉴权拒绝。
      final badType = await h.exec('sys.events', args: {'waitMs': 'abc'});
      expect(badType.error!.code, ControlErrorCode.usage);
      final unknown = await h.exec('nope.nope');
      expect(unknown.error!.code, ControlErrorCode.unknownCommand);
      final denied = await h.exec(
        'chat.send',
        channel: ControlChannel.mcp,
        args: {'id': 'x', 'text': 'y'},
      );
      expect(denied.error!.code, ControlErrorCode.authRequired);

      final r = await h.execResult('sys.events', args: {'since': 0});
      final finished = typed(eventsOf(r), ControlEventType.commandFinished);
      final cmds = finished.map((e) => (e['data'] as Map)['cmd']).toList();

      expect(cmds, contains('sys.ping'));
      expect(cmds, contains('diary.export'));
      // 裁决前失败的 sys.events（解析 USAGE）/ 未知命令 / mcp 鉴权
      // 拒绝均不发收口事件（查询自身的 finished 在返回后才发）。
      expect(cmds.where((c) => c == 'sys.events'), isEmpty);
      expect(cmds, isNot(contains('nope.nope')));
      expect(cmds, isNot(contains('chat.send')));

      // 成功载荷形状：ok/ms/nonce；同步路径无 jobId 键。
      final ping = finished.firstWhere(
        (e) => (e['data'] as Map)['cmd'] == 'sys.ping',
      );
      final pingData = (ping['data'] as Map).cast<String, Object?>();
      expect(pingData['ok'], isTrue);
      expect(pingData['ms'], isA<int>());
      expect(pingData['nonce'], 'n');
      expect(pingData.containsKey('jobId'), isFalse);

      // 业务失败载荷：ok=false + error 结构。
      final failed = finished.firstWhere(
        (e) => (e['data'] as Map)['cmd'] == 'diary.export',
      );
      final failData = (failed['data'] as Map).cast<String, Object?>();
      expect(failData['ok'], isFalse);
      expect(
        ((failData['error'] as Map).cast<String, Object?>())['code'],
        ControlErrorCode.exportEmpty.wire,
      );
    });

    test('diary.export.completed + 后台作业终态事件带 jobId，顺序可关联', () async {
      final h = await ControlHarness.create();
      addTearDown(h.dispose);

      await h.execResult('diary.ensure', args: {'date': '2026-10-10'});
      // 起作业前先抓游标：轮询期间每次 sys.job.get 自身都会产生一条
      // command.finished（重载下导出可达数百 ms、上百次轮询），
      // 不用游标会把目标事件挤出 limit 窗口。
      final startSeq = h.events.lastSeq;
      final running = await h.exec(
        'diary.export',
        backgroundSlow: true,
        nonce: 'exp-g2',
      );
      expect(running.async, isTrue);
      // running 首包不发 command.finished（终态才发）。
      expect(running.jobId, 'exp-g2');

      // 轮询作业至 done（终态事件在 complete 落表前已入环）。
      final deadline = DateTime.now().add(const Duration(seconds: 5));
      ControlEnvelope done = running;
      while (DateTime.now().isBefore(deadline)) {
        done = await h.exec('sys.job.get', args: {'id': 'exp-g2'});
        if (done.ok && done.result!['status'] == 'done') break;
        await Future<void>.delayed(const Duration(milliseconds: 5));
      }
      expect(done.result!['status'], 'done', reason: done.error?.toString());
      final innerDone = (done.result!['envelope'] as Map?)
          ?.cast<String, Object?>();
      expect(innerDone?['ok'], isTrue, reason: '内层信封：$innerDone');

      // 类型白名单 + 游标：环内只有这一条导出完成事件，轮询噪声被
      // 类型物理过滤，与重载下的轮询次数无关。
      final exportR = await h.execResult(
        'sys.events',
        args: {
          'since': startSeq,
          'types': ControlEventType.diaryExportCompleted,
        },
      );
      final exported = eventsOf(exportR).single;
      expect(exported['level'], ControlLevel.user.value);
      final data = (exported['data'] as Map).cast<String, Object?>();
      expect((data['path'] as String).endsWith('.sy.zip'), isTrue);
      expect(data['entries'] as int, greaterThanOrEqualTo(1));
      expect(data['sizeBytes'] as int, greaterThan(0));
      expect(data['notebook'], '日记');

      // 终态收口：从导出完成事件的 seq 往后看，按 cmd 过滤出本次
      // 导出的收口（其间夹有最后一次 sys.job.get 自身的 finished）。
      final termR = await h.execResult(
        'sys.events',
        args: {
          'since': exported['seq'] as int,
          'types': ControlEventType.commandFinished,
        },
      );
      final terminal = typed(
        eventsOf(termR),
        ControlEventType.commandFinished,
        cmd: 'diary.export',
      ).single;
      final terminalData = (terminal['data'] as Map).cast<String, Object?>();
      expect(terminalData['ok'], isTrue);
      expect(terminalData['jobId'], 'exp-g2');
      expect(terminalData['nonce'], 'exp-g2');
      // 先有导出完成事件，后有收口终态。
      expect(terminal['seq'], greaterThan(exported['seq'] as int));
    });

    test('chat.incoming：适配器转发自定义文本与默认文案两条路径', () async {
      final h = await ControlHarness.create();
      addTearDown(h.dispose);
      final nav = NavPhysicsController(vsync: const _VSync(), pageCount: 4);
      addTearDown(nav.dispose);
      final bridge = UiEventBridge(
        events: h.events,
        chatStore: h.chatStore,
        nav: nav,
      )..attach();
      addTearDown(bridge.dispose);

      // 自定义正文：trim 后正文与预览同源。
      h.chatStore.addIncoming(text: '  你好，世界  ');
      // broadcast StreamController 的监听回调在微任务里派发，
      // 等一拍让适配器把信号翻译成事件。
      await Future<void>.delayed(Duration.zero);
      var r = await h.execResult(
        'sys.events',
        args: {'since': 0, 'types': ControlEventType.chatIncoming},
      );
      var event = eventsOf(r).single;
      expect(event['level'], ControlLevel.owner.value);
      var data = (event['data'] as Map).cast<String, Object?>();
      expect(data['id'], 'incoming-1');
      expect(data['nickname'], '新消息 1');
      expect(data['preview'], '你好，世界');
      expect(data['text'], '你好，世界');

      // null/空白走默认文案（UI 按钮零参路径不变）。
      h.chatStore.addIncoming(text: '   ');
      await Future<void>.delayed(Duration.zero);
      r = await h.execResult(
        'sys.events',
        args: {'since': event['seq'], 'types': ControlEventType.chatIncoming},
      );
      event = eventsOf(r).single;
      data = (event['data'] as Map).cast<String, Object?>();
      expect(data['id'], 'incoming-2');
      expect(data['preview'], '你有一条新消息');
      expect(data['text'], '你有一条新消息');
    });

    test('nav.changed：初始页不发、页号 diff 才发、同页 notify 不重发、'
        'dispose 后不发、可重新 attach', () async {
      final h = await ControlHarness.create();
      addTearDown(h.dispose);
      final nav = NavPhysicsController(vsync: const _VSync(), pageCount: 4);
      addTearDown(nav.dispose);
      final bridge = UiEventBridge(
        events: h.events,
        chatStore: h.chatStore,
        nav: nav,
      );

      Future<List<Map<String, Object?>>> navEvents(int since) async {
        final r = await h.execResult(
          'sys.events',
          args: {'since': since, 'types': ControlEventType.navChanged},
        );
        return eventsOf(r);
      }

      bridge
        ..attach()
        ..attach(); // 幂等：重复 attach 不叠加监听。

      // 初始页无「变化」；同页 notify（拖动帧很密）不发。
      nav.notifyListeners();
      expect(await navEvents(0), isEmpty);

      // 真正换页：guest(0) 级，页名解析自目的地规格。
      nav.activePage = 2;
      nav.notifyListeners();
      var events = await navEvents(0);
      expect(events.length, 1);
      expect(events.single['level'], ControlLevel.guest.value);
      final data = (events.single['data'] as Map).cast<String, Object?>();
      expect(data['index'], 2);
      expect(data['page'], navPageName(2));
      expect(data['page'], 'notes');
      final lastSeq = events.single['seq'] as int;

      // 同页再 notify 不重发。
      nav.notifyListeners();
      expect(await navEvents(lastSeq), isEmpty);

      // 再换页。
      nav.activePage = 3;
      nav.notifyListeners();
      events = await navEvents(lastSeq);
      expect((events.single['data'] as Map)['index'], 3);
      expect((events.single['data'] as Map)['page'], 'me');

      // dispose 后页再变化不发。
      bridge.dispose();
      nav.activePage = 1;
      nav.notifyListeners();
      expect(await navEvents(h.events.lastSeq), isEmpty);

      // 允许重新 attach：attach 时当前页作为新基线（不补发），
      // 之后再次换页正常转发。游标必须在触发事件之前捕获。
      bridge.attach();
      nav.notifyListeners();
      expect(await navEvents(h.events.lastSeq), isEmpty);
      final beforeReopen = h.events.lastSeq;
      nav.activePage = 0;
      nav.notifyListeners();
      events = await navEvents(beforeReopen);
      expect((events.single['data'] as Map)['index'], 0);
      expect((events.single['data'] as Map)['page'], 'console');
      bridge.dispose();
    });
  });

  group('sys.events 命令契约', () {
    test('缺省 since=当前尾 seq 不补历史；nextSeq 游标连续', () async {
      final h = await ControlHarness.create();
      addTearDown(h.dispose);

      await h.execResult('sys.ping'); // 产生 1 条 command.finished。
      final tail = h.events.lastSeq;
      expect(tail, greaterThanOrEqualTo(1));

      // 不带 since：只看新事件，历史不补。
      final r1 = await h.execResult('sys.events');
      expect(eventsOf(r1), isEmpty);
      expect(r1['nextSeq'], tail);
    });

    test('wait-ms 长轮询被命中事件提前唤醒；无关事件不唤醒', () async {
      final h = await ControlHarness.create();
      addTearDown(h.dispose);
      final tail = h.events.lastSeq;

      // 等 3s，期间触发一条 command.finished（owner，命中全类型）：
      // 应远早于截止返回。
      final woken = h.exec('sys.events', args: {'waitMs': 3000, 'since': tail});
      await Future<void>.delayed(const Duration(milliseconds: 80));
      await h.execResult('sys.ping');
      final sw = Stopwatch()..start();
      final r1 = await woken;
      sw.stop();
      expect(r1.ok, isTrue, reason: r1.error?.toString());
      expect(sw.elapsedMilliseconds, lessThan(1500));
      final got = eventsOf(r1.result!);
      expect((got.single['data'] as Map)['cmd'], 'sys.ping');
      expect(r1.result!['nextSeq'], got.single['seq']);

      // types 白名单下，新事件不命中必须继续等到截止（不提前返空）。
      final waiting = h.exec(
        'sys.events',
        args: {
          'since': h.events.lastSeq,
          'waitMs': 400,
          'types': ControlEventType.navChanged,
        },
      );
      await Future<void>.delayed(const Duration(milliseconds: 80));
      await h.execResult('sys.ping'); // owner 级、类型不符。
      sw
        ..reset()
        ..start();
      final r2 = await waiting;
      sw.stop();
      expect(r2.ok, isTrue);
      expect(eventsOf(r2.result!), isEmpty);
      expect(sw.elapsedMilliseconds, greaterThanOrEqualTo(300));
    });

    test('since/limit 升序截断；types 白名单；未知类型 USAGE', () async {
      final h = await ControlHarness.create();
      addTearDown(h.dispose);

      await h.execResult('sys.ping');
      await h.execResult('sys.ping');
      await h.execResult('sys.ping');

      // 首次查询时环内恰有三条 ping 的收口事件（查询自身的 finished
      // 在返回后才发射）。types 白名单 + 升序 + nextSeq。
      final first = await h.execResult(
        'sys.events',
        args: {'since': 0, 'types': ControlEventType.commandFinished},
      );
      final all = eventsOf(first);
      expect(all.length, 3);
      expect(all.map((e) => e['seq']), [1, 2, 3]);
      expect(first['nextSeq'], 3);

      // limit 截断：前两条。
      final p1 = await h.execResult(
        'sys.events',
        args: {
          'since': 0,
          'limit': 2,
          'types': ControlEventType.commandFinished,
        },
      );
      expect(eventsOf(p1).map((e) => e['seq']), [1, 2]);

      // 游标续轮：seq>2 的第一条仍是第三发 ping（其后可能夹有各次
      // sys.events 查询自身的 finished，按 cmd 过滤出受测主体）。
      final p2 = await h.execResult(
        'sys.events',
        args: {'since': 2, 'types': ControlEventType.commandFinished},
      );
      final restPings = typed(
        eventsOf(p2),
        ControlEventType.commandFinished,
        cmd: 'sys.ping',
      );
      expect(restPings.single['seq'], 3);

      // types 不命中：nav.changed 一条都没有。
      final none = await h.execResult(
        'sys.events',
        args: {'since': 0, 'types': ControlEventType.navChanged},
      );
      expect(eventsOf(none), isEmpty);

      // 未知类型（含与合法类型混排）一律 USAGE。
      final unknown = await h.exec(
        'sys.events',
        args: {'types': 'nav.changed,bogus.type'},
      );
      expect(unknown.error!.code, ControlErrorCode.usage);
      expect(unknown.error!.message, contains('未知事件类型'));
    });

    test('USAGE 矩阵：wait-ms/limit 越界', () async {
      final h = await ControlHarness.create();
      addTearDown(h.dispose);

      for (final bad in [
        {'waitMs': 8001},
        {'waitMs': -1},
        {'limit': 0},
        {'limit': 101},
      ]) {
        final env = await h.exec('sys.events', args: bad);
        expect(env.ok, isFalse, reason: '应拒绝：$bad');
        expect(env.error!.code, ControlErrorCode.usage, reason: '参数：$bad');
      }
    });

    test('ceiling 物理过滤：事件环按有效级别剔除超级别事件', () async {
      final h = await ControlHarness.create();
      addTearDown(h.dispose);

      await h.execResult('diary.ensure', args: {'date': '2026-10-10'});
      await h.execResult('diary.export'); // 产生 user(2) 导出事件 + owner 事件。

      // owner ceiling：user 级导出事件物理消失（不是打码），owner 级
      // 的收口/审计仍可见。
      final ownerView = await h.events.poll(
        since: 0,
        ceiling: ControlLevel.owner,
      );
      expect(
        ownerView.any((e) => e.type == ControlEventType.diaryExportCompleted),
        isFalse,
      );
      expect(
        ownerView.any((e) => e.type == ControlEventType.commandFinished),
        isTrue,
      );

      // user ceiling（adb/slash 未解锁的有效级别）：全集可见。
      final userView = await h.events.poll(
        since: 0,
        ceiling: ControlLevel.user,
      );
      expect(
        userView.any((e) => e.type == ControlEventType.diaryExportCompleted),
        isTrue,
      );

      // 命令面：adb 未解锁＝user(2)，sys.events 看得到导出完成事件。
      final viaAdb = await h.execResult(
        'sys.events',
        args: {'since': 0, 'types': ControlEventType.diaryExportCompleted},
      );
      expect(eventsOf(viaAdb).length, 1);

      // mcp 未解锁有效级别＝guest(0)，而 sys.events 本身是 owner(1)：
      // 与一切 owner 级读命令同纪律，在鉴权门即 AUTH_REQUIRED。
      //
      // 此处钉死**未解锁**的鉴权门行为；R4 起 mcp 可解锁到 owner(1)
      // 只读，解锁后的 owner 级读取由 test/control/mcp 覆盖。
      final viaMcp = await h.exec(
        'sys.events',
        channel: ControlChannel.mcp,
        args: {'since': 0},
      );
      expect(viaMcp.ok, isFalse);
      expect(viaMcp.error!.code, ControlErrorCode.authRequired);
    });
  });

  group('G0 挂账 nit①：close 时在飞 poll 的语义', () {
    test('等待期间 close 立即返空集不抛；close 后历史仍可一次性读出', () async {
      final bus = ControlEventBus();
      addTearDown(bus.close); // 二次 close 幂等。

      bus.emit(
        type: ControlEventType.navChanged,
        level: ControlLevel.guest,
        data: const {'index': 0},
      );
      final tail = bus.lastSeq;

      // 在飞长轮询等「新事件」。
      final flying = bus.poll(
        since: tail,
        ceiling: ControlLevel.owner,
        wait: const Duration(seconds: 5),
      );
      await Future<void>.delayed(const Duration(milliseconds: 30));
      bus.close();
      final got = await flying; // 不穿透 StateError。
      expect(got, isEmpty);

      // 环未清：close 后一次性 poll（wait=null）仍读得到历史。
      final history = await bus.poll(since: 0, ceiling: ControlLevel.owner);
      expect(history.single.type, ControlEventType.navChanged);
    });

    test('close 后严格 emit 抛 StateError；tryEmit 安静丢弃返回 null', () {
      final bus = ControlEventBus();
      bus.emit(
        type: ControlEventType.navChanged,
        level: ControlLevel.guest,
        data: const {'index': 0},
      );
      bus.close();

      // 业务发射点仍受严格约束：生命周期接错要暴露。
      expect(
        () => bus.emit(
          type: ControlEventType.navChanged,
          level: ControlLevel.guest,
        ),
        throwsStateError,
      );

      // 装配收口缝：关停途中晚到的终态/审计不拖垮命令执行。
      expect(
        bus.tryEmit(
          type: ControlEventType.commandFinished,
          level: ControlLevel.owner,
        ),
        isNull,
      );
      expect(bus.length, 1); // 丢弃的事件未入环。
    });
  });

  group('G2 复审必改项：收口缝关停容忍', () {
    test('events.close 后在飞后台 slow 作业仍正常收口，晚到事件安静丢弃', () async {
      final h = await ControlHarness.create();
      addTearDown(h.dispose);

      // 起一条短后台作业：同步首包只回 running（不发收口事件）。
      final running = await h.exec(
        'sys.delay',
        args: {'ms': 60},
        backgroundSlow: true,
        nonce: 'tolerant-1',
      );
      expect(running.async, isTrue);
      final maybe = h.jobs.lookup(
        id: 'tolerant-1',
        channel: ControlChannel.adb,
      );
      expect(maybe, isNotNull, reason: '作业应已登记入表');
      final job = maybe!;
      expect(job.isDone, isFalse);

      // 模拟宿主关停：事件中心先关，作业在其后才跑完收口。
      // 修复前收口走严格 emit → 抛 StateError → 被 `on StateError`
      // 误捕成 CONFLICT → failAudited 内二次 emit 再抛并穿透 catch →
      // jobs.complete 不执行（作业永久 running）+ 未捕获异步异常。
      // close 后 sys.events 不再是可用观测手段，直接查作业表。
      final lengthAtClose = h.events.length;
      h.events.close();

      final deadline = DateTime.now().add(const Duration(seconds: 5));
      while (!job.isDone && DateTime.now().isBefore(deadline)) {
        await Future<void>.delayed(const Duration(milliseconds: 5));
      }

      // 关停容忍：终态照写作业表，成功命令不被拖垮。
      expect(job.isDone, isTrue, reason: 'close 后作业仍应写入终态信封');
      expect(job.envelope!.ok, isTrue);
      expect(job.envelope!.cmd, 'sys.delay');
      expect(job.envelope!.nonce, 'tolerant-1');
      expect(job.envelope!.result!['sleptMs'], 60);
      // 晚到的事件安静丢弃：close 后事件环不再增长。
      expect(h.events.length, lengthAtClose);
    });
  });

  group('分层硬项：services/navigation 零 control 反向依赖', () {
    test('services/ 全目录与导航物理层源码无 control import', () {
      final banned = RegExp(r'''import\s+['"][^'"]*control/''');

      final serviceFiles = Directory('lib/src/services')
          .listSync(recursive: true)
          .whereType<File>()
          .where((f) => f.path.endsWith('.dart'))
          .toList();
      expect(serviceFiles, isNotEmpty, reason: '从 echo/ 包目录运行测试');

      // 导航层只钉物理层：装配宿主 smart_nav_screen.dart 与
      // slash_ui/ 允许（且应当）import control。
      final navFiles = [
        File('lib/src/navigation/nav_physics.dart'),
        File('lib/src/navigation/nav_destination_specs.dart'),
      ];

      for (final f in [...serviceFiles, ...navFiles]) {
        final src = f.readAsStringSync();
        expect(
          banned.hasMatch(src),
          isFalse,
          reason: '${f.path} 不得反向 import control（P4-G2 接线纪律）',
        );
      }
    });

    test('ChatStore 不认识事件总线：incoming 是 services 自有载荷类型', () {
      // 编译期保证：addIncoming 的广播类型来自 services 自身
      //（ChatIncomingPayload 定义在 services/chat_repository.dart，
      // 由 chat_store.dart 导出），适配器只在 control 层做翻译。
      const payload = ChatIncomingPayload(
        id: 'incoming-1',
        nickname: 'n',
        preview: 'p',
        text: 't',
      );
      expect(payload.id, 'incoming-1');
    });
  });
}

/// 纯测试用 TickerProvider（与 domain_commands_test 同款）：
/// NavPhysicsController 构造必须要 vsync，单测不需要真正跑帧。
class _VSync implements TickerProvider {
  const _VSync();

  @override
  Ticker createTicker(TickerCallback onTick) => Ticker(onTick);
}
