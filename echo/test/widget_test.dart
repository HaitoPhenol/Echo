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
}
