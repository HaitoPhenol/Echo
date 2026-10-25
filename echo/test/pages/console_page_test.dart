// 终端页（R6）widget 回归：裸命令执行、确认卡、PIN 首装、历史召回。
//
// 整树只挂 ConsolePage（不经导航屏），经 ControlBootstrap 测试缝接入
// ControlHarness 真总线——与生产路径的差别仅在宿主外壳。

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:echo/src/control/bootstrap.dart';
import 'package:echo/src/control/protocol/command_spec.dart'
    show ControlBuildMode;
import 'package:echo/src/control/slash_ui/slash_result_card.dart';
import 'package:echo/src/pages/console_page.dart';

import '../control/control_test_harness.dart';

void main() {
  late ControlHarness h;

  Future<void> boot(
    WidgetTester tester, {
    ControlBuildMode mode = ControlBuildMode.debug,
  }) async {
    await tester.runAsync(() async {
      h = await ControlHarness.create(buildMode: mode);
    });
    ControlBootstrap.attachTestInstance(
      registry: h.registry,
      bus: h.bus,
      auth: h.auth,
      paths: h.paths,
      appState: h.appState,
      audit: h.audit,
      consoleStats: h.consoleStats,
    );
    addTearDown(ControlBootstrap.detachTestInstance);
    addTearDown(() => tester.runAsync(h.dispose));

    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: ConsolePage())),
    );
    await tester.pump();
  }

  /// 输入并提交一行（键盘「发送」动作 = 触屏回车）。
  Future<void> submitLine(WidgetTester tester, String line) async {
    await tester.enterText(find.byType(TextField), line);
    await tester.pump();
    await tester.testTextInput.receiveAction(TextInputAction.send);
    await tester.pump();
  }

  /// 推进到命令完成（信封回填是若干微任务）。
  Future<void> settle(WidgetTester tester, {int count = 20}) async {
    for (var i = 0; i < count; i++) {
      await tester.pump(const Duration(milliseconds: 4));
    }
  }

  String inputText(WidgetTester tester) =>
      tester.widget<TextField>(find.byType(TextField)).controller!.text;

  testWidgets('裸命令与 / 前缀等价：执行后出结果卡、输入行清空', (tester) async {
    await boot(tester);
    expect(find.text('输入命令并回车执行，例如 sys.ping'), findsOneWidget);

    await submitLine(tester, 'sys.ping');
    await settle(tester);
    expect(find.byType(SlashResultCard), findsOneWidget);
    expect(inputText(tester), isEmpty, reason: '提交后输入行清空');

    await submitLine(tester, '/sys.info');
    await settle(tester);
    expect(find.byType(SlashResultCard), findsNWidgets(2));
    expect(h.chatStore.conversations, isEmpty, reason: '只读命令无副作用');
  });

  testWidgets('未知命令：错误视图与命令回显都在结果流里', (tester) async {
    await boot(tester);
    await submitLine(tester, 'ghost.verb --x y');
    await settle(tester);

    expect(find.byType(SlashResultCard), findsOneWidget);
    expect(find.text('ghost.verb --x y'), findsOneWidget, reason: '回显原行');
    expect(find.text('UNKNOWN_COMMAND'), findsOneWidget);
  });

  testWidgets('破坏性命令：先挂确认卡，取消后不执行', (tester) async {
    await boot(tester);
    await submitLine(tester, 'diary.prune');
    await settle(tester);

    expect(find.text('执行 3 级破坏性命令'), findsOneWidget);
    expect(find.byType(SlashResultCard), findsNothing, reason: '未确认不执行');

    await tester.tap(find.text('取消'));
    await tester.pump();
    expect(find.text('执行 3 级破坏性命令'), findsNothing);
    expect(find.byType(SlashResultCard), findsNothing);
  });

  testWidgets('3 级命令未解锁：弹 PIN 首装面板', (tester) async {
    await boot(tester);
    await submitLine(tester, 'chat.send --id incoming-1 --text hi');
    await settle(tester);

    // isPinSet() 走真实文件 IO：fake-async 区里永不完成，放到 runAsync
    // 的真实事件循环里等它跑完，再回 fake 区 pump 一次让状态落到面板。
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 200)),
    );
    await tester.pump();

    expect(find.text('首次使用 · 设置 PIN'), findsOneWidget);
    expect(find.byType(SlashResultCard), findsOneWidget, reason: '失败信封同屏');
  });

  testWidgets('空输入时 ↑ 召回最近一条历史命令', (tester) async {
    await boot(tester);
    await submitLine(tester, 'sys.ping');
    await settle(tester);
    expect(inputText(tester), isEmpty);

    await tester.showKeyboard(find.byType(TextField));
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await tester.pump();
    expect(inputText(tester), 'sys.ping');
  });
}
