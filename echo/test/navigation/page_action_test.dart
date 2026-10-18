import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:echo/src/navigation/page_action.dart';

/// 本页操作竖单的**按页分派**：把手条竖单显示当前所在页面的操作，
/// 各页独立。笔记页只放一个「今日日记」快捷，其余页暂时沿用占位演示项。
void main() {
  group('buildPageActions 按页分派', () {
    testWidgets('笔记页只返回一个「今日日记」项，点按触发注入回调', (tester) async {
      var fired = 0;
      late BuildContext ctx;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) {
              ctx = context;
              return const SizedBox.shrink();
            },
          ),
        ),
      );

      final actions = buildPageActions('notes', onOpenTodayDiary: () => fired++);

      expect(actions, hasLength(1));
      expect(actions.single.id, 'diary-today');
      expect(actions.single.label, '今日日记');

      // 点按即回调注入的「今日日记」动作（不切换轨道页）。
      actions.single.onSelect(ctx);
      expect(fired, 1);
    });

    testWidgets('非笔记页：沿用 3 个占位演示项（刷新/分享/置顶）', (tester) async {
      final actions = buildPageActions('chat', onOpenTodayDiary: () {});

      expect(
        actions.map((a) => a.id).toList(),
        ['refresh', 'share', 'pin'],
      );
    });
  });
}
