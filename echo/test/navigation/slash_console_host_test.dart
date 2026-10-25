// G4-BUG-1 宿主层回归：整树挂载 SmartNavScreen（经 ControlBootstrap
// 测试缝接入 ControlHarness 真总线），验证触屏 IME「完成」提交后
// TextField 失焦的 150ms 定时器不会自毁 slash 指令台，同时钉死
// 普通搜索态失焦自动关闭与 scrim/BACK/Esc 显式退出不回归。
//
// 真机机理（见 docs/code_review_report.md G4）：IME done 触发
// onSubmitted 后主动 hide 键盘 → 搜索框失焦；widget 测试里以
// focusNode.unfocus() 显式复现该失焦。G4-BUG-3 的 IME hide 补帧器
// 不做任何失焦/断连动作（只标脏根 RenderView 重提帧），本文件的
// 保活断言不受其影响；补帧器单例在每个用例后重置，避免状态互串。

import 'package:echo/src/app/echo_app.dart';
import 'package:echo/src/control/bootstrap.dart';
import 'package:echo/src/control/slash_ui/slash_ui.dart';
import 'package:echo/src/diary/data/in_memory_diary_repository.dart';
import 'package:echo/src/navigation/dock_geometry.dart';
import 'package:echo/src/navigation/widgets/search_capsule.dart';
import 'package:echo/src/services/window_inset_refresher.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../control/control_test_harness.dart';

/// 搜索胶囊内的输入框（R6 起终端页也有 TextField，不能裸定位）。
final Finder searchField = find.descendant(
  of: find.byType(SearchCapsule),
  matching: find.byType(TextField),
);

void main() {
  late final InMemoryDiaryRepository diaryRepo;
  setUpAll(() {
    diaryRepo = InMemoryDiaryRepository(seedDebugData: true);
    addTearDown(diaryRepo.dispose);
    // G4-BUG-3：slash 提交会安排 50ms（覆盖）后的兜底补帧标脏；
    // 既有的 200ms 级 pump 自然触发（避免 fake-async 悬挂定时器），
    // 标脏只重提当前 scene，不触碰焦点与输入连接。补帧窗口也缩到
    // 100ms，让各用例既有的 200ms pump 越过窗口超时。
    WindowInsetRefresher.fallbackDelayOverride = const Duration(
      milliseconds: 50,
    );
    WindowInsetRefresher.windowOverride = const Duration(milliseconds: 100);
    addTearDown(() {
      WindowInsetRefresher.fallbackDelayOverride = null;
      WindowInsetRefresher.windowOverride = null;
    });
  });

  late ControlHarness h;

  Future<void> boot(WidgetTester tester) async {
    await tester.runAsync(() async {
      h = await ControlHarness.create();
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

    WindowInsetRefresher.debugReset();
    addTearDown(WindowInsetRefresher.debugReset);

    await tester.pumpWidget(EchoApp(diaryRepository: diaryRepo));
    await tester.pump();
  }

  /// 长按胶囊展开搜索并聚焦输入框（与 widget_test.dart 同一几何）。
  Future<void> openSearch(WidgetTester tester) async {
    await tester.longPressAt(const Offset(600, 560));
    await tester.pump(const Duration(milliseconds: 500));
    expect(searchField, findsOneWidget, reason: '搜索已展开');
    await tester.tapAt(const Offset(500, 560));
    await tester.pump(const Duration(milliseconds: 100));
  }

  /// 模拟触屏 IME 提交：重组进入指令态（SlashKeyEvents 包裹输入框）
  /// 后，widget 测试环境里新 EditableText 不会自动重连 IME 客户端
  /// （真机软键盘持续输入时连接保持），先 showKeyboard 重挂再发
  /// 蓝色「完成」动作；done 会同步令输入框失焦。
  Future<void> imeDone(WidgetTester tester) async {
    await tester.showKeyboard(searchField);
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();
  }

  /// 复现 MIUI IME 点「完成」后的 hide 键盘 → TextField 失焦，
  /// 并越过 150ms 失焦定时器（再留 50ms 余量）。
  Future<void> imeDoneThenUnfocus(WidgetTester tester) async {
    final focusNode = tester.widget<TextField>(searchField).focusNode;
    expect(focusNode, isNotNull);
    focusNode!.unfocus();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
  }

  /// 逐帧推进等待搜索胶囊卸载（最长约 1s）。
  Future<void> pumpUntilClosed(WidgetTester tester) async {
    var closed = false;
    for (var i = 0; i < 64 && !closed; i++) {
      await tester.pump(const Duration(milliseconds: 16));
      closed = searchField.evaluate().isEmpty;
    }
    expect(closed, isTrue, reason: '搜索面板应收起');
  }

  SlashConsoleController slashOf(WidgetTester tester) => tester
      .widget<SlashCommandLayer>(find.byType(SlashCommandLayer))
      .controller;

  testWidgets('提交挂起确认卡后失焦：面板不自毁，确认卡仍在且可点', (tester) async {
    await boot(tester);
    await openSearch(tester);

    await tester.enterText(searchField, '/diary.prune');
    await tester.pump();
    // 触屏唯一提交动作：IME 蓝色「完成」。
    await imeDone(tester);
    expect(find.text('执行 3 级破坏性命令'), findsOneWidget);
    final slash = slashOf(tester);
    expect(slash.confirmPending, isNotNull);

    await imeDoneThenUnfocus(tester);

    // 150ms 后：面板仍开、确认卡仍挂（旧实现此处已 hostClosed 清空）。
    expect(searchField, findsOneWidget, reason: '失焦不得收起指令台');
    expect(find.text('执行 3 级破坏性命令'), findsOneWidget);
    expect(slash.confirmPending, isNotNull);
    expect(slash.pinSheet.visible, isFalse);

    // 卡片按钮不依赖搜索框焦点：点「取消」即时响应（同步路径）。
    await tester.tap(find.text('取消'));
    await tester.pump();
    expect(slash.confirmPending, isNull);
    expect(find.text('执行 3 级破坏性命令'), findsNothing);
    // 取消后指令态仍在，输入框未被关闭。
    expect(searchField, findsOneWidget);
  });

  testWidgets('提交产生结果流后失焦：面板与结果卡保留', (tester) async {
    await boot(tester);
    await openSearch(tester);

    await tester.enterText(searchField, '/sys.ping');
    await tester.pump();
    await imeDone(tester);
    // guest 级命令经若干微任务完成。
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 4));
      if (slashOf(tester).core.entries.isNotEmpty &&
          slashOf(tester).core.entries.last.ok) {
        break;
      }
    }
    final slash = slashOf(tester);
    expect(slash.core.entries, hasLength(1));
    expect(slash.core.entries.single.ok, isTrue);
    expect(find.byType(SlashResultCard), findsOneWidget);

    await imeDoneThenUnfocus(tester);
    expect(searchField, findsOneWidget, reason: '结果流回看期失焦不得关闭');
    expect(find.byType(SlashResultCard), findsOneWidget);
  });

  testWidgets('搜索框发送按钮走键盘提交同一路径：执行命令并产出结果卡', (tester) async {
    await boot(tester);
    await openSearch(tester);

    await tester.enterText(searchField, '/sys.ping');
    await tester.pump();
    expect(find.byTooltip('执行命令'), findsOneWidget);

    await tester.tap(find.byTooltip('执行命令'));
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.byType(SlashResultCard), findsOneWidget);
  });

  testWidgets('指令面板顶边钉在 y=40，键盘开合都撑满到输入框上沿', (tester) async {
    await boot(tester);
    await openSearch(tester);

    await tester.enterText(searchField, '/sys.');
    await tester.pump();

    final layer = find.byType(SlashCommandLayer);
    expect(layer, findsOneWidget);

    // 测试表面 800×600、安全区 0：胶囊上沿 = 600−(16+44)，面板再留 8。
    const capsuleTop = 600.0 - (16 + DockGeometry.searchHeight);
    final closed = tester.getRect(layer);
    expect(closed.top, closeTo(DockGeometry.slashPanelTop, 0.5));
    expect(closed.bottom, closeTo(capsuleTop - 8, 0.5));

    // 软键盘弹起：顶边不动，底边随胶囊抬到键盘上方，高度自适应收缩。
    // FakeViewPadding 以物理像素计，换算成逻辑像素后再断言。
    tester.view.viewInsets = const FakeViewPadding(bottom: 260);
    addTearDown(tester.view.reset);
    await tester.pump();
    final keyboardInset = 260 / tester.view.devicePixelRatio;
    final open = tester.getRect(layer);
    expect(open.top, closeTo(DockGeometry.slashPanelTop, 0.5));
    expect(open.bottom, closeTo(capsuleTop - 8 - keyboardInset, 0.5));
    expect(open.height, lessThan(closed.height));
  });

  testWidgets('普通搜索态失焦：150ms 后仍自动关闭（回归保护）', (tester) async {
    await boot(tester);
    await openSearch(tester);

    await tester.enterText(searchField, '聊天');
    await tester.pump();
    expect(find.text('页面'), findsOneWidget, reason: '普通搜索结果正常');
    expect(slashOf(tester).active, isFalse);

    final focusNode = tester.widget<TextField>(searchField).focusNode!;
    focusNode.unfocus();
    await pumpUntilClosed(tester);
    expect(find.byType(SlashCommandLayer), findsNothing);
  });

  testWidgets('显式退出不受保活影响：点 scrim 关闭并清空挂起确认卡', (tester) async {
    await boot(tester);
    await openSearch(tester);

    await tester.enterText(searchField, '/diary.prune');
    await tester.pump();
    await imeDone(tester);
    final slash = slashOf(tester);
    expect(slash.confirmPending, isNotNull);
    await imeDoneThenUnfocus(tester);
    expect(searchField, findsOneWidget, reason: '前置：失焦未关闭');

    // 点 scrim 空白区：显式退出必须穿透保活闸门。
    await tester.tapAt(const Offset(400, 100));
    await pumpUntilClosed(tester);
    expect(slash.confirmPending, isNull, reason: 'hostClosed 清空挂起态');
  });

  testWidgets('显式退出不受保活影响：系统返回键关闭', (tester) async {
    await boot(tester);
    await openSearch(tester);

    await tester.enterText(searchField, '/diary.prune');
    await tester.pump();
    await imeDone(tester);
    final slash = slashOf(tester);
    expect(slash.confirmPending, isNotNull);
    await imeDoneThenUnfocus(tester);
    expect(searchField, findsOneWidget, reason: '前置：失焦未关闭');

    await tester.binding.handlePopRoute();
    await pumpUntilClosed(tester);
    expect(slash.confirmPending, isNull, reason: 'hostClosed 清空挂起态');
  });

  testWidgets('Esc 显式退出指令态后失焦：不再被结果流保活，面板关闭', (tester) async {
    await boot(tester);
    await openSearch(tester);

    await tester.enterText(searchField, '/sys.ping');
    await tester.pump();
    await imeDone(tester);
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 4));
      if (slashOf(tester).core.entries.isNotEmpty &&
          slashOf(tester).core.entries.last.ok) {
        break;
      }
    }
    final slash = slashOf(tester);
    expect(slash.active, isTrue);

    // Esc 先显式结束指令会话（键事件需焦点在输入框）。
    final focusNode = tester.widget<TextField>(searchField).focusNode!;
    if (!focusNode.hasFocus) {
      focusNode.requestFocus();
      await tester.pump();
    }
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump();
    expect(slash.active, isFalse, reason: 'Esc 退出指令态');

    // 旧语义下 entries 非空会一直保活；Esc 已显式结束会话，失焦应关闭。
    focusNode.unfocus();
    await pumpUntilClosed(tester);
  });
}
