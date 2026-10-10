import 'package:flutter/services.dart' show AssetBundle, rootBundle;

import '../sy/diary_model.dart';
import '../sy/sy_id.dart';
import '../sy/sy_serializer.dart';
import 'diary_template.dart';
import 'diary_template_json.dart';

/// M4 默认日模板（📈自动记录 / data 快照 / 💭今天 / 🌙睡前）。
///
/// 与 [BlankDiaryTemplate] 不同：实例化即带完整骨架，data 块使用
/// 确定性 ID、readonly、3 号底色（M1 真机验收深蓝反色），初始文本
/// 为占位文案，由 composer 拉取 provider 后替换为数据快照。
class DailyDefaultTemplate implements DiaryTemplate {
  DailyDefaultTemplate({required this.spec});

  final DiaryTemplateSpec spec;

  /// 资产路径（pubspec 已注册 `assets/diary/templates/`）。
  static const String assetPath = 'assets/diary/templates/daily-default.json';

  /// 从 rootBundle 加载；测试可注入自定义 [bundle]。
  static Future<DailyDefaultTemplate> loadAsset({AssetBundle? bundle}) async {
    final source =
        await (bundle ?? rootBundle).loadString(assetPath, cache: false);
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
            ),
          DiaryTemplateBlockType.paragraph => DiaryBlock(
              id: ids.next(),
              text: b.text,
            ),
          DiaryTemplateBlockType.data => DiaryBlock(
              id: SyIdGenerator.dataBlock(day, b.role!),
              text: b.placeholder,
              background: _dataBackground,
              readonly: true,
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

  /// data 快照块底色（tech-plan §5.1 第 2 条，M1 验收样本同值）。
  static const int _dataBackground = 3;
}
