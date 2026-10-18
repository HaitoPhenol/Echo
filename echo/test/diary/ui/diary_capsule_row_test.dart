import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:echo/src/diary/editor/block_editor_controller.dart';
import 'package:echo/src/diary/sy/diary_model.dart';
import 'package:echo/src/diary/sy/sy_id.dart';
import 'package:echo/src/diary/ui/widgets/diary_capsule_row.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final fixedNow = DateTime(2026, 10, 10);
  late SyIdGenerator ids;
  late BlockEditorController controller;

  const tempKey = ValueKey<String>('diary-capsule-temp');
  const humidityKey = ValueKey<String>('diary-capsule-humidity');
  const weatherKey = ValueKey<String>('diary-capsule-weather');
  const scheduleKey = ValueKey<String>('diary-capsule-schedule');
  const moodKey = ValueKey<String>('diary-capsule-mood');

  setUp(() {
    ids = SyIdGenerator(random: Random(1), now: () => fixedNow);
    controller = BlockEditorController(idGenerator: ids, now: () => fixedNow);
  });

  /// 以真实 attach 挂一篇手写文档（custom 即胶囊读取的数据面）。
  void attachDoc({Map<String, String>? custom}) {
    controller.attach(
      DiaryDocument(
        id: SyIdGenerator.dayContainer(fixedNow),
        date: fixedNow,
        title: '10月10日 周六',
        custom: custom ?? {},
        blocks: [DiaryBlock(id: ids.next())],
      ),
    );
  }

  Widget host({
    VoidCallback? onRefreshData,
    VoidCallback? onPickMood,
    bool refreshing = false,
  }) {
    return MaterialApp(
      home: Scaffold(
        body: DiaryCapsuleRow(
          controller: controller,
          onRefreshData: onRefreshData,
          onPickMood: onPickMood,
          refreshing: refreshing,
        ),
      ),
    );
  }

  group('DiaryCapsuleRow 渲染', () {
    testWidgets('五槽恒显且稳定 key 就位', (tester) async {
      attachDoc();
      addTearDown(controller.dispose);
      await tester.pumpWidget(host());
      await tester.pumpAndSettle();

      for (final k in [tempKey, humidityKey, weatherKey, scheduleKey, moodKey]) {
        expect(find.byKey(k), findsOneWidget);
      }
    });

    testWidgets('有值：温度/湿度/天气/日程/心情逐槽文本正确', (tester) async {
      attachDoc(
        custom: {
          'custom-iot-temp': '21',
          'custom-iot-humidity': '45',
          'custom-weather': '多云',
          'custom-schedule-count': '3',
          'custom-mood': '🙂',
        },
      );
      addTearDown(controller.dispose);
      await tester.pumpWidget(host());
      await tester.pumpAndSettle();

      expect(find.text('21°C'), findsOneWidget);
      expect(find.text('45%'), findsOneWidget);
      expect(find.text('多云'), findsOneWidget);
      expect(find.text('3 条'), findsOneWidget);
      expect(find.text('🙂'), findsOneWidget);
      expect(find.text('—'), findsNothing);
    });

    testWidgets('custom 为空：五槽仍显，数据槽显 —、心情槽显空心图标 +「心情」', (tester) async {
      attachDoc();
      addTearDown(controller.dispose);
      await tester.pumpWidget(host());
      await tester.pumpAndSettle();

      expect(find.text('—'), findsNWidgets(4)); // 温度/湿度/天气/日程
      expect(find.byIcon(Icons.mood_outlined), findsOneWidget);
      expect(find.text('心情'), findsOneWidget);
      expect(find.text('🙂'), findsNothing);
    });
  });

  group('DiaryCapsuleRow 点按', () {
    testWidgets('注入回调：点数据胶囊触发 onRefreshData，点心情胶囊触发 onPickMood', (tester) async {
      attachDoc(custom: const {'custom-mood': '🙂'});
      addTearDown(controller.dispose);
      var refresh = 0;
      var pick = 0;
      await tester.pumpWidget(
        host(onRefreshData: () => refresh++, onPickMood: () => pick++),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(tempKey));
      await tester.tap(find.byKey(weatherKey));
      expect(refresh, 2);
      expect(pick, 0);

      await tester.tap(find.byKey(moodKey));
      expect(pick, 1);
      expect(refresh, 2);
    });

    testWidgets('onRefreshData 为 null（locked 语义）：点数据胶囊不触发任何回调', (tester) async {
      attachDoc();
      addTearDown(controller.dispose);
      final calls = <String>[];
      await tester.pumpWidget(
        host(onPickMood: () => calls.add('mood')),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(tempKey));
      await tester.tap(find.byKey(humidityKey));
      await tester.tap(find.byKey(weatherKey));
      await tester.tap(find.byKey(scheduleKey));
      expect(calls, isEmpty);
    });

    testWidgets('refreshing 为 true：数据胶囊不响应点按', (tester) async {
      attachDoc();
      addTearDown(controller.dispose);
      var refresh = 0;
      await tester.pumpWidget(
        host(onRefreshData: () => refresh++, refreshing: true),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(tempKey));
      await tester.tap(find.byKey(weatherKey));
      expect(refresh, 0);
    });
  });
}
