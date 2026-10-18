import 'package:flutter/services.dart' show AssetBundle, rootBundle;

import '../sy/diary_model.dart';
import '../sy/sy_id.dart';
import '../sy/sy_serializer.dart';
import 'diary_template.dart';
import 'diary_template_json.dart';

/// 默认日模板（2026-10-18 重设）：首块「一句话概述今日」段（12 号底色）
/// + 一个空正文段。
///
/// 自动数据（温度/湿度/天气/日程条数）与心情**不再是块**：它们写进文档根
/// `custom-*` 属性，由编辑页的胶囊行 UI 呈现并随正文滚动。
///
/// 与 [BlankDiaryTemplate] 的区别仅是「声明式资产驱动」——实例化同样只
/// 产生可写段落，没有任何只读块。
class DailyDefaultTemplate implements DiaryTemplate {
  DailyDefaultTemplate({required this.spec});

  final DiaryTemplateSpec spec;

  /// 资产路径（pubspec 已注册 `assets/diary/templates/`）。
  static const String assetPath = 'assets/diary/templates/daily-default.json';

  /// 从 rootBundle 加载；测试可注入自定义 [bundle]。
  static Future<DailyDefaultTemplate> loadAsset({AssetBundle? bundle}) async {
    final source = await (bundle ?? rootBundle).loadString(
      assetPath,
      cache: false,
    );
    return DailyDefaultTemplate(spec: DiaryTemplateSpec.fromJson(source));
  }

  @override
  String get id => spec.id;

  @override
  DiaryDocument instantiate(DateTime date, SyIdGenerator ids) {
    final day = DateTime(date.year, date.month, date.day);
    final blocks = <DiaryBlock>[
      for (final b in spec.blocks)
        switch (b.type) {
          DiaryTemplateBlockType.heading => DiaryBlock(
            id: ids.next(),
            kind: DiaryBlockKind.heading,
            level: b.level,
            text: b.text,
            background: b.background,
          ),
          DiaryTemplateBlockType.paragraph => DiaryBlock(
            id: ids.next(),
            text: b.text,
            background: b.background,
          ),
        },
    ];
    return DiaryDocument(
      id: SyIdGenerator.dayContainer(day),
      date: day,
      title: SySerializer.dayTitle(day),
      blocks: blocks,
    );
  }
}
