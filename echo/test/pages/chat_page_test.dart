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
/// 数据经由 [ChatStoreScope] 注入 [ChatStore]——store 初始为空，
/// 需要行的用例一律通过 `addIncoming()` 造数据。
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

  /// 造 [count] 条会话（addIncoming 逐条插到最前，id 为
  /// incoming-1..count，最终顺序为 incoming-count..incoming-1），
  /// 再全部标记已读，得到不带呼吸动画的纯列表（可安全 settle）。
  ChatStore seededReadStore(int count) {
    final store = ChatStore();
    for (var i = 0; i < count; i++) {
      store.addIncoming();
    }
    for (var i = 1; i <= count; i++) {
      store.markRead('incoming-$i');
    }
    return store;
  }

  testWidgets('初始为空：无列表/头像/绿点，居中显示「暂无消息」小字', (
    tester,
  ) async {
    tester.view
      ..devicePixelRatio = 1.0
      ..physicalSize = const Size(800, 1200);
    addTearDown(tester.view.reset);

    final store = ChatStore();
    await tester.pumpWidget(booth(store));
    await tester.pump();

    expect(store.conversations, isEmpty);
    expect(store.hasUnread, isFalse);

    // 空态不挂标题栏也不挂列表
    expect(find.byType(AppBar), findsNothing);
    expect(find.byType(ListView), findsNothing);
    expect(find.byType(ChatAvatar), findsNothing);
    expect(find.byType(UnreadDot), findsNothing);

    // 唯一一条空态提示：tone2 13px 小字，位于屏幕正中
    final hint = find.text(ChatPage.emptyHint);
    expect(hint, findsOneWidget);
    final hintText = tester.widget<Text>(hint);
    expect(hintText.style?.fontSize, 13);
    expect(hintText.style?.color, AppColors.textMuted);
    expect(
      find.ancestor(of: hint, matching: find.byType(Center)),
      findsOneWidget,
    );
    final hintCenter = tester.getCenter(hint);
    expect(hintCenter, const Offset(400, 600));
  });

  testWidgets('列表可纵向滚动；状态栏与底部停靠条通过内边距避让', (
    tester,
  ) async {
    // 常规手机表面：上 30 状态栏、下 20 手势条安全区
    tester.view
      ..devicePixelRatio = 1.0
      ..physicalSize = const Size(800, 600)
      ..padding = const FakeViewPadding(top: 30, bottom: 20);
    addTearDown(tester.view.reset);

    final store = seededReadStore(30);
    await tester.pumpWidget(booth(store));
    await tester.pump();

    // 首行（最后插入的 incoming-30）从状态栏安全区之下开始
    final firstRect = tester.getRect(
      find.byKey(const ValueKey<String>('chat-row-incoming-30')),
    );
    expect(firstRect.top, 30);

    // 视口只放得下约 7 行，末行尚未构建
    expect(
      find.byKey(const ValueKey<String>('chat-row-incoming-1')),
      findsNothing,
    );

    // 滚到底（行程不足一屏时拖动量超出会被夹在 maxScrollExtent）
    await tester.drag(find.byType(ListView), const Offset(0, -2000));
    await tester.pumpAndSettle();

    // 末行底边距屏幕底部 = 底部安全区 20 + 停靠条预留 26
    final lastRect = tester.getRect(
      find.byKey(const ValueKey<String>('chat-row-incoming-1')),
    );
    expect(lastRect.bottom, 600 - 20 - 26);
  });

  testWidgets('新消息：空态切为列表，最前插入未读行（绿点+80%居中分隔线），点行已读', (
    tester,
  ) async {
    tester.view
      ..devicePixelRatio = 1.0
      ..physicalSize = const Size(800, 1200);
    addTearDown(tester.view.reset);
    mockHaptics(tester);

    final store = ChatStore();
    await tester.pumpWidget(booth(store));
    await tester.pump();
    expect(find.text(ChatPage.emptyHint), findsOneWidget);

    store.addIncoming();
    await tester.pump();

    // 空态消失，出现 1 行，新会话在最前且带未读绿点
    expect(store.conversations, hasLength(1));
    expect(store.hasUnread, isTrue);
    expect(find.text(ChatPage.emptyHint), findsNothing);
    expect(find.byType(ListView), findsOneWidget);
    final newRow = find.byKey(const ValueKey<String>('chat-row-incoming-1'));
    expect(newRow, findsOneWidget);
    expect(tester.getTopLeft(newRow).dy, 0);
    expect(
      find.descendant(of: newRow, matching: find.byType(UnreadDot)),
      findsOneWidget,
    );

    // 行几何回归：统一行高 72；头像左边距 14、在内容区（行高 − 1px
    // 分隔线）内垂直居中，48 见方、tone1 圆形描边
    expect(tester.getSize(newRow).height, ChatPage.rowHeight);
    final avatarRect = tester.getRect(
      find.descendant(of: newRow, matching: find.byType(ChatAvatar)),
    );
    expect(avatarRect.left, ChatPage.rowHorizontalPadding);
    expect(avatarRect.width, ChatPage.avatarSize);
    expect(avatarRect.height, ChatPage.avatarSize);
    expect(avatarRect.top, (ChatPage.rowHeight - 1 - ChatPage.avatarSize) / 2);
    final avatarBox = tester.widget<Container>(
      find.descendant(of: newRow, matching: find.byType(Container)).first,
    );
    final decoration = avatarBox.decoration! as BoxDecoration;
    expect(decoration.shape, BoxShape.circle);
    expect(decoration.border!.top.color, AppColors.tone1);

    // 昵称 / 预览样式
    final name = tester.widget<Text>(find.text('新消息 1'));
    expect(name.style?.color, AppColors.textPrimary);
    expect(name.maxLines, 1);
    expect(name.overflow, TextOverflow.ellipsis);
    final preview = tester.widget<Text>(find.text('你有一条新消息'));
    expect(preview.style?.color, AppColors.textMuted);
    expect(preview.maxLines, 1);
    expect(preview.overflow, TextOverflow.ellipsis);

    // 分隔线：屏宽 80%（800 表面 → 640 宽、左右各留 80）、1px、
    // tone1，贴在行底（行顶 0 → 底边 72）
    final divider = find.descendant(
      of: newRow,
      matching: find.byWidgetPredicate(
        (w) => w is ColoredBox && w.color == AppColors.tone1,
      ),
    );
    expect(divider, findsOneWidget);
    final dividerRect = tester.getRect(divider);
    expect(
      dividerRect.left,
      closeTo(800 * (1 - ChatPage.dividerWidthRatio) / 2, 1e-9),
    );
    expect(dividerRect.width, closeTo(800 * ChatPage.dividerWidthRatio, 1e-9));
    expect(dividerRect.height, 1);
    expect(dividerRect.bottom, ChatPage.rowHeight);

    // 点按该行 → 标记已读：绿点消失，store 无未读；行保留、不回空态
    await tester.tap(newRow);
    await tester.pump();
    expect(store.hasUnread, isFalse);
    expect(
      find.descendant(of: newRow, matching: find.byType(UnreadDot)),
      findsNothing,
    );
    expect(newRow, findsOneWidget);
    expect(find.text(ChatPage.emptyHint), findsNothing);
  });

  testWidgets('左滑：操作区恒为「读状态切换 + 删除」两按钮，切换/删除行为正确且删光回空态', (
    tester,
  ) async {
    tester.view
      ..devicePixelRatio = 1.0
      ..physicalSize = const Size(800, 1200);
    addTearDown(tester.view.reset);
    mockHaptics(tester);

    // 从已读行起步：读状态按钮标签为「未读」
    final store = ChatStore()
      ..addIncoming()
      ..markRead('incoming-1');
    await tester.pumpWidget(booth(store));
    await tester.pump();

    final row0 = find.byKey(const ValueKey<String>('chat-row-incoming-1'));

    /// 行内的操作按钮文字。
    Finder rowAction(String label) =>
        find.descendant(of: row0, matching: find.text(label));

    /// 真正露出（未被前景遮挡、可点）的操作按钮。操作按钮全行都在
    /// 树中，仅靠「在树」无法区分是否露出，必须过 hitTestable。
    Finder revealed(String label) => rowAction(label).hitTestable();

    // 收起态：没有任何可点的操作按钮
    expect(revealed('删除'), findsNothing);
    expect(revealed('未读'), findsNothing);
    expect(revealed('已读'), findsNothing);

    // 左滑超过半程并吸附：两个按钮露出
    await tester.drag(row0, const Offset(-200, 0));
    await pumpSnap(tester);
    final deleteButton = revealed('删除');
    final unreadButton = revealed('未读');
    expect(deleteButton, findsOneWidget);
    expect(unreadButton, findsOneWidget);
    // 删除按钮在最右（读状态按钮在其左侧）
    expect(
      tester.getCenter(deleteButton).dx,
      greaterThan(tester.getCenter(unreadButton).dx),
    );
    // 删除按钮为 anchorRed 实底（沿「删除」文字向上找它自己的
    // ColoredBox，不能取行内第一个——分隔线/读状态按钮也有 ColoredBox）
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
    expect(store.conversations.single.unread, isTrue);
    expect(
      find.descendant(of: row0, matching: find.byType(UnreadDot)),
      findsOneWidget,
    );
    expect(revealed('删除'), findsNothing);

    // 未读行再左滑：仍是两个按钮，读状态按钮改标为「已读」
    await tester.drag(row0, const Offset(-200, 0));
    await pumpSnap(tester);
    expect(revealed('删除'), findsOneWidget);
    expect(rowAction('未读'), findsNothing);
    final readButton = revealed('已读');
    expect(readButton, findsOneWidget);

    // 点「已读」：标记已读（绿点消失、操作区收回）
    await tester.tap(readButton);
    await pumpSnap(tester);
    expect(store.hasUnread, isFalse);
    expect(
      find.descendant(of: row0, matching: find.byType(UnreadDot)),
      findsNothing,
    );
    expect(revealed('删除'), findsNothing);

    // 再左滑：读状态按钮标签切回「未读」——操作区宽度全程恒定
    await tester.drag(row0, const Offset(-200, 0));
    await pumpSnap(tester);
    expect(revealed('未读'), findsOneWidget);
    expect(revealed('已读'), findsNothing);

    // 点「删除」：唯一一行被移除 → 列表消失、空态复现
    await tester.tap(revealed('删除'));
    await pumpSnap(tester);
    expect(store.conversations, isEmpty);
    expect(store.hasUnread, isFalse);
    expect(row0, findsNothing);
    expect(find.byType(ListView), findsNothing);
    expect(find.text(ChatPage.emptyHint), findsOneWidget);
  });

  testWidgets('松手吸附从手指离开位置起播，不弹回旧状态重播（开/合两方向）', (
    tester,
  ) async {
    tester.view
      ..devicePixelRatio = 1.0
      ..physicalSize = const Size(800, 1200);
    addTearDown(tester.view.reset);
    mockHaptics(tester);

    // 操作区恒为两个按钮、宽 152：半程 = -76、全开 = -152。
    final store = ChatStore()..addIncoming();
    await tester.pumpWidget(booth(store));
    await tester.pump();

    final row = find.byKey(const ValueKey<String>('chat-row-incoming-1'));
    Finder avatar() => find.descendant(
      of: row,
      matching: find.byType(ChatAvatar),
    );

    // 起播首帧前景位置（头像左边距 14 + 前景偏移）。
    double avatarLeft() => tester.getRect(avatar()).left;

    /// 逐段小步拖动（每段都 pump），直到前景偏移进入 [target] 区间。
    /// 首段过 slop 的位移量被识别器折算、不可精确预测，故只按
    /// 实际渲染位置逼近，不预设步数。
    Future<TestGesture> dragUntil(
      double step,
      bool Function(double offset) reached,
    ) async {
      final gesture = await tester.startGesture(const Offset(400, 36));
      await tester.pump();
      for (var i = 0; i < 20; i++) {
        await gesture.moveBy(Offset(step, 0));
        await tester.pump();
        if (reached(avatarLeft() - 14)) break;
      }
      return gesture;
    }

    // ---- 关闭态左拖到半程与全开位之间（-120 附近）后松手 ----
    var gesture = await dragUntil(
      -10,
      (offset) => offset <= -110 && offset > -152,
    );
    final beforeOpen = avatarLeft();
    expect(beforeOpen, lessThan(14 - 76), reason: '测试前置：已过半程');
    await gesture.up();
    // 吸附动画第 0 帧：必须停在手指离开位置，不能弹回 0 再打开
    await tester.pump(Duration.zero);
    expect(
      avatarLeft(),
      closeTo(beforeOpen, 0.5),
      reason: '松手后首帧不应弹回关闭态',
    );
    await pumpSnap(tester);
    // 落位到全开 -152
    expect(avatarLeft(), closeTo(14 - 152, 0.5));
    expect(
      find.descendant(of: row, matching: find.text('删除')).hitTestable(),
      findsOneWidget,
    );

    // ---- 打开态向右拖回半程与全关位之间（-40 附近）后松手 ----
    gesture = await dragUntil(10, (offset) => offset >= -55 && offset < 0);
    final beforeClose = avatarLeft();
    expect(beforeClose, greaterThan(14 - 76), reason: '测试前置：已过半程');
    await gesture.up();
    // 首帧必须停在手指离开位置，不能弹回全开位 -152 再播关闭
    await tester.pump(Duration.zero);
    expect(
      avatarLeft(),
      closeTo(beforeClose, 0.5),
      reason: '松手后首帧不应弹回打开态',
    );
    await pumpSnap(tester);
    expect(avatarLeft(), closeTo(14, 0.5));
    expect(
      find.descendant(of: row, matching: find.text('删除')).hitTestable(),
      findsNothing,
    );
  });

  testWidgets('吸附落位后再次拖动：从当前呈现位连续跟手，不跳回上一次松手位置', (
    tester,
  ) async {
    tester.view
      ..devicePixelRatio = 1.0
      ..physicalSize = const Size(800, 1200);
    addTearDown(tester.view.reset);
    mockHaptics(tester);

    final store = ChatStore()..addIncoming();
    await tester.pumpWidget(booth(store));
    await tester.pump();

    final row = find.byKey(const ValueKey<String>('chat-row-incoming-1'));
    double avatarLeft() =>
        tester
            .getRect(
              find.descendant(of: row, matching: find.byType(ChatAvatar)),
            )
            .left;

    // 左拖到半程与全开之间（约 -120）松手，吸附落位到全开 -152。
    // 注意：此时内部记录的上次松手位置仍在 -120 一带，与呈现位不同。
    final first = await tester.startGesture(const Offset(400, 36));
    await tester.pump();
    for (var i = 0; i < 20; i++) {
      await first.moveBy(const Offset(-10, 0));
      await tester.pump();
      final offset = avatarLeft() - 14;
      if (offset <= -110 && offset > -152) break;
    }
    await first.up();
    await pumpSnap(tester);
    expect(avatarLeft(), closeTo(14 - 152, 0.5));

    // 落位后立刻发起第二次拖动。错误实现会在拖动起点把位置重置为
    // 上一次松手位置（约 -120，向右跳 30+px）；正确实现应从
    // 当前呈现位 -152 连续起步（首段过 slop 后只可能继续向左）。
    final second = await tester.startGesture(const Offset(400, 36));
    await tester.pump();
    await second.moveBy(const Offset(-30, 0));
    await tester.pump();
    expect(
      avatarLeft(),
      closeTo(14 - 152, 0.6),
      reason: '再次拖动不应跳回上一次松手位置',
    );
    await second.up();
  });

  testWidgets('左滑展开一行后，竖向滚动列表会自动收回操作区', (
    tester,
  ) async {
    tester.view
      ..devicePixelRatio = 1.0
      ..physicalSize = const Size(800, 600);
    addTearDown(tester.view.reset);
    mockHaptics(tester);

    // 视口放得下约 7 行，造 12 条已读行让列表真正可竖向滚动
    final store = seededReadStore(12);
    await tester.pumpWidget(booth(store));
    await tester.pump();

    final row0 = find.byKey(const ValueKey<String>('chat-row-incoming-12'));
    await tester.drag(row0, const Offset(-200, 0));
    await pumpSnap(tester);
    expect(
      find.descendant(of: row0, matching: find.text('删除')).hitTestable(),
      findsOneWidget,
    );

    // 从列表中部发起竖向滚动（避开操作按钮所在的右缘）
    await tester.dragFrom(const Offset(300, 400), const Offset(0, -300));
    await pumpSnap(tester);
    expect(
      find.descendant(of: row0, matching: find.text('删除')).hitTestable(),
      findsNothing,
    );
  });
}
