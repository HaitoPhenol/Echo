import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:echo/src/app/echo_app.dart';
import 'package:echo/src/navigation/smart_nav_screen.dart';
import 'package:echo/src/pages/template_page.dart';

void main() {
  testWidgets('初始展示 10 个模板页，且第 1 页显示数字 1', (tester) async {
    // 构建应用
    await tester.pumpWidget(const EchoApp());
    await tester.pump();

    // 智能导航屏与 10 个空白模板页均在树上
    expect(find.byType(SmartNavScreen), findsOneWidget);
    expect(find.byType(TemplatePage), findsNWidgets(10));

    // 第 1 页（首个模板页）内的文本为 '1'
    final firstPageText = tester.widget<Text>(
      find.descendant(
        of: find.byType(TemplatePage).first,
        matching: find.byType(Text),
      ),
    );
    expect(firstPageText.data, '1');
  });

  testWidgets('搜索真实闭环：长按展开 → 输入页面名 → 点结果跳转',
      (tester) async {
    // 测试表面 800×600；胶囊隐形热区约 x:362~794, y:542~585。
    await tester.pumpWidget(const EchoApp());
    await tester.pump();
    // 第 9 个模板页的数字（排除滚筒页标同名文本）
    final page9Text = find.descendant(
      of: find.byType(TemplatePage).at(8),
      matching: find.byType(Text),
    );
    // 初始时第 9 页虽在树上但远在屏幕右侧（中心 x≈6800）
    expect(tester.getCenter(page9Text).dx, greaterThan(800));

    // 长按胶囊区域 → 展开搜索（倒计时 ticker 会持续运行，
    // 因此这里手动推进时间而不用 pumpAndSettle）
    await tester.longPressAt(const Offset(600, 560));
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.byType(TextField), findsOneWidget);
    // 无真实历史时显示空状态提示
    expect(find.text('暂无最近搜索'), findsOneWidget);

    // 点击搜索框聚焦（倒计时取消），输入「音乐」
    await tester.tapAt(const Offset(400, 560));
    await tester.pump(const Duration(milliseconds: 200));
    await tester.enterText(find.byType(TextField), '音乐');
    await tester.pump();

    // 实时出现搜索结果：「音乐」同时存在于输入框与结果标题中，
    // 故用唯一的来源标签「页面」确认结果行存在
    expect(find.text('页面'), findsOneWidget);

    // 点击结果行（点来源标签处，事件冒泡到结果行的点击区域）
    // → 跳转到对应页面（音乐是第 9 页，中心 x 应≈400）
    await tester.tap(find.text('页面'));
    // 手动推进，等待吸附物理完全落位（最长约 5 秒）
    double pageCenterX() => tester.getCenter(page9Text).dx;
    var settled = false;
    for (var i = 0; i < 300 && !settled; i++) {
      await tester.pump(const Duration(milliseconds: 16));
      settled = (pageCenterX() - 400).abs() < 0.5;
    }
    expect(pageCenterX(), closeTo(400, 0.5));
  });
}
