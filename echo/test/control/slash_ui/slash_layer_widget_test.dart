// slash 指令态 widget 测试：最小宿主（TextField + SlashKeyEvents +
// SlashCommandLayer）+ ControlHarness 真总线，覆盖
// 补全点选 → 确认卡 → 首装两输 → 结果卡渲染的完整 UI 链路，
// Esc 退指令态，JSON 长按复制。
//
// SmartNavScreen 上帝类不整树挂载（装配成本与价值不匹配，
// plan 已声明），真实胶囊外观由 G4 真机走查兜底。
//
// 注意：testWidgets 跑在 fake-async zone，PIN 落盘/校验是真实文件
// IO；凡触及 IO 的交互段用 tester.runAsync 执行并轮询模型，
// 帧重建统一在 runAsync 外 pump。

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:echo/src/control/slash/result_view.dart';
import 'package:echo/src/control/slash_ui/slash_ui.dart';

import '../control_test_harness.dart';

/// 在真实异步区等待模型条件（不能在这里 pump/查 finder）。
Future<void> _waitReal(bool Function() cond, {int ticks = 300}) async {
  for (var i = 0; i < ticks && !cond(); i++) {
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
  expect(cond(), isTrue, reason: 'runAsync 条件轮询超时');
}

Widget _host(TextEditingController tc, FocusNode fn, SlashConsoleController c) {
  return MaterialApp(
    home: Scaffold(
      body: Column(
        children: [
          SlashKeyEvents(
            controller: c,
            child: TextField(
              controller: tc,
              focusNode: fn,
              onChanged: c.onInputChanged,
              onSubmitted: (v) => c.submit(v),
            ),
          ),
          Expanded(child: SlashCommandLayer(controller: c)),
        ],
      ),
    ),
  );
}

void main() {
  testWidgets('指令态全链路：补全点选→确认→首装两输→结果卡', (tester) async {
    late final ControlHarness h;
    late final SlashConsoleController c;
    await tester.runAsync(() async {
      h = await ControlHarness.create();
    });
    addTearDown(() async {
      await tester.runAsync(h.dispose);
      c.dispose();
    });

    final tc = TextEditingController();
    final fn = FocusNode();
    addTearDown(tc.dispose);
    addTearDown(fn.dispose);
    c = SlashConsoleController(
      bus: h.bus,
      auth: h.auth,
      onEditText: (v) => tc.value = v,
    );

    await tester.pumpWidget(_host(tc, fn, c));

    // 1) 输 /di 出现命名空间候选，点 diary 插入 '/diary.'。
    await tester.enterText(find.byType(TextField), '/di');
    await tester.pump();
    expect(find.text('diary'), findsWidgets);
    await tester.tap(find.text('diary').first);
    await tester.pump();
    expect(tc.text, '/diary.');

    // 2) 带参命令提交 → 确认卡，且卡面回显完整原行（删除范围可核对）。
    await tester.enterText(
      find.byType(TextField),
      '/diary.prune --before 2026-10-01',
    );
    await tester.pump();
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();
    expect(find.text('执行 3 级破坏性命令'), findsOneWidget);
    expect(
      find.textContaining('diary.prune --before 2026-10-01 --confirm'),
      findsOneWidget,
    );

    // 3) 确认 → AUTH_REQUIRED → 首装面板（isPinSet 走真实 IO）。
    await tester.runAsync(() async {
      await tester.tap(find.text('确认执行'));
      await _waitReal(() => c.pinSheet.visible);
    });
    await tester.pump();
    expect(find.text('首次使用 · 设置 PIN'), findsOneWidget);

    // 4) 第一遍：纯本地阶段切换，无 IO。
    await tester.enterText(find.byType(TextField).last, '1234');
    await tester.pump();
    await tester.tap(find.text('确定'));
    await tester.pump();
    expect(find.text('再输入一遍 PIN'), findsOneWidget);

    // 5) 第二遍：set-pin 落盘 → unlock 校验 → 重放 prune，全在真实区。
    await tester.enterText(find.byType(TextField).last, '1234');
    await tester.pump();
    await tester.runAsync(() async {
      await tester.tap(find.text('确认'));
      await _waitReal(() => c.core.entries.length == 2);
    });
    await tester.pump();

    // 两条结果卡：原行 AUTH 失败 + 解锁后重放成功（结果流保留全部）。
    expect(find.byType(SlashResultCard), findsNWidgets(2));
    // 最新一条为成功（成功状态勾）；回显行含完整参数 + --confirm。
    expect(find.byIcon(Icons.check_circle_outline), findsOneWidget);
    expect(
      find.textContaining('diary.prune --before 2026-10-01 --confirm'),
      findsWidgets,
    );
  });

  testWidgets('Esc 硬件键退指令态并清空输入', (tester) async {
    late final ControlHarness h;
    late final SlashConsoleController c;
    await tester.runAsync(() async {
      h = await ControlHarness.create();
    });
    addTearDown(() async {
      await tester.runAsync(h.dispose);
      c.dispose();
    });

    final tc = TextEditingController();
    final fn = FocusNode();
    addTearDown(tc.dispose);
    addTearDown(fn.dispose);
    c = SlashConsoleController(
      bus: h.bus,
      auth: h.auth,
      onEditText: (v) => tc.value = v,
    );

    await tester.pumpWidget(_host(tc, fn, c));

    await tester.enterText(find.byType(TextField), '/sys.info ');
    await tester.pump();
    expect(c.active, isTrue);
    expect(find.text('--stay'), findsWidgets); // 参数段补全条挂载

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump();
    expect(tc.text, '');
    expect(c.active, isFalse);
  });

  testWidgets('JSON 结果长按写入剪贴板', (tester) async {
    final clips = <String>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') {
          clips.add((call.arguments as Map)['text'] as String);
        }
        return null;
      },
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: SlashResultCard(view: JsonView('{"a": 1}'))),
      ),
    );

    await tester.longPress(find.byType(SlashResultCard));
    await tester.pump();
    expect(clips.single, '{"a": 1}');
  });

  testWidgets('补全条恒贴消息列表底部；层内无嵌套滚动体（滚不到顶回归）', (tester) async {
    late final ControlHarness h;
    late final SlashConsoleController c;
    await tester.runAsync(() async {
      h = await ControlHarness.create();
    });
    addTearDown(() async {
      await tester.runAsync(h.dispose);
      c.dispose();
    });

    final tc = TextEditingController();
    final fn = FocusNode();
    addTearDown(tc.dispose);
    addTearDown(fn.dispose);
    c = SlashConsoleController(
      bus: h.bus,
      auth: h.auth,
      onEditText: (v) => tc.value = v,
    );

    // 生产同构：浮层以 left/right/bottom 定位在输入框上方（松散高度约束），
    // 加高表面避免内容被 0.45 高度上限压缩而走反滚。
    tester.view
      ..devicePixelRatio = 1.0
      ..physicalSize = const Size(400, 1200);
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Stack(
            children: [
              Positioned(
                left: 14,
                right: 14,
                bottom: 120,
                child: SlashCommandLayer(controller: c),
              ),
              Positioned(
                left: 14,
                right: 14,
                bottom: 40,
                child: TextField(
                  controller: tc,
                  focusNode: fn,
                  onChanged: c.onInputChanged,
                  onSubmitted: (v) => c.submit(v),
                ),
              ),
            ],
          ),
        ),
      ),
    );

    // 先制造一条历史结果（guest 级 /sys.ping 经若干微任务即时成功）。
    await tester.enterText(find.byType(TextField), '/sys.ping');
    await tester.pump();
    await tester.testTextInput.receiveAction(TextInputAction.done);
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 4));
      if (c.core.entries.isNotEmpty && c.core.entries.last.ok) break;
    }
    expect(find.byType(SlashResultCard), findsOneWidget);

    // 再输入 /di 展开命名空间候选：补全条与结果流同屏。
    await tester.enterText(find.byType(TextField), '/di');
    await tester.pump();
    expect(find.text('命名空间'), findsOneWidget);

    // 1) 预测提示指令框（补全条）必须完整落在消息列表（结果流）下方，
    //    而非浮在列表顶端被历史结果顶离视线。
    final resultCard = tester.getRect(find.byType(SlashResultCard));
    final completionLabel = tester.getRect(find.text('命名空间'));
    expect(
      completionLabel.top,
      greaterThanOrEqualTo(resultCard.bottom),
      reason: '补全条应贴消息列表底部',
    );

    // 2) 层内不得再有嵌套滚动体：结果流旧用 shrinkWrap/reverse ListView，
    //    竖直拖拽在手势竞技场被它抢先胜出却零可滚范围 → 整层滚不到顶。
    expect(
      find.descendant(
        of: find.byType(SlashCommandLayer),
        matching: find.byType(ListView),
      ),
      findsNothing,
    );
  });
}
