import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:echo/src/pages/chat_page.dart';
import 'package:echo/src/theme/app_colors.dart';

/// ChatPage 会话列表骨架的组件测试。
///
/// 用 [TestFlutterView] 直接配置表面尺寸与安全区 padding，
/// 不挂载整个 EchoApp：页面骨架与导航/手势无关，隔离测更精确。
void main() {
  testWidgets('30 个会话行：头像/昵称/预览齐全，无标题栏、行高统一', (tester) async {
    // 表面高度足以容纳全部 30 行 + 底部停靠预留：30*72 + 26 = 2186。
    tester.view
      ..devicePixelRatio = 1.0
      ..physicalSize = const Size(800, 2200);
    addTearDown(tester.view.reset);

    await tester.pumpWidget(const MaterialApp(home: ChatPage()));
    await tester.pump();

    // 没有任何标题栏，整页只有一个列表
    expect(find.byType(AppBar), findsNothing);
    expect(find.byType(ListView), findsOneWidget);

    // 每行一个头像框、一条昵称、一条预览
    expect(find.byType(ChatAvatar), findsNWidgets(30));
    expect(find.text(ChatPage.placeholderNickname), findsNWidgets(30));
    expect(find.text(ChatPage.placeholderPreview), findsNWidgets(30));

    // 30 行全部构建且 key 连续
    for (var i = 0; i < ChatPage.conversationCount; i++) {
      expect(find.byKey(ValueKey<String>('chat-row-$i')), findsOneWidget);
    }

    // 无安全区时首行紧贴屏幕顶部（无标题栏占位），统一行高 72
    final firstRow = find.byKey(const ValueKey<String>('chat-row-0'));
    final firstRect = tester.getRect(firstRow);
    expect(firstRect.top, 0);
    expect(firstRect.height, ChatPage.rowHeight);

    // 首行头像：左边距 14、在分隔线之上的内容区（行高 − 1px 分隔线）
    // 内垂直居中，48 见方
    final avatarRect = tester.getRect(
      find.descendant(of: firstRow, matching: find.byType(ChatAvatar)),
    );
    expect(avatarRect.left, ChatPage.rowHorizontalPadding);
    expect(avatarRect.width, ChatPage.avatarSize);
    expect(avatarRect.height, ChatPage.avatarSize);
    expect(
      avatarRect.top,
      (ChatPage.rowHeight - 1 - ChatPage.avatarSize) / 2,
    );

    // 头像框为 tone1 圆形描边
    final avatarBox = tester.widget<Container>(
      find.descendant(of: firstRow, matching: find.byType(Container)).first,
    );
    final decoration = avatarBox.decoration! as BoxDecoration;
    expect(decoration.shape, BoxShape.circle);
    expect(decoration.border!.top.color, AppColors.tone1);

    // 昵称在头像右侧、预览为单行省略
    final name = tester.widget<Text>(
      find.descendant(
        of: firstRow,
        matching: find.text(ChatPage.placeholderNickname),
      ),
    );
    expect(name.style?.color, AppColors.textPrimary);
    expect(name.maxLines, 1);
    expect(name.overflow, TextOverflow.ellipsis);

    // 预览为次级色，同样单行省略
    final preview = tester.widget<Text>(
      find.descendant(
        of: firstRow,
        matching: find.text(ChatPage.placeholderPreview),
      ),
    );
    expect(preview.style?.color, AppColors.textMuted);
    expect(preview.maxLines, 1);
    expect(preview.overflow, TextOverflow.ellipsis);
  });

  testWidgets('列表可纵向滚动；状态栏与底部停靠条通过内边距避让', (tester) async {
    // 常规手机表面：上 30 状态栏、下 20 手势条安全区
    tester.view
      ..devicePixelRatio = 1.0
      ..physicalSize = const Size(800, 600)
      ..padding = const FakeViewPadding(top: 30, bottom: 20);
    addTearDown(tester.view.reset);

    await tester.pumpWidget(const MaterialApp(home: ChatPage()));
    await tester.pump();

    // 首行从状态栏安全区之下开始（没有额外标题栏占位）
    final firstRect = tester.getRect(
      find.byKey(const ValueKey<String>('chat-row-0')),
    );
    expect(firstRect.top, 30);

    // 视口只放得下约 7 行，末行尚未构建
    expect(find.byKey(const ValueKey<String>('chat-row-29')), findsNothing);

    // 滚到底（行程不足一屏时拖动量超出会被夹在 maxScrollExtent）
    await tester.drag(find.byType(ListView), const Offset(0, -2000));
    await tester.pumpAndSettle();

    // 末行底边距屏幕底部 = 底部安全区 20 + 停靠条预留 26
    final lastRect = tester.getRect(
      find.byKey(const ValueKey<String>('chat-row-29')),
    );
    expect(lastRect.bottom, 600 - 20 - 26);
  });
}
