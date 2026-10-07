import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:echo/src/app/echo_app.dart';
import 'package:echo/src/navigation/smart_nav_screen.dart';
import 'package:echo/src/navigation/widgets/ai_dialog.dart';
import 'package:echo/src/navigation/widgets/handle_menu.dart';
import 'package:echo/src/navigation/widgets/nav_roller.dart';
import 'package:echo/src/navigation/widgets/quick_action_arc.dart';
import 'package:echo/src/navigation/widgets/side_drawer.dart';
import 'package:echo/src/pages/chat_page.dart';
import 'package:echo/src/pages/template_page.dart';
import 'package:echo/src/services/nav_badge_service.dart';

/// 以 16ms 为步长逐帧推进 [ms] 毫秒。
///
/// 必须逐帧 pump：在 widget 测试里单次 `pump(Duration)` 只触发一帧，
/// 组件挂载当帧启动的 Ticker 拿不到逐帧回调，入场动画会停在 0。
Future<void> pumpFramesMs(WidgetTester tester, int ms) async {
  final frames = (ms / 16).ceil();
  for (var i = 0; i < frames; i++) {
    await tester.pump(const Duration(milliseconds: 16));
  }
}

void main() {
  testWidgets('初始展示 4 页：聊天页为会话列表骨架，其余 3 页为占位页', (tester) async {
    // 构建应用
    await tester.pumpWidget(const EchoApp());
    await tester.pump();

    // 智能导航屏在树上；聊天页已换成 ChatPage，其余 3 页仍是占位页
    expect(find.byType(SmartNavScreen), findsOneWidget);
    expect(find.byType(ChatPage), findsOneWidget);
    expect(find.byType(TemplatePage), findsNWidgets(3));

    // 首个占位页内的标题文本为「控制台」（页内另有测试按钮文字，
    // 故按标题精确匹配）
    final firstPageText = tester.widget<Text>(
      find.descendant(
        of: find.byType(TemplatePage).first,
        matching: find.text('控制台'),
      ),
    );
    expect(firstPageText.data, '控制台');
  });

  testWidgets('搜索真实闭环：长按展开 → 输入页面名 → 点结果跳转', (tester) async {
    // 测试表面 800×600；胶囊隐形热区约 x:362~794, y:542~585。
    await tester.pumpWidget(const EchoApp());
    await tester.pump();

    // 第 2 页（聊天）已是 ChatPage，用其列表组件作为页面位置标记
    final chatPageMarker = find.byKey(const ValueKey<String>('chat-page-list'));
    // 初始时聊天页虽在树上但在屏幕右侧（中心 x≈1200）
    expect(tester.getCenter(chatPageMarker).dx, greaterThan(800));

    // 长按胶囊区域 → 展开搜索（倒计时 ticker 会持续运行，
    // 因此这里手动推进时间而不用 pumpAndSettle）
    await tester.longPressAt(const Offset(600, 560));
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.byType(TextField), findsOneWidget);
    // 无真实历史时显示空状态提示
    expect(find.text('暂无最近搜索'), findsOneWidget);

    // 点击搜索框聚焦（倒计时取消），输入「聊天」
    await tester.tapAt(const Offset(500, 560));
    await tester.pump(const Duration(milliseconds: 200));
    await tester.enterText(find.byType(TextField), '聊天');
    await tester.pump();

    // 实时出现搜索结果：「聊天」同时存在于输入框与结果标题中，
    // 故用唯一的来源标签「页面」确认结果行存在
    expect(find.text('页面'), findsOneWidget);

    // 点击结果行（点来源标签处，事件冒泡到结果行的点击区域）
    // → 跳转到聊天页（中心 x 应≈400）
    await tester.tap(find.text('页面'));
    // 手动推进，等待吸附物理完全落位（最长约 5 秒）
    double pageCenterX() => tester.getCenter(chatPageMarker).dx;
    var settled = false;
    for (var i = 0; i < 300 && !settled; i++) {
      await tester.pump(const Duration(milliseconds: 16));
      settled = (pageCenterX() - 400).abs() < 0.5;
    }
    expect(pageCenterX(), closeTo(400, 0.5));

    // 再次长按展开搜索：结果点击已记入历史。
    await tester.longPressAt(const Offset(600, 560));
    await tester.pump(const Duration(milliseconds: 500));
    // 聊天页仍在树上；且「聊天」历史胶囊（带省略号样式）出现一次。
    // 滚筒页名标签常驻树上但不属于历史胶囊，故按样式谓词精确断言。
    expect(chatPageMarker, findsOneWidget);
    final historyChip = find.byWidgetPredicate(
      (w) => w is Text && w.data == '聊天' && w.overflow == TextOverflow.ellipsis,
    );
    expect(historyChip, findsOneWidget);
  });

  testWidgets('横滑松手后立即上甩：滚筒先关闭，快捷弧不叠加', (tester) async {
    await tester.pumpWidget(const EchoApp());
    await tester.pump();

    // 滚筒整体显隐用的最外层 AnimatedOpacity
    Finder rollerOpacity() => find
        .descendant(
          of: find.byType(NavRoller),
          matching: find.byType(AnimatedOpacity),
        )
        .first;

    // ---- 第一次手势：横滑（滚筒出现）后松手 ----
    final g1 = await tester.createGesture();
    await g1.down(const Offset(600, 560));
    await tester.pump();
    // 分段左移（触发横滑方向锁定，累计约 120px）
    await g1.moveTo(const Offset(590, 560));
    await g1.moveTo(const Offset(560, 560));
    await g1.moveTo(const Offset(530, 560));
    await g1.moveTo(const Offset(500, 560));
    await g1.moveTo(const Offset(480, 560));
    await tester.pump();
    expect(
      tester.widget<AnimatedOpacity>(rollerOpacity()).opacity,
      1,
      reason: '横滑中滚筒应可见',
    );

    await g1.up();
    // 等待吸附落位（弹簧约 0.4s 内完成）
    for (var i = 0; i < 30; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
    // 落位后 650ms 内滚筒仍显示
    await tester.pump(const Duration(milliseconds: 200));
    expect(
      tester.widget<AnimatedOpacity>(rollerOpacity()).opacity,
      1,
      reason: '落位后短时间内滚筒仍应可见',
    );

    // ---- 第二次手势：立即上甩 ----
    final g2 = await tester.createGesture();
    await g2.down(const Offset(600, 560));
    await tester.pump();
    await g2.moveTo(const Offset(600, 528));
    await tester.pump();

    // 快捷弧显示，且滚筒已被立即关闭
    expect(find.byType(QuickActionArc), findsOneWidget);
    expect(
      tester.widget<AnimatedOpacity>(rollerOpacity()).opacity,
      0,
      reason: '上甩时滚筒应立即关闭',
    );
  });

  testWidgets('点击右端圆点：按下即翻到聊天页', (tester) async {
    // 表面 800×600：整体导航位于 x 400..800、y 574..584。
    await tester.pumpWidget(const EchoApp());
    await tester.pump();

    // 聊天页（第 2 页）已是 ChatPage，用其列表组件作为位置标记
    final chatPageMarker = find.byKey(const ValueKey<String>('chat-page-list'));
    expect(tester.getCenter(chatPageMarker).dx, greaterThan(800));

    // 右圆点中心≈(781, 579)，热区 20 宽；点其热区（按下即触发）
    await tester.tapAt(const Offset(781, 560));

    // 等待吸附落位
    double pageCenterX() => tester.getCenter(chatPageMarker).dx;
    var settled = false;
    for (var i = 0; i < 300 && !settled; i++) {
      await tester.pump(const Duration(milliseconds: 16));
      settled = (pageCenterX() - 400).abs() < 0.5;
    }
    expect(pageCenterX(), closeTo(400, 0.5));
  });

  testWidgets('导航锚点：停留才算已读，快速扫过/双击跳转不读中转页；'
      '异常须处理完成才恢复', (tester) async {
    await tester.pumpWidget(const EchoApp());
    await tester.pump();

    // 读取第 i 页锚点的当前逻辑状态。锚点始终全部挂载（被滑块
    // 物理遮挡时组件仍在），直接读 widget 即可。
    NavBadgeLevel anchorLevel(int i) {
      final widget = tester.widget(
        find.byKey(ValueKey<String>('nav-anchor-$i')),
      );
      return (widget as dynamic).level as NavBadgeLevel;
    }

    /// 锚点短条当前绘制颜色（随动画每帧变化）。
    Color anchorColor(int i) {
      final box = tester.widget<DecoratedBox>(
        find
            .descendant(
              of: find.byKey(ValueKey<String>('nav-anchor-$i')),
              matching: find.byType(DecoratedBox),
            )
            .first,
      );
      return (box.decoration as BoxDecoration).color!;
    }

    // 初始：4 个锚点全部挂载（首页锚点在滑块下方被物理遮挡），
    // 逻辑状态均为正常。
    for (var i = 0; i < 4; i++) {
      expect(find.byKey(ValueKey<String>('nav-anchor-$i')), findsOneWidget);
      expect(anchorLevel(i), NavBadgeLevel.normal);
    }

    // ---- 控制台模拟：聊天新消息 + 日志报错 ----
    await tester.tap(find.text('模拟：聊天新消息'));
    await tester.pump();
    expect(anchorLevel(1), NavBadgeLevel.notification);

    // 回归：呼吸动画必须随时间自行推进，不能依赖触控才刷新——
    // 只推进时间、不触发任何其他重建，颜色就应发生变化。
    final colorAtTap = anchorColor(1);
    await tester.pump(const Duration(milliseconds: 300));
    expect(
      anchorColor(1),
      isNot(equals(colorAtTap)),
      reason: '锚点光效应自动推进，无触控时不能冻结',
    );

    await tester.tap(find.text('模拟：日志报错'));
    await tester.pump();
    expect(anchorLevel(2), NavBadgeLevel.exception);

    /// 等待页面吸附落位（圆点翻页为弹簧动画，最长约 5 秒）。
    Future<void> settlePage(Finder pageText) async {
      var settled = false;
      for (var i = 0; i < 300 && !settled; i++) {
        await tester.pump(const Duration(milliseconds: 16));
        settled = (tester.getCenter(pageText).dx - 400).abs() < 0.5;
      }
    }

    // 先收起模拟按钮弹出的 SnackBar——它覆盖在底部会挡住导航条热区。
    ScaffoldMessenger.of(tester.element(find.byType(Scaffold).first))
        .clearSnackBars();
    for (
      var i = 0;
      i < 30 && find.byType(SnackBar).evaluate().isNotEmpty;
      i++
    ) {
      await tester.pump(const Duration(milliseconds: 16));
    }

    /// 第 i 个目的地页的位置标记：聊天页（i=1）已换成 ChatPage，
    /// 用其 ListView；其余三页仍是 TemplatePage 标题。
    /// 注意 TemplatePage 序列中控制台/日志/我依次为 0/1/2
    /// （聊天页不在该序列内）。
    Finder pageMarker(int i) {
      if (i == 1) {
        return find.byKey(const ValueKey<String>('chat-page-list'));
      }
      final templateIndex = switch (i) {
        0 => 0,
        2 => 1,
        _ => 2,
      };
      return find
          .descendant(
            of: find.byType(TemplatePage).at(templateIndex),
            matching: find.byType(Text),
          )
          .first;
    }

    // ---- 双击导航条直达末页：途中经过的页面不算已读 ----
    await tester.tapAt(const Offset(700, 580));
    await tester.tapAt(const Offset(700, 580));
    await settlePage(pageMarker(3));
    expect(tester.getCenter(pageMarker(3)).dx, closeTo(400, 0.5));
    expect(
      anchorLevel(1),
      NavBadgeLevel.notification,
      reason: '双击直达途中经过聊天页，不应判定已读',
    );
    expect(anchorLevel(2), NavBadgeLevel.exception);

    /// 点左圆点，并只推进到激活页切换（越过 destination 中点，
    /// 该页标题中心越过屏幕左缘 0）——模拟快速连点：每"页"停留
    /// 远不到已读阈值。
    Future<void> fastStepLeft(int destination) async {
      await tester.tapAt(const Offset(391, 560));
      for (
        var i = 0;
        i < 60 && tester.getCenter(pageMarker(destination)).dx < 0;
        i++
      ) {
        await tester.pump(const Duration(milliseconds: 8));
      }
    }

    // ---- 连点左圆点快速扫回首页：经过聊天页也不算已读 ----
    await fastStepLeft(2);
    await fastStepLeft(1);
    await fastStepLeft(0);
    await settlePage(pageMarker(0));
    await tester.pump(const Duration(milliseconds: 750));
    expect(anchorLevel(1), NavBadgeLevel.notification, reason: '快速扫过不应判定已读');
    expect(anchorLevel(2), NavBadgeLevel.exception);

    // ---- 真正翻到聊天页并停留：落位时仍未读，停留够久才已读 ----
    await tester.tapAt(const Offset(781, 560));
    await settlePage(pageMarker(1));
    expect(anchorLevel(1), NavBadgeLevel.notification, reason: '刚落位、停留未达阈值');
    // 当前页锚点仍挂载，只是被不透明滑块物理遮挡（无显隐逻辑）
    expect(find.byKey(const ValueKey<String>('nav-anchor-1')), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 750));
    expect(anchorLevel(1), NavBadgeLevel.normal);
    expect(anchorLevel(2), NavBadgeLevel.exception);

    // ---- 再翻到日志页：仅查看不解除异常，按钮可处理 ----
    await tester.tapAt(const Offset(781, 560));
    await settlePage(pageMarker(2));
    // 离开聊天页：锚点始终在树上（覆盖/揭示都靠物理遮挡）
    expect(find.byKey(const ValueKey<String>('nav-anchor-1')), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 750));
    expect(
      anchorLevel(2),
      NavBadgeLevel.exception,
      reason: '异常未处理完成，查看页面不应改变状态',
    );
    expect(find.text('处理异常'), findsOneWidget);

    // 处理完成 → 锚点恢复，按钮变为禁用文案
    await tester.tap(find.text('处理异常'));
    await tester.pump();
    expect(anchorLevel(2), NavBadgeLevel.normal);
    expect(find.text('当前无待处理异常'), findsOneWidget);
  });

  testWidgets('返回键：搜索 open/input 态与快捷弧先关闭不退出；'
      '常规态行为不变', (tester) async {
    await tester.pumpWidget(const EchoApp());
    await tester.pump();

    // 记录 App 退出请求（唯一路由被 pop 时框架调用 SystemNavigator.pop）。
    final exitRequests = <MethodCall>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'SystemNavigator.pop') exitRequests.add(call);
        return null;
      },
    );

    /// 模拟 Android 系统返回键。
    Future<void> back() => tester.binding.handlePopRoute();

    /// 逐帧推进直到条件成立（上限约 1s，覆盖面板 720ms 退场时间轴）。
    Future<bool> pumpUntil(bool Function() condition) async {
      for (var i = 0; i < 64; i++) {
        if (condition()) return true;
        await tester.pump(const Duration(milliseconds: 16));
      }
      return condition();
    }

    // ---- ① open 态返回：关闭搜索，不退出 ----
    await tester.longPressAt(const Offset(600, 560));
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.byType(TextField), findsOneWidget, reason: '搜索已展开');

    exitRequests.clear();
    await back();
    expect(
      await pumpUntil(() => find.byType(TextField).evaluate().isEmpty),
      isTrue,
      reason: '返回键应收起 open 态搜索',
    );
    expect(exitRequests, isEmpty, reason: 'open 态返回不应退出 App');

    // ---- ② input 态返回：关闭搜索，不退出 ----
    await tester.longPressAt(const Offset(600, 560));
    await tester.pump(const Duration(milliseconds: 500));
    await tester.tapAt(const Offset(500, 560));
    await tester.pump(const Duration(milliseconds: 200));
    await tester.enterText(find.byType(TextField), '聊天');
    await tester.pump();
    expect(find.text('页面'), findsOneWidget, reason: 'input 态已有实时结果');

    exitRequests.clear();
    await back();
    expect(
      await pumpUntil(() => find.byType(TextField).evaluate().isEmpty),
      isTrue,
      reason: '返回键应收起 input 态搜索',
    );
    expect(exitRequests, isEmpty, reason: 'input 态返回不应退出 App');

    // ---- ③ 快捷弧返回：弧收起，不退出 ----
    final g = await tester.createGesture();
    await g.down(const Offset(600, 560));
    await tester.pump();
    await g.moveTo(const Offset(600, 528));
    await tester.pump();
    expect(find.byType(QuickActionArc), findsOneWidget);

    exitRequests.clear();
    await back();
    expect(
      await pumpUntil(() => find.byType(QuickActionArc).evaluate().isEmpty),
      isTrue,
      reason: '返回键应收起快捷弧',
    );
    expect(exitRequests, isEmpty, reason: '快捷弧返回不应退出 App');
    // 模拟手指松开：弧已由返回键收起，此次释放不触发任何操作。
    await g.up();
    await tester.pump();

    // ---- ④ 常规态返回：默认行为不变（退出 App）----
    await back();
    await tester.pump(const Duration(milliseconds: 50));
    expect(exitRequests, hasLength(1), reason: '常规态返回应保留默认退出行为');
  });

  // 800×600 表面下的几何：
  // 把手 x14..110（中心 62）、AI 条 x124..372（中心 248）、
  // 条顶 y=574，热区上下扩到 542/594；竖单在把手位向上生长，
  // 抽屉宽 340，全开时把手停靠 x354..450。
  testWidgets('把手点按：竖单生长出 3 个占位按钮；返回键/点遮罩收起', (tester) async {
    await tester.pumpWidget(const EchoApp());
    await tester.pump();

    // 初始只有常态把手，没有竖单。
    expect(find.byKey(const ValueKey<String>('handle-bar')), findsOneWidget);
    expect(find.byType(HandleMenu), findsNothing);

    // 点按把手条 → 竖单挂载并生长。
    await tester.tapAt(const Offset(62, 579));
    await tester.pump();
    expect(find.byType(HandleMenu), findsOneWidget);
    // 等生长动画（340ms）与按钮错峰弹入完成。
    await pumpFramesMs(tester, 400);

    // 竖单期间常态把手隐藏（同帧交接），三个图标按钮就位。
    expect(find.byKey(const ValueKey<String>('handle-bar')), findsNothing);
    expect(
      find.descendant(
        of: find.byType(HandleMenu),
        matching: find.byIcon(Icons.refresh),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byType(HandleMenu),
        matching: find.byIcon(Icons.ios_share),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byType(HandleMenu),
        matching: find.byIcon(Icons.push_pin_outlined),
      ),
      findsOneWidget,
    );

    // 系统返回键：先收竖单，不退出 App。
    final exitRequests = <MethodCall>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'SystemNavigator.pop') exitRequests.add(call);
        return null;
      },
    );
    await tester.binding.handlePopRoute();
    var closed = false;
    for (var i = 0; i < 48 && !closed; i++) {
      await tester.pump(const Duration(milliseconds: 16));
      closed = find.byType(HandleMenu).evaluate().isEmpty;
    }
    expect(closed, isTrue, reason: '返回键应收起竖单');
    expect(exitRequests, isEmpty, reason: '竖单打开时返回不应退出 App');
    expect(
      find.byKey(const ValueKey<String>('handle-bar')),
      findsOneWidget,
      reason: '竖单退场后把手条应回归',
    );

    // 再次打开，点遮罩空白处也应收起。
    await tester.tapAt(const Offset(62, 579));
    await pumpFramesMs(tester, 400);
    expect(find.byType(HandleMenu), findsOneWidget);
    await tester.tapAt(const Offset(400, 200));
    closed = false;
    for (var i = 0; i < 48 && !closed; i++) {
      await tester.pump(const Duration(milliseconds: 16));
      closed = find.byType(HandleMenu).evaluate().isEmpty;
    }
    expect(closed, isTrue, reason: '点遮罩应收起竖单');
  });

  testWidgets('竖单按钮触发：弹「开发中」提示并收起竖单', (tester) async {
    await tester.pumpWidget(const EchoApp());
    await tester.pump();

    await tester.tapAt(const Offset(62, 579));
    await pumpFramesMs(tester, 400);

    // 最上方按钮（刷新）圆心 ≈ (62,432)；直接点其图标保证命中。
    await tester.tap(
      find.descendant(
        of: find.byType(HandleMenu),
        matching: find.byIcon(Icons.refresh),
      ),
      warnIfMissed: true,
    );
    await tester.pump();
    expect(find.text('「刷新」功能开发中'), findsOneWidget);

    // 竖单随即反向收起，把手条回归。
    var closed = false;
    for (var i = 0; i < 48 && !closed; i++) {
      await tester.pump(const Duration(milliseconds: 16));
      closed = find.byType(HandleMenu).evaluate().isEmpty;
    }
    expect(closed, isTrue, reason: '触发操作后竖单应收起');
    expect(find.byKey(const ValueKey<String>('handle-bar')), findsOneWidget);
  });

  testWidgets('AI 条：单击/短滑动不误触；长按呼出对话框可输入，点遮罩收起', (tester) async {
    await tester.pumpWidget(const EchoApp());
    await tester.pump();

    // 单击 AI 条：预留无动作。
    await tester.tapAt(const Offset(248, 579));
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.byType(AiDialog), findsNothing);

    // 按下后上滑超过 8px：取消长按，不弹对话框。
    final slide = await tester.createGesture();
    await slide.down(const Offset(248, 579));
    await slide.moveTo(const Offset(248, 550));
    await tester.pump(const Duration(milliseconds: 500));
    await slide.up();
    expect(find.byType(AiDialog), findsNothing);

    // 长按 450ms：对话框升起，输入框自动聚焦，可直接打字。
    await tester.longPressAt(const Offset(248, 579));
    await tester.pump();
    expect(find.byType(AiDialog), findsOneWidget);
    await pumpFramesMs(tester, 340);
    final dialogField = find.descendant(
      of: find.byType(AiDialog),
      matching: find.byType(TextField),
    );
    expect(dialogField, findsOneWidget);
    await tester.enterText(dialogField, '你好');
    await tester.pump();
    expect(find.text('你好'), findsOneWidget);

    // 点遮罩空白处：失焦收键盘 + 面板退场。
    await tester.tapAt(const Offset(400, 100));
    var closed = false;
    for (var i = 0; i < 48 && !closed; i++) {
      await tester.pump(const Duration(milliseconds: 16));
      closed = find.byType(AiDialog).evaluate().isEmpty;
    }
    expect(closed, isTrue, reason: '点遮罩应收起 AI 对话框');
  });

  testWidgets('把手右拖：抽屉跟手滑出、松手吸附；返回键关闭，把手回归', (tester) async {
    await tester.pumpWidget(const EchoApp());
    await tester.pump();
    expect(find.byType(SideDrawer), findsNothing);

    // 从把手向右拖出约 220px（抽屉宽 340 → 进度 ≈ .65）。
    final g = await tester.createGesture();
    await g.down(const Offset(62, 579));
    await tester.pump();
    await g.moveTo(const Offset(90, 579));
    await g.moveTo(const Offset(160, 579));
    await g.moveTo(const Offset(282, 579));
    await tester.pump();
    expect(find.byType(SideDrawer), findsOneWidget, reason: '跟手期间抽屉应已挂载');

    // 松手 → 进度过半，吸附到全开（420ms 动画）。
    await g.up();
    for (var i = 0; i < 40; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
    expect(find.byType(SideDrawer), findsOneWidget, reason: '松手应吸附到全开');
    expect(
      find.byKey(const ValueKey<String>('handle-bar-docked')),
      findsOneWidget,
      reason: '全开后把手应停靠在抽屉右缘',
    );
    expect(find.byKey(const ValueKey<String>('handle-bar')), findsNothing);

    // 返回键关闭抽屉，把手回归常态位。
    await tester.binding.handlePopRoute();
    var closed = false;
    for (var i = 0; i < 48 && !closed; i++) {
      await tester.pump(const Duration(milliseconds: 16));
      closed = find.byType(SideDrawer).evaluate().isEmpty;
    }
    expect(closed, isTrue, reason: '返回键应关闭抽屉');
    expect(find.byKey(const ValueKey<String>('handle-bar')), findsOneWidget);
  });

  testWidgets('浮层互斥：竖单打开时在 AI 条上长按不弹对话框', (tester) async {
    await tester.pumpWidget(const EchoApp());
    await tester.pump();

    // 先开竖单。
    await tester.tapAt(const Offset(62, 579));
    await pumpFramesMs(tester, 400);
    expect(find.byType(HandleMenu), findsOneWidget);

    // 在 AI 条区域按下并停留超过长按阈值：被竖单遮罩拦截，
    // 不允许同时呼出 AI 对话框。
    final g = await tester.createGesture();
    await g.down(const Offset(248, 579));
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.byType(AiDialog), findsNothing, reason: '竖单打开时 AI 长按必须被互斥');
    await g.up();
    await tester.pump();
  });
}
