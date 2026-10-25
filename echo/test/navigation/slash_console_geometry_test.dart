// G4-BUG-3 几何回归（MIX 2S / Android 10 / MIUI / 豆包 IME 真机阻断）：
// 整树挂载 EchoApp。钉死四件事——
//
// 1. 根因二（SlashCommandLayer 高度约束 overflow）：压缩画布
//    （584 逻辑高 ≈ 真机键盘压缩的 1751px÷3，0.45 上限仅 263）下，
//    确认卡/PIN 卡必须以固有高度完整落在 Layer RenderBox 内（命中点
//    不得落到溢出区——溢出区 hitTest 恒 false 即「可见不可点」的直接
//    机理），补全/结果区可被压到 0、内部滚动，不得抛 overflow。
// 2. adjustResize 键盘弹起态几何（本来就正确、必须守住的部分）：
//    系统直接把窗口物理压缩到键盘顶缘——测试里以表面高度 780→580
//    忠实复现（键盘高 200 逻辑像素，等价真机窗口 frame
//    1080x2160→1080x1751）。搜索胶囊底边停在键盘顶缘上方，slash
//    层在胶囊之上，确认卡按钮在压缩后的层内仍可点。
// 3. 根因一（真机最终修复）= IME hide「终态补帧」：真机实锤为布局/
//    hit-test 已随最终全屏 metrics 正确、但 surface resize 期间引擎
//    把最终布局帧丢了（视觉停在动画中途、触摸已在全屏位）。修复在
//    slash 提交后的补帧窗口内：收到「表面恢复全屏、inset 归零」的
//    终态 metrics 时对根 RenderView 标脏（当帧 + 次帧各一次）强制
//    重提 scene；另有提交后 200ms 的兜底标脏。以下测试用标脏计数
//    与帧泵送钉死该行为；窗口外的 metrics 抖动零补帧（零常态开销）。
// 4. IME hide（表面 580→780）后视口恢复全屏、层整体回落，「取消」
//    按钮真实命中并生效。
//
// 表面设定：dpr=1、宽 360；压缩态高 584（对齐真机压缩逻辑高），
// 常规态高 780、键盘高 200（弹起态表面压到 580）。

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:echo/src/app/echo_app.dart';
import 'package:echo/src/control/bootstrap.dart';
import 'package:echo/src/control/slash_ui/slash_ui.dart';
import 'package:echo/src/diary/data/in_memory_diary_repository.dart';
import 'package:echo/src/navigation/dock_geometry.dart';
import 'package:echo/src/navigation/widgets/search_capsule.dart';
import 'package:echo/src/services/window_inset_refresher.dart';

import '../control/control_test_harness.dart';

/// 搜索胶囊内的输入框（R6 起终端页也有 TextField，不能裸定位）。
final Finder searchField = find.descendant(
  of: find.byType(SearchCapsule),
  matching: find.byType(TextField),
);

/// 压缩画布逻辑高（≈真机压缩的 1751px÷3）：0.45 上限=262.8，而完整
/// 带参 prune 的补全条+确认卡固有高约 372——旧结构实测溢出 109px。
const double kCompressedHeight = 584;

/// 常规态键盘高（逻辑像素）：adjustResize 下窗口表面被压到
/// 780-200=580（≈真机压缩逻辑高 584）。
const double kKeyboardHeight = 200;

void main() {
  late final InMemoryDiaryRepository diaryRepo;
  setUpAll(() {
    diaryRepo = InMemoryDiaryRepository(seedDebugData: true);
    addTearDown(diaryRepo.dispose);
    // fake-async 下把兜底标脏延时缩短：submitPrune 末尾有 200ms
    // pump，足够让 50ms 的兜底定时器触发并完成两帧标脏。
    WindowInsetRefresher.fallbackDelayOverride = const Duration(
      milliseconds: 50,
    );
    // 纯几何用例（不验补帧窗口时序）把窗口缩到 100ms，使既有的
    // 200ms pump 自然越过窗口超时，避免悬挂 Timer；验窗口/终态时序
    // 的用例显式恢复生产默认（1.2s）。
    WindowInsetRefresher.windowOverride = const Duration(milliseconds: 100);
    addTearDown(() {
      WindowInsetRefresher.fallbackDelayOverride = null;
      WindowInsetRefresher.windowOverride = null;
    });
  });

  late ControlHarness h;

  /// 静音触感通道（长按展开搜索会 fire-and-forget 触发 Haptics.confirm；
  /// 含 runAsync 的用例里其异步错误会在真实区刷出导致用例失败）。
  void mockHaptics(WidgetTester tester) {
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('echo/haptics'),
      (call) async => null,
    );
  }

  Future<void> boot(WidgetTester tester, double height) async {
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

    tester.view
      ..devicePixelRatio = 1.0
      ..physicalSize = Size(360, height);
    addTearDown(tester.view.reset);

    // 每个用例从干净的补帧器单例开始（基线取本用例 boot 高度）。
    WindowInsetRefresher.debugReset();
    addTearDown(WindowInsetRefresher.debugReset);

    mockHaptics(tester);
    await tester.pumpWidget(EchoApp(diaryRepository: diaryRepo));
    await tester.pump();
  }

  /// 长按导航条展开搜索并点胶囊聚焦。坐标按 DockGeometry 从表面高度推算。
  Future<void> openAndFocusSearch(WidgetTester tester, double imeInset) async {
    final height = tester.view.physicalSize.height;
    // 导航条：顶 = h-16-10；扩大热区 [h-58, h-6)，x=250 在条身内、
    // 避开两端圆点热区（156..186 / 326..356）。
    await tester.longPressAt(Offset(250, height - 21));
    await tester.pump(const Duration(milliseconds: 500));
    expect(searchField, findsOneWidget, reason: '搜索已展开');
    // 胶囊中心：adjustResize 下其全局底边 = h - inset - 16（body 被压
    // 缩时 Positioned bottom:16 的全局位置恰好等于屏高减键盘再减 16）。
    await tester.tapAt(
      Offset(180, height - imeInset - DockGeometry.bottomMargin - 22),
    );
    await tester.pump(const Duration(milliseconds: 100));
  }

  /// 触屏 IME「完成」提交 /diary.prune，并越过 150ms 失焦定时器与
  /// 50ms 补帧兜底定时器。
  ///
  /// flutter_test 下 done 会同步先 unfocus 再 onSubmitted（见
  /// EditableText._finalizeEditing）；retainsOnUnfocus 为 true，
  /// 确认卡必须保住（G4-BUG-1）。补帧器自身的时序在独立用例里钉。
  Future<void> submitPrune(WidgetTester tester) async {
    await tester.enterText(searchField, '/diary.prune --before 2026-10-01');
    await tester.pump();
    await tester.showKeyboard(searchField);
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();

    // 越过 50ms 兜底补帧定时器与宿主 150ms 失焦检查定时器；
    // retainsOnUnfocus 为 true，面板/确认卡不得被收起。
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.text('执行 3 级破坏性命令'), findsOneWidget);
  }

  /// 模拟 adjustResize 的窗口物理压缩/恢复：键盘弹起时系统直接改
  /// 窗口 frame（引擎表面高度变化），IME 不与窗口重叠，viewInsets
  /// 始终为 0——测试以改 surface 高度忠实复现，而不是设 viewInsets。
  Future<void> resizeSurface(WidgetTester tester, double height) async {
    tester.view.physicalSize = Size(360, height);
    await tester.pump();
  }

  SlashConsoleController slashOf(WidgetTester tester) => tester
      .widget<SlashCommandLayer>(find.byType(SlashCommandLayer))
      .controller;

  Rect layerRect(WidgetTester tester) =>
      tester.getRect(find.byType(SlashCommandLayer));

  /// 断言 [inner] 完全落在 [outer] 内（溢出区 hitTest 恒 false，这正是
  /// 真机「可见不可点」的直接机理，必须逐点钉死）。
  void expectFullyInside(Rect outer, Rect inner, String what) {
    expect(
      inner.top >= outer.top - 0.5 &&
          inner.bottom <= outer.bottom + 0.5 &&
          inner.left >= outer.left - 0.5 &&
          inner.right <= outer.right + 0.5,
      isTrue,
      reason:
          '$what 必须完整落在 SlashCommandLayer 内：'
          'outer=$outer inner=$inner',
    );
  }

  // ------------------------------------------------------------------
  //  根因二：压缩画布高度（584，对齐真机压缩逻辑高）下确认卡可点
  // ------------------------------------------------------------------

  testWidgets('压缩画布：确认卡无 overflow，「取消」命中并生效', (tester) async {
    await boot(tester, kCompressedHeight);
    await openAndFocusSearch(tester, 0);
    await submitPrune(tester);

    expect(tester.takeException(), isNull, reason: '确认卡布局不得溢出');
    final slash = slashOf(tester);
    expect(slash.confirmPending, isNotNull);

    // G4-BUG-1 闸门保卡：越过 150ms 失焦定时器后搜索框无焦点（widget
    // 测试里 done 同步失焦），但 retainsOnUnfocus=true（_confirm 挂账），
    // 确认卡必须完整保留——下方三个按钮的 Layer 内命中断言与真实 tap
    // 即钉死该行为，另两个压缩用例（X / PIN 全链路）同理覆盖。
    final searchFocus = tester.widget<TextField>(searchField).focusNode;
    expect(searchFocus, isNotNull);
    expect(searchFocus!.hasFocus, isFalse);
    expect(find.text('执行 3 级破坏性命令'), findsOneWidget);

    final outer = layerRect(tester);
    // 面板顶边钉在 y=40，底边贴着胶囊上沿：高度自适应撑满两者之间。
    expect(outer.top, closeTo(DockGeometry.slashPanelTop, 0.5));
    expect(
      outer.height,
      closeTo(
        kCompressedHeight -
            DockGeometry.slashPanelTop -
            (DockGeometry.bottomMargin + DockGeometry.searchHeight + 8),
        0.5,
      ),
    );
    // viewInsets=0 时 adjustResize 无需压缩 body，层内逻辑高即表面高。
    final layerContext = tester.element(find.byType(SlashCommandLayer));
    expect(MediaQuery.sizeOf(layerContext), const Size(360, kCompressedHeight));
    expect(MediaQuery.viewInsetsOf(layerContext).bottom, 0);

    final cancel = tester.getRect(find.text('取消'));
    final confirm = tester.getRect(find.text('确认执行'));
    final close = tester.getRect(find.byIcon(Icons.close));
    expectFullyInside(outer, cancel, '取消按钮');
    expectFullyInside(outer, confirm, '确认执行按钮');
    expectFullyInside(outer, close, '右上角 X');

    await tester.tap(find.text('取消'));
    await tester.pump();
    expect(tester.takeException(), isNull);
    expect(slash.confirmPending, isNull);
    expect(find.text('执行 3 级破坏性命令'), findsNothing);
    // 取消后指令态仍在、输入框未被关闭。
    expect(searchField, findsOneWidget);
  });

  testWidgets('压缩画布：确认卡右上角 X 命中并取消', (tester) async {
    await boot(tester, kCompressedHeight);
    await openAndFocusSearch(tester, 0);
    await submitPrune(tester);
    expect(tester.takeException(), isNull);

    final outer = layerRect(tester);
    expectFullyInside(outer, tester.getRect(find.byIcon(Icons.close)), 'X');

    await tester.tap(find.byIcon(Icons.close));
    await tester.pump();
    expect(slashOf(tester).confirmPending, isNull);
    expect(find.text('执行 3 级破坏性命令'), findsNothing);
  });

  // ------------------------------------------------------------------
  //  PIN 全链路（确认执行 → AUTH_REQUIRED → 首装两输 → 重放）
  //  在压缩画布高度下逐按钮可点
  // ------------------------------------------------------------------

  testWidgets('压缩画布：确认执行 → PIN 首装两输，全部按钮在层内可点', (tester) async {
    await boot(tester, kCompressedHeight);
    await openAndFocusSearch(tester, 0);
    await submitPrune(tester);
    expect(tester.takeException(), isNull);

    // 确认执行 → AUTH_REQUIRED → 首装面板（isPinSet 走真实 IO，
    // 与 slash_layer_widget_test 同法，IO 段置于 runAsync）。
    await tester.runAsync(() async {
      await tester.tap(find.text('确认执行'));
      for (var i = 0; i < 300; i++) {
        if (slashOf(tester).pinSheet.visible) break;
        await Future<void>.delayed(const Duration(milliseconds: 5));
      }
    });
    await tester.pump();
    expect(find.text('首次使用 · 设置 PIN'), findsOneWidget);
    expect(tester.takeException(), isNull);

    var outer = layerRect(tester);
    expect(outer.top, closeTo(DockGeometry.slashPanelTop, 0.5));
    expectFullyInside(outer, tester.getRect(find.text('确定')), 'PIN 确定');
    expectFullyInside(outer, tester.getRect(find.byIcon(Icons.close)), 'PIN X');

    // 第一遍：本地阶段切换。
    await tester.enterText(find.byType(TextField).last, '1234');
    await tester.pump();
    await tester.tap(find.text('确定'));
    await tester.pump();
    expect(find.text('再输入一遍 PIN'), findsOneWidget);

    // 第二遍：set-pin 落盘 → unlock 校验 → 重放 prune。
    await tester.enterText(find.byType(TextField).last, '1234');
    await tester.pump();
    await tester.runAsync(() async {
      await tester.tap(find.text('确认'));
      for (var i = 0; i < 300; i++) {
        if (slashOf(tester).core.entries.length == 2) break;
        await Future<void>.delayed(const Duration(milliseconds: 5));
      }
    });
    await tester.pump();
    expect(tester.takeException(), isNull);
    expect(slashOf(tester).core.entries, hasLength(2));

    outer = layerRect(tester);
    expect(outer.top, closeTo(DockGeometry.slashPanelTop, 0.5));
  });

  /// 用例内恢复生产默认补帧窗口（1.2s）；用例结束还原为短窗口。
  void useProductionWindow() {
    WindowInsetRefresher.windowOverride = null;
    addTearDown(
      () => WindowInsetRefresher.windowOverride = const Duration(
        milliseconds: 100,
      ),
    );
  }

  // ------------------------------------------------------------------
  //  adjustResize 键盘弹起几何 + 补帧器时序
  // ------------------------------------------------------------------

  testWidgets('IME 弹起：窗口表面压到键盘顶缘，胶囊/指令层停在键盘上方；'
      '提交后补帧窗口打开并兜底标脏', (tester) async {
    useProductionWindow();
    const fullHeight = 780.0;
    const compressedHeight = fullHeight - kKeyboardHeight;
    await boot(tester, fullHeight);
    await openAndFocusSearch(tester, 0);
    // 键盘弹起：adjustResize 把窗口表面物理压到 580（非 viewInsets）。
    await resizeSurface(tester, compressedHeight);

    expect(WindowInsetRefresher.debugWindowActive, isFalse);
    await submitPrune(tester);
    expect(tester.takeException(), isNull);

    // 提交即打开补帧窗口；越过 50ms 兜底定时器 + 200ms pump 后，
    // 兜底已对根 RenderView 标脏（当帧 + 次帧跟进 = 2 次）。
    expect(WindowInsetRefresher.debugWindowActive, isTrue);
    expect(
      WindowInsetRefresher.debugForcedFrameCount,
      greaterThanOrEqualTo(2),
      reason: '兜底定时器必须在压缩态也产出两帧标脏（内容不变、无视觉扰动）',
    );

    final layerContext = tester.element(find.byType(SlashCommandLayer));
    // 表面即逻辑画布：580 高；IME 在窗口之外，viewInsets 恒 0。
    expect(MediaQuery.sizeOf(layerContext), const Size(360, compressedHeight));
    expect(MediaQuery.viewInsetsOf(layerContext).bottom, 0);

    // 键盘顶缘 y=580；胶囊底边 = 580-16=564，层底边 = 580-16-44-8=512。
    final capsule = tester.getRect(
      find.byKey(const ValueKey<String>('capsule')),
    );
    final outer = layerRect(tester);
    expect(
      capsule.bottom,
      closeTo(compressedHeight - DockGeometry.bottomMargin, 0.5),
    );
    expect(capsule.bottom, lessThan(compressedHeight));
    expect(
      outer.bottom,
      closeTo(
        compressedHeight -
            DockGeometry.bottomMargin -
            DockGeometry.searchHeight -
            8,
        0.5,
      ),
    );
    expect(outer.bottom, lessThan(compressedHeight));
    // 压缩表面（580 ≈ 真机压缩 584）下面板从 y=40 撑到胶囊上沿，
    // 确认卡按钮仍必须完整落在层内。
    expect(outer.top, closeTo(DockGeometry.slashPanelTop, 0.5));
    expectFullyInside(outer, tester.getRect(find.text('取消')), '取消按钮');
    expectFullyInside(outer, tester.getRect(find.text('确认执行')), '确认执行按钮');

    // 越过 1.2s 补帧窗口，避免 fake-async 悬挂窗口超时定时器。
    await tester.pump(const Duration(milliseconds: 1100));
    expect(WindowInsetRefresher.debugWindowActive, isFalse);
  });

  testWidgets('IME hide（表面 580→780）：终态全屏 metrics 触发当帧+次帧补绘，'
      '视口恢复、层回落、按钮真实命中', (tester) async {
    useProductionWindow();
    const fullHeight = 780.0;
    const compressedHeight = fullHeight - kKeyboardHeight;
    await boot(tester, fullHeight);
    await openAndFocusSearch(tester, 0);
    await resizeSurface(tester, compressedHeight);
    await submitPrune(tester);

    // 压缩态：层底边 512。
    final before = layerRect(tester);
    expect(
      before.bottom,
      closeTo(
        compressedHeight -
            DockGeometry.bottomMargin -
            DockGeometry.searchHeight -
            8,
        0.5,
      ),
    );

    // 模拟 IME hide 的终态 metrics：窗口 frame 恢复全屏 780。
    // 真机上布局/hit-test 此刻已正确、只是最终帧被 surface resize
    // 吞掉——补帧器必须在收到这条 metrics 的同一泵内标脏一次，并在
    // 该帧结束后（下一次泵）再标脏一次（覆盖 resize 晚完成的时序）。
    final marksBefore = WindowInsetRefresher.debugForcedFrameCount;
    await resizeSurface(tester, fullHeight);
    expect(
      WindowInsetRefresher.debugForcedFrameCount - marksBefore,
      greaterThanOrEqualTo(1),
      reason: '终态全屏 metrics 必须立刻标脏根 RenderView',
    );
    await tester.pump();
    expect(
      WindowInsetRefresher.debugForcedFrameCount - marksBefore,
      greaterThanOrEqualTo(2),
      reason: '次帧跟进必须再标脏一次（N+1 帧对齐 surface）',
    );

    final layerContext = tester.element(find.byType(SlashCommandLayer));
    expect(MediaQuery.sizeOf(layerContext), const Size(360, fullHeight));
    expect(MediaQuery.viewInsetsOf(layerContext).bottom, 0);

    final after = layerRect(tester);
    // 层随表面恢复整体下移键盘高度（512→712）；约束放宽后固有内容
    // 可能变高，故只钉底边与回落量。
    expect(after.bottom, closeTo(before.bottom + kKeyboardHeight, 0.5));
    expect(
      after.bottom,
      closeTo(
        fullHeight - DockGeometry.bottomMargin - DockGeometry.searchHeight - 8,
        0.5,
      ),
    );
    expect(after.top, closeTo(DockGeometry.slashPanelTop, 0.5));
    expect(
      after.height,
      closeTo(
        fullHeight -
            DockGeometry.slashPanelTop -
            (DockGeometry.bottomMargin + DockGeometry.searchHeight + 8),
        0.5,
      ),
    );
    expect(tester.takeException(), isNull);

    // 真机阻断点：收起后的「取消」必须真实命中。
    final cancel = tester.getRect(find.text('取消'));
    final confirm = tester.getRect(find.text('确认执行'));
    expectFullyInside(after, cancel, '取消按钮');
    expectFullyInside(after, confirm, '确认执行按钮');
    await tester.tap(find.text('取消'));
    await tester.pump();
    expect(slashOf(tester).confirmPending, isNull);

    // 越过 1.2s 补帧窗口，避免 fake-async 悬挂窗口超时定时器。
    await tester.pump(const Duration(milliseconds: 1100));
    expect(WindowInsetRefresher.debugWindowActive, isFalse);
  });

  testWidgets('补帧窗口外的 metrics 抖动不产生任何补帧（零常态开销）', (tester) async {
    const fullHeight = 780.0;
    await boot(tester, fullHeight);
    await openAndFocusSearch(tester, 0);

    // 普通搜索态下键盘弹起/收起（无 slash 提交 → 补帧窗口从未打开）：
    // 无论 surface 怎么变，标脏计数必须恒为 0。
    expect(WindowInsetRefresher.debugWindowActive, isFalse);
    expect(WindowInsetRefresher.debugForcedFrameCount, 0);
    await resizeSurface(tester, fullHeight - kKeyboardHeight);
    await tester.pump(const Duration(milliseconds: 300));
    await resizeSurface(tester, fullHeight);
    await tester.pump(const Duration(milliseconds: 300));
    expect(WindowInsetRefresher.debugForcedFrameCount, 0);
    expect(WindowInsetRefresher.debugWindowActive, isFalse);
  });

  testWidgets('补帧窗口超时后到达的全屏 metrics 不再补帧', (tester) async {
    useProductionWindow();
    const fullHeight = 780.0;
    const compressedHeight = fullHeight - kKeyboardHeight;
    await boot(tester, fullHeight);
    await openAndFocusSearch(tester, 0);
    await resizeSurface(tester, compressedHeight);
    await submitPrune(tester);
    expect(WindowInsetRefresher.debugWindowActive, isTrue);

    // 越过默认 1.2s 窗口（200ms 已在 submitPrune 内泵过）。
    await tester.pump(const Duration(milliseconds: 1100));
    expect(WindowInsetRefresher.debugWindowActive, isFalse);
    final marksAtClose = WindowInsetRefresher.debugForcedFrameCount;

    // 窗口关闭后才恢复全屏（极端时序）：不再补帧——窗口外零开销，
    // 框架自身随 metrics 的常规产帧在健康设备上本就足够。
    await resizeSurface(tester, fullHeight);
    await tester.pump();
    expect(WindowInsetRefresher.debugForcedFrameCount, marksAtClose);
  });
}
