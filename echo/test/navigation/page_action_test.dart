import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:echo/src/navigation/page_action.dart';

/// 本页操作竖单的**按页分派**：把手条竖单显示当前所在页面的操作，
/// 各页独立。笔记页放「今日日记」+「补记」两个快捷，其余页暂时沿用
/// 占位演示项。
void main() {
  group('buildPageActions 按页分派', () {
    testWidgets('笔记页返回「今日日记」+「补记」两项，点按各自触发对应回调', (tester) async {
      var todayFired = 0;
      var backfillFired = 0;
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

      final actions = buildPageActions(
        'notes',
        onOpenTodayDiary: () => todayFired++,
        onBackfill: () => backfillFired++,
      );

      expect(actions.map((a) => a.id).toList(), ['diary-today', 'backfill']);
      expect(actions[0].label, '今日日记');
      expect(actions[1].label, '补记');

      // 点按即各自回调（不切换轨道页）。
      actions[0].onSelect(ctx);
      expect(todayFired, 1);
      expect(backfillFired, 0);

      actions[1].onSelect(ctx);
      expect(backfillFired, 1);
      expect(todayFired, 1);
    });

    testWidgets('非笔记页：沿用 3 个占位演示项（刷新/分享/置顶）', (tester) async {
      final actions = buildPageActions(
        'chat',
        onOpenTodayDiary: () {},
        onBackfill: () {},
      );

      expect(
        actions.map((a) => a.id).toList(),
        ['refresh', 'share', 'pin'],
      );
    });
  });
}
