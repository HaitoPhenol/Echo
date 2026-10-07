import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:echo/src/pages/chat_page.dart';
import 'package:echo/src/services/chat_store.dart';
import 'package:echo/src/theme/app_colors.dart';

/// ChatPage 会话列表的组件测试。
///
/// 用 [TestFlutterView] 直接配置表面尺寸与安全区 padding，
/// 不挂载整个 EchoApp：页面骨架与导航/手势无关，隔离测更精确。
/// 数据经由 [ChatStoreScope] 注入 [ChatStore]。
void main() {
  /// 包一层 ChatStoreScope 的挂载台。
  Widget booth(ChatStore store) => MaterialApp(
    home: ChatStoreScope(store: store, child: const ChatPage()),
  );

  /// 静音触感方法通道（吸附/点按会触发 Haptics，测试环境无原生端）。
  void mockHaptics(WidgetTester tester) {
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('echo/haptics'),
      (call) async => null,
    );
  }

  /// 逐帧推进约 320ms：足够 180ms 吸附动画落位。
  ///
  /// 不能用 pumpAndSettle——未读绿点是无限循环呼吸动画，
  /// 存在时 settle 会永久超时。
  Future<void> pumpSnap(WidgetTester tester) async {
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
  }

  testWidgets('初始 30 个已读会话行：头像/昵称/预览齐全，无未读绿点', (tester) async {
    // 表面高度足以容纳全部 30 行 + 底部停靠预留：30*72 + 26 = 2186。
    tester.view
      ..devicePixelRatio = 1.0
      ..physicalSize = const Size(800, 2200);
    addTearDown(tester.view.reset);

    final store = ChatStore();
    await tester.pumpWidget(booth(store));
    await tester.pump();

    expect(store.conversations, hasLength(30));
    expect(store.hasUnread, isFalse);

    // 没有任何标题栏，整页只有一个列表
    expect(find.byType(AppBar), findsNothing);
    expect(find.byType(ListView), findsOneWidget);

    // 每行一个头像框、一条昵称、一条预览；没有任何未读绿点
    expect(find.byType(ChatAvatar), findsNWidgets(30));
    expect(find.text(ChatStore.placeholderNickname), findsNWidgets(30));
    expect(find.text(ChatStore.placeholderPreview), findsNWidgets(30));
    expect(find.byType(UnreadDot), findsNothing);

    // 30 行全部构建且 key 连续
    for (var i = 0; i < store.seedCount; i++) {
      expect(find.byKey(ValueKey<String>('chat-row-seed-$i')), findsOneWidget);
    }

    // 无安全区时首行紧贴屏幕顶部（无标题栏占位），统一行高 72
    final firstRow = find.byKey(const ValueKey<String>('chat-row-seed-0'));
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
    expect(avatarRect.top, (ChatPage.rowHeight - 1 - ChatPage.avatarSize) / 2);

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
        matching: find.text(ChatStore.placeholderNickname),
      ),
    );
    expect(name.style?.color, AppColors.textPrimary);
    expect(name.maxLines, 1);
    expect(name.overflow, TextOverflow.ellipsis);

    final preview = tester.widget<Text>(
      find.descendant(
        of: firstRow,
        matching: find.text(ChatStore.placeholderPreview),
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

    await tester.pumpWidget(booth(ChatStore()));
    await tester.pump();

    // 首行从状态栏安全区之下开始（没有额外标题栏占位）
    final firstRect = tester.getRect(
      find.byKey(const ValueKey<String>('chat-row-seed-0')),
    );
    expect(firstRect.top, 30);

    // 视口只放得下约 7 行，末行尚未构建
    expect(
      find.byKey(const ValueKey<String>('chat-row-seed-29')),
      findsNothing,
    );

    // 滚到底（行程不足一屏时拖动量超出会被夹在 maxScrollExtent）
    await tester.drag(find.byType(ListView), const Offset(0, -2000));
    await tester.pumpAndSettle();

    // 末行底边距屏幕底部 = 底部安全区 20 + 停靠条预留 26
    final lastRect = tester.getRect(
      find.byKey(const ValueKey<String>('chat-row-seed-29')),
    );
    expect(lastRect.bottom, 600 - 20 - 26);
  });

  testWidgets('新消息：列表最前插入未读会话并显示呼吸绿点，点行已读清除', (tester) async {
    tester.view
      ..devicePixelRatio = 1.0
      ..physicalSize = const Size(800, 1200);
    addTearDown(tester.view.reset);
    mockHaptics(tester);

    final store = ChatStore();
    await tester.pumpWidget(booth(store));
    await tester.pump();

    store.addIncoming();
    await tester.pump();

    // 31 行，新会话在最前且带未读绿点；初始 30 行仍无点
    expect(store.conversations, hasLength(31));
    expect(store.hasUnread, isTrue);
    final newRow = find.byKey(const ValueKey<String>('chat-row-incoming-1'));
    expect(newRow, findsOneWidget);
    expect(tester.getTopLeft(newRow).dy, 0);
    expect(
      find.descendant(of: newRow, matching: find.byType(UnreadDot)),
      findsOneWidget,
    );

    // 点按该行 → 标记已读：绿点消失，store 无未读
    await tester.tap(newRow);
    await tester.pump();
    expect(store.hasUnread, isFalse);
    expect(
      find.descendant(of: newRow, matching: find.byType(UnreadDot)),
      findsNothing,
    );
  });

  testWidgets('左滑：已读行露出「未读」「删除」，未读行只露出「删除」', (tester) async {
    tester.view
      ..devicePixelRatio = 1.0
      ..physicalSize = const Size(800, 1200);
    addTearDown(tester.view.reset);
    mockHaptics(tester);

    final store = ChatStore();
    await tester.pumpWidget(booth(store));
    await tester.pump();

    final row0 = find.byKey(const ValueKey<String>('chat-row-seed-0'));

    /// 行内的操作按钮文字。
    Finder rowAction(String label) =>
        find.descendant(of: row0, matching: find.text(label));

    /// 真正露出（未被前景遮挡、可点）的操作按钮。操作按钮全行都在
    /// 树中，仅靠「在树」无法区分是否露出，必须过 hitTestable。
    Finder revealed(String label) => rowAction(label).hitTestable();

    // 收起态：没有任何可点的操作按钮
    expect(revealed('删除'), findsNothing);
    expect(revealed('未读'), findsNothing);

    // 左滑超过半程并吸附：两个按钮露出
    await tester.drag(row0, const Offset(-200, 0));
    await pumpSnap(tester);
    final deleteButton = revealed('删除');
    final unreadButton = revealed('未读');
    expect(deleteButton, findsOneWidget);
    expect(unreadButton, findsOneWidget);
    // 删除按钮在最右（未读在其左侧）
    expect(
      tester.getCenter(deleteButton).dx,
      greaterThan(tester.getCenter(unreadButton).dx),
    );
    // 删除按钮为 anchorRed 实底（沿「删除」文字向上找它自己的
    // ColoredBox，不能取行内第一个——分隔线/未读按钮也有 ColoredBox）
    final deleteFill = tester.widget<ColoredBox>(
      find
          .ancestor(of: rowAction('删除'), matching: find.byType(ColoredBox))
          .first,
    );
    expect(deleteFill.color, AppColors.anchorRed);

    // 点「未读」：恢复未读态（绿点出现、操作区收回）
    await tester.tap(unreadButton);
    await pumpSnap(tester);
    expect(store.hasUnread, isTrue);
    expect(store.conversations.first.unread, isTrue);
    expect(
      find.descendant(of: row0, matching: find.byType(UnreadDot)),
      findsOneWidget,
    );
    expect(revealed('删除'), findsNothing);

    // 未读行再左滑：只有「删除」，「未读」根本不构建
    await tester.drag(row0, const Offset(-200, 0));
    await pumpSnap(tester);
    expect(revealed('删除'), findsOneWidget);
    expect(rowAction('未读'), findsNothing);

    // 点「删除」：该行从列表移除，且仍剩 29 行
    await tester.tap(revealed('删除'));
    await pumpSnap(tester);
    expect(row0, findsNothing);
    expect(store.conversations, hasLength(29));
    expect(store.hasUnread, isFalse, reason: '删掉唯一未读行后应无未读');
  });

  testWidgets('左滑展开一行后，竖向滚动列表会自动收回操作区', (tester) async {
    tester.view
      ..devicePixelRatio = 1.0
      ..physicalSize = const Size(800, 600);
    addTearDown(tester.view.reset);
    mockHaptics(tester);

    await tester.pumpWidget(booth(ChatStore()));
    await tester.pump();

    final row0 = find.byKey(const ValueKey<String>('chat-row-seed-0'));
    await tester.drag(row0, const Offset(-200, 0));
    await tester.pumpAndSettle();
    expect(
      find.descendant(of: row0, matching: find.text('删除')).hitTestable(),
      findsOneWidget,
    );

    // 从列表中部发起竖向滚动（避开操作按钮所在的右缘）
    await tester.dragFrom(const Offset(300, 400), const Offset(0, -300));
    await tester.pumpAndSettle();
    expect(
      find.descendant(of: row0, matching: find.text('删除')).hitTestable(),
      findsNothing,
    );
  });
}
