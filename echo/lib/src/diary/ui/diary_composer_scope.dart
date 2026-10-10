import 'package:flutter/widgets.dart';

import '../data/diary_clock.dart';
import '../data/diary_data_provider.dart';
import '../template/diary_composer.dart';

/// 全模块唯一的「日记日时钟 + 数据提供方 + composer」装配点。
///
/// 由 [DiaryPage] 建一次随页面常驻；年/月/日各级与编辑器页从此读取，
/// 禁止子树内自行 `DateTime.now()` 判定今天。
class DiaryComposerScope extends InheritedWidget {
  const DiaryComposerScope({
    super.key,
    required this.clock,
    required this.dataProvider,
    required this.composer,
    required super.child,
  });

  /// 04:00 日界时钟（标题、容器 ID、补记上限、清理判定同源收口）。
  final DiaryClock clock;

  /// 室温/日程/天气数据源（M4 为 FakeDiaryDataProvider）。
  final DiaryDataProvider dataProvider;

  /// 成稿/刷新/空稿判定编排器。
  final DiaryComposer composer;

  /// 取装配（日记子树内必定可用，缺失即装配错误）。
  static DiaryComposerScope of(BuildContext context) {
    final scope =
        context.dependOnInheritedWidgetOfExactType<DiaryComposerScope>();
    assert(scope != null, '子树中缺少 DiaryComposerScope');
    return scope!;
  }

  @override
  bool updateShouldNotify(DiaryComposerScope oldWidget) =>
      !identical(clock, oldWidget.clock) ||
      !identical(dataProvider, oldWidget.dataProvider) ||
      !identical(composer, oldWidget.composer);
}
