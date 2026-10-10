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
/// M2-M4 用 [InMemoryDiaryRepository]；M5 换成 sqflite `diary_meta`
/// 加应用目录下的 `.sy` 草稿文件。仓储在数据变化时 notify，
/// 列表页经 [DiaryRepositoryScope] 自动刷新。
abstract class DiaryRepository extends ChangeNotifier {
  /// 日记日时钟所认为的「今天」（04:00 日界，归一到年月日）。
  ///
  /// 全模块对「今天」的判定唯一收口点，委托 [DiaryClock]；
  /// 浏览层高亮、自动成稿、清理与补记未来禁用一律以它为准。
  DateTime today();

  /// 有草稿的年份（升序、去重）。
  ///
  /// M4 起不再保证包含当前年份——当前年由「进模块自动成稿」
  /// （tech-plan §5.2 第 2 条）保证自然出现。
  Future<List<int>> availableYears();

  /// 指定年份下有草稿的月份（1..12，升序、去重）。
  ///
  /// M4 起不再保证包含当前月份，理由同 [availableYears]。
  Future<List<int>> monthsOfYear(int year);

  /// 指定月份内**已有草稿**的日摘要（升序）；没有草稿返回空列表。
  ///
  /// M4 起日列表只展示这里返回的真实日记，不再逐日枚举空日。
  Future<List<DiaryDaySummary>> daysOfMonth(int year, int month);

  /// 指定月份内草稿篇数（月列表行做篇数视觉层级用）。
  Future<int> draftCountOfMonth(int year, int month);

  /// 取某日草稿；不存在返回 null（调用方随后走 composer.ensureDay
  /// 模板成稿；M2 空白模板路径已在 M4 移除）。
  Future<DiaryDocument?> findDay(DateTime date);

  /// 新建或覆盖某日草稿。
  Future<void> upsertDraft(DiaryDocument document);

  /// 删除日记日**早于** [cutoff]（按自然日比较，不含 cutoff 当天）
  /// 且 [isEmpty] 判定为「什么都没写」的草稿（tech-plan §5.2 第 4 条）。
  ///
  /// 判定函数由 composer 提供（忽略 readonly data 块与模板骨架预填块），
  /// 仓储只负责日期筛选与删除。返回删除篇数，完成后 notify 一次。
  /// M4 内存实现下仅进程内生效；M5 持久化后自动获得跨进程语义。
  Future<int> pruneEmptyBefore(
    DateTime cutoff,
    bool Function(DiaryDocument document) isEmpty,
  );
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
