import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:echo/src/app/echo_app.dart';
import 'package:echo/src/navigation/smart_nav_screen.dart';
import 'package:echo/src/navigation/widgets/nav_roller.dart';
import 'package:echo/src/navigation/widgets/quick_action_arc.dart';
import 'package:echo/src/pages/template_page.dart';

void main() {
  testWidgets('初始展示 4 个占位页，且首页标题为「控制台」', (tester) async {
    // 构建应用
    await tester.pumpWidget(const EchoApp());
    await tester.pump();

    // 智能导航屏与 4 个占位页均在树上
    expect(find.byType(SmartNavScreen), findsOneWidget);
    expect(find.byType(TemplatePage), findsNWidgets(4));

    // 首个占位页内的标题文本为「控制台」
    final firstPageText = tester.widget<Text>(
      find.descendant(
        of: find.byType(TemplatePage).first,
        matching: find.byType(Text),
      ),
    );
    expect(firstPageText.data, '控制台');
  });

  testWidgets('搜索真实闭环：长按展开 → 输入页面名 → 点结果跳转',
      (tester) async {
    // 测试表面 800×600；胶囊隐形热区约 x:362~794, y:542~585。
    await tester.pumpWidget(const EchoApp());
    await tester.pump();

    // 第 2 个占位页（聊天）的标题
    final chatPageText = find.descendant(
      of: find.byType(TemplatePage).at(1),
      matching: find.byType(Text),
    );
    // 初始时聊天页虽在树上但在屏幕右侧（中心 x≈1200）
    expect(tester.getCenter(chatPageText).dx, greaterThan(800));

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
    double pageCenterX() => tester.getCenter(chatPageText).dx;
    var settled = false;
    for (var i = 0; i < 300 && !settled; i++) {
      await tester.pump(const Duration(milliseconds: 16));
      settled = (pageCenterX() - 400).abs() < 0.5;
    }
    expect(pageCenterX(), closeTo(400, 0.5));
  });

  testWidgets('横滑松手后立即上甩：滚筒先关闭，快捷弧不叠加',
      (tester) async {
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

    final chatPageText = find.descendant(
      of: find.byType(TemplatePage).at(1),
      matching: find.byType(Text),
    );
    expect(tester.getCenter(chatPageText).dx, greaterThan(800));

    // 右圆点中心≈(781, 579)，热区 20 宽；点其热区（按下即触发）
    await tester.tapAt(const Offset(781, 560));

    // 等待吸附落位
    double pageCenterX() => tester.getCenter(chatPageText).dx;
    var settled = false;
    for (var i = 0; i < 300 && !settled; i++) {
      await tester.pump(const Duration(milliseconds: 16));
      settled = (pageCenterX() - 400).abs() < 0.5;
    }
    expect(pageCenterX(), closeTo(400, 0.5));
  });
}
