import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:echo/src/navigation/background_scroll_motion.dart';

void main() {
  group('BackgroundScrollMotion', () {
    test('累加滚动增量：内容上移则背景上移', () {
      final motion = BackgroundScrollMotion();
      motion.applyScrollDelta(20);
      expect(motion.offsetY, -20);
      motion.applyScrollDelta(-5);
      expect(motion.offsetY, -15);
    });

    test('倍率可配置（视差减速）', () {
      final motion = BackgroundScrollMotion(factor: 0.5);
      motion.applyScrollDelta(20);
      expect(motion.offsetY, -10);
    });

    test('零增量不通知；reset 归零并通知一次', () {
      final motion = BackgroundScrollMotion();
      var notified = 0;
      motion.addListener(() => notified++);
      motion.applyScrollDelta(0);
      expect(notified, 0);
      motion.applyScrollDelta(10);
      expect(notified, 1);
      motion.reset();
      expect(motion.offsetY, 0);
      expect(notified, 2);
    });
  });

  testWidgets('竖向列表滚动会转发增量', (tester) async {
    final motion = BackgroundScrollMotion();
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: BackgroundScrollListener(
          motion: motion,
          child: ListView.builder(
            itemCount: 100,
            itemExtent: 50,
            itemBuilder: (context, index) => Text('row $index'),
          ),
        ),
      ),
    );

    await tester.drag(find.byType(ListView), const Offset(0, -120));
    await tester.pumpAndSettle();
    expect(motion.offsetY, lessThan(0));
  });

  testWidgets('横向滚动不影响背景纵向位移', (tester) async {
    final motion = BackgroundScrollMotion();
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: BackgroundScrollListener(
          motion: motion,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            itemCount: 100,
            itemExtent: 50,
            itemBuilder: (context, index) => Text('col $index'),
          ),
        ),
      ),
    );

    await tester.drag(find.byType(ListView), const Offset(-120, 0));
    await tester.pumpAndSettle();
    expect(motion.offsetY, 0);
  });
}
