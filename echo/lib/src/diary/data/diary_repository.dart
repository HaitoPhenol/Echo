import 'package:flutter/material.dart';

import '../sy/diary_model.dart';

// ====================================================================
//  领域小类型
// ====================================================================

/// 一篇日记在状态机中的状态（flutter-tech-plan.md §6）。
///
/// M2 只有 [draft]；M5 接入 sqflite meta 后补齐 exported/archived。
/// 枚举与摘要字段先行，列表 UI 无需为状态机落地再改签名。
enum DiaryDocState {
  /// 草稿：可编辑。
  draft,

  /// 已导出：只读 + 「已归档」徽标。
  exported,

  /// 已归档：正文已清除，仅留索引。
  archived,
}

/// 日列表行所需的摘要信息（不持有正文）。
class DiaryDaySummary {
  const DiaryDaySummary({
    required this.date,
    required this.preview,
    required this.blockCount,
    required this.state,
  });

  /// 归属自然日（年月日有效，时分秒不参与语义）。
  final DateTime date;

  /// 首个非空块的单行预览（无正文为空串）。
  final String preview;

  /// 正文块数量。
  final int blockCount;

  /// 草稿/导出/归档状态。
  final DiaryDocState state;
}

// ====================================================================
//  仓储抽象（扩展缝：M5 换 sqflite + .sy 草稿文件实现）
// ====================================================================

/// 日记数据仓储。
///
/// 浏览层级与编辑器只依赖本抽象，不关心正文存内存还是文件：
/// M2 用 [InMemoryDiaryRepository]；M5 换成 sqflite `diary_meta`
/// 加应用目录下的 `.sy` 草稿文件。仓储在数据变化时 notify，
/// 列表页经 [DiaryRepositoryScope] 自动刷新。
abstract class DiaryRepository extends ChangeNotifier {
  /// 有草稿或应当可浏览的年份（升序、去重）。
  ///
  /// 即使仓为空也必须包含今天所在年份，保证「今天」始终可达。
  Future<List<int>> availableYears();

  /// 指定年份下有草稿或应当可浏览的月份（1..12，升序、去重）。
  ///
  /// 当 [year] 为当前年份时必须包含当前月份，理由同 [availableYears]。
  Future<List<int>> monthsOfYear(int year);

  /// 指定月份内**已有草稿**的日摘要（升序）；没有草稿返回空列表。
  /// 日列表页自行枚举整月日期并与本结果合并，空日显示弱化行。
  Future<List<DiaryDaySummary>> daysOfMonth(int year, int month);

  /// 取某日草稿；不存在返回 null（编辑器随后按模板新建空草稿，
  /// 首次输入时才 [upsertDraft] 落盘）。
  Future<DiaryDocument?> findDay(DateTime date);

  /// 新建或覆盖某日草稿。
  Future<void> upsertDraft(DiaryDocument document);
}

/// 向子树提供 [DiaryRepository]（与 ChatStoreScope 同范式）。
class DiaryRepositoryScope extends InheritedNotifier<DiaryRepository> {
  const DiaryRepositoryScope({
    super.key,
    required DiaryRepository repository,
    required super.child,
  }) : super(notifier: repository);

  /// 取仓储（日记子树内必定可用，缺失即装配错误）。
  static DiaryRepository of(BuildContext context) {
    final repository = maybeOf(context);
    assert(repository != null, '子树中缺少 DiaryRepositoryScope');
    return repository!;
  }

  /// 取仓储；scope 之外返回 null。
  static DiaryRepository? maybeOf(BuildContext context) =>
      context
          .dependOnInheritedWidgetOfExactType<DiaryRepositoryScope>()
          ?.notifier;
}
