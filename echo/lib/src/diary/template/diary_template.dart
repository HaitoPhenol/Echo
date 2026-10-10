import '../sy/diary_model.dart';
import '../sy/sy_id.dart';
import '../sy/sy_serializer.dart';

/// 日记模板（M4 扩展缝）。
///
/// M2 只有 [BlankDiaryTemplate]（单个空段落）；M4 增加从
/// `assets/diary/templates/daily-default.json` 实例化的声明式模板
/// （📈自动记录 / data 块 / 💭今天 / 🌙睡前）与 Provider 数据注入。
/// 编辑器只依赖本接口，模板来源变化不影响编辑器。
abstract interface class DiaryTemplate {
  /// 模板稳定标识（写入文档 custom 或 M5 meta，便于追溯成稿来源）。
  String get id;

  /// 为指定自然日实例化一篇新文档（尚未落盘，首次输入才保存）。
  DiaryDocument instantiate(DateTime date, SyIdGenerator ids);
}

/// 空白模板：一个空段落，标题取金标准日标题（「10月10日 周六」）。
class BlankDiaryTemplate implements DiaryTemplate {
  const BlankDiaryTemplate();

  @override
  String get id => 'blank-v1';

  @override
  DiaryDocument instantiate(DateTime date, SyIdGenerator ids) {
    return DiaryDocument(
      // 日文档用确定性容器 ID：同一自然日永远对应同一路径，
      // 保证增量导出幂等（flutter-tech-plan.md §3.2）。
      id: SyIdGenerator.dayContainer(date),
      date: DateTime(date.year, date.month, date.day),
      title: SySerializer.dayTitle(date),
      blocks: [DiaryBlock(id: ids.next())],
    );
  }
}
