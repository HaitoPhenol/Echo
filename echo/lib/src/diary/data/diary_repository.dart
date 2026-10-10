import 'package:flutter/material.dart';

import '../sy/diary_model.dart';
import '../sy/sy_id.dart';

// ====================================================================
//  领域小类型
// ====================================================================

/// 一篇日记在状态机中的状态（flutter-tech-plan.md §6）。
///
/// M5 持久化后三态齐备：
/// `draft → exported → archived`（见 [requireStateTransition]）。
enum DiaryDocState {
  /// 草稿：正文可编辑，可被增量导出打包。
  draft,

  /// 已导出：zip 已分享出 Echo；正文保留在本机但只读。
  exported,

  /// 已归档：用户确认在思源导入后清除本机正文，仅留 meta 索引（终态）。
  archived,
}

/// 状态机守卫：只允许 draft→exported 与 exported→archived，
/// 其余迁移（含 archived 的一切出路）抛 [StateError]。
DiaryDocState requireStateTransition(
  DiaryDocState from,
  DiaryDocState to,
) {
  final allowed =
      (from == DiaryDocState.draft && to == DiaryDocState.exported) ||
          (from == DiaryDocState.exported && to == DiaryDocState.archived);
  if (!allowed) {
    throw StateError('非法日记状态迁移：$from → $to');
  }
  return to;
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

  /// 列表预览规则：用户写下的第一段非空文字（跳过 readonly data
  /// 快照与标题骨架），单行化并截 40 字；一个字没写返回空串。
  /// 内存与持久两个仓储共用，保证列表口径一致。
  static String previewOf(DiaryDocument doc) {
    final preview = doc.blocks
        .where(
            (b) => !b.readonly && b.kind == DiaryBlockKind.paragraph)
        .map((b) => b.text.replaceAll('\n', ' ').trim())
        .firstWhere((t) => t.isNotEmpty, orElse: () => '');
    return preview.length > 40 ? preview.substring(0, 40) : preview;
  }

  /// 由文档直接构造摘要（[state] 显式给——文档对象本身只有 locked）。
  factory DiaryDaySummary.fromDocument(
    DiaryDocument doc, {
    required DiaryDocState state,
  }) {
    return DiaryDaySummary(
      date: DateTime(doc.date.year, doc.date.month, doc.date.day),
      preview: previewOf(doc),
      blockCount: doc.blocks.length,
      state: state,
    );
  }
}

// ====================================================================
//  仓储抽象（M5：sqflite diary_meta + 应用目录 .sy 正文文件实现）
// ====================================================================

/// 日记数据仓储。
///
/// 浏览层级与编辑器只依赖本抽象：测试与 preview 走
/// [InMemoryDiaryRepository]，生产 M5 起走 sqflite `diary_meta`
/// 加应用目录下的 `.sy` 正文文件。仓储在数据变化时 notify，
/// 列表页经 [DiaryRepositoryScope] 自动刷新。
abstract class DiaryRepository extends ChangeNotifier {
  /// 与仓储同源的思源 ID 发生器（composer 模板成稿时注入，
  /// 保证容器/块 ID 与仓储内既有 ID 不冲突）。
  SyIdGenerator get idGenerator;

  /// 日记日时钟所认为的「今天」（04:00 日界，归一到年月日）。
  ///
  /// 全模块对「今天」的判定唯一收口点，委托 [DiaryClock]；
  /// 浏览层高亮、自动成稿、清理与补记未来禁用一律以它为准。
  DateTime today();

  /// 有日记的年份（升序、去重，含三态）。
  ///
  /// 当前年由「进模块自动成稿」（tech-plan §5.2 第 2 条）保证自然出现。
  Future<List<int>> availableYears();

  /// 指定年份下有日记的月份（1..12，升序、去重，含三态）。
  Future<List<int>> monthsOfYear(int year);

  /// 指定月份内**真实存在**的日摘要（升序，含三态；archived 行
  /// 正文已清空，preview/blockCount 为归档前快照）。
  Future<List<DiaryDaySummary>> daysOfMonth(int year, int month);

  /// 指定月份内日记总篇数（含 draft/exported/archived；
  /// 月列表行做篇数视觉层级用）。
  Future<int> draftCountOfMonth(int year, int month);

  /// 取某日可打开的文档；无 meta 或正文已清除（archived）返回 null。
  /// exported 文档返回时 `locked == true`（调用方随后走只读 UI；
  /// 新建路径走 composer.ensureDay）。
  Future<DiaryDocument?> findDay(DateTime date);

  /// meta 是否存在（含正文已删的 archived）。
  ///
  /// composer.ensureDay 据此区分「从未存在（可模板成稿）」与
  /// 「已归档（禁止复活）」。
  Future<bool> dayExists(DateTime date);

  /// 某日状态；无 meta 返回 null。
  Future<DiaryDocState?> stateOfDay(DateTime date);

  /// 新建或覆盖某日草稿。
  ///
  /// 仅允许无 meta 或 draft 态；对 exported/archived 日期写入抛
  /// [StateError]（只读 UI 不会触发，属防御性守卫）。
  Future<void> upsertDraft(DiaryDocument document);

  /// 指定年份的全部 draft 文档（日期升序），供增量导出打包。
  /// exported/archived 不重复入包。
  Future<List<DiaryDocument>> draftDocumentsOfYear(int year);

  /// 批量 draft→exported：要求每个日期当前均为 draft，否则
  /// [StateError]（整批不迁移）；落 exportedAt 并把文档置只读。
  Future<void> markExported(
    Iterable<DateTime> dates, {
    required DateTime exportedAt,
  });

  /// exported→archived：删除本机正文文件，仅保留 meta 索引（终态）。
  /// 非 exported 状态调用抛 [StateError]。
  Future<void> archiveDay(DateTime date);

  /// 删除日记日**早于** [cutoff]（按自然日比较，不含 cutoff 当天）
  /// 且 [isEmpty] 判定为「什么都没写」的 **draft** 草稿
  /// （tech-plan §5.2 第 4 条）。
  ///
  /// 判定函数由 composer 提供（忽略 readonly data 块与模板骨架预填块），
  /// 仓储只负责日期筛选与删除。exported/archived 永不参与清理。
  /// 返回删除篇数，完成后 notify 一次。
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
  static DiaryRepository? maybeOf(BuildContext context) => context
      .dependOnInheritedWidgetOfExactType<DiaryRepositoryScope>()
      ?.notifier;
}
