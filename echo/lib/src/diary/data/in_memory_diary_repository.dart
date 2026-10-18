import 'dart:math';

import 'package:flutter/foundation.dart';

import '../sy/diary_model.dart';
import '../sy/sy_id.dart';
import 'diary_clock.dart';
import 'diary_repository.dart';
import 'diary_seed_data.dart';

/// 内存版 [DiaryRepository]（测试 / preview 专用）。
///
/// 进程内 Map 存储，重启清空；生产 M5 起走 sqflite + `.sy` 文件，
/// 浏览页与编辑器代码只依赖抽象。状态机行为与持久版严格一致：
/// draft→exported→archived，非法迁移抛 [StateError]。
///
/// 「今天」一律取自注入的 [DiaryClock]（04:00 日界）。
class InMemoryDiaryRepository extends DiaryRepository {
  InMemoryDiaryRepository({
    SyIdGenerator? idGenerator,
    DiaryClock? clock,
    bool? seedDebugData,
  }) : _ids = idGenerator ?? SyIdGenerator(random: Random(0xE0C0)),
       _clock = clock ?? DiaryClock() {
    // 默认 debug 构建装种子、release 空仓；测试显式传 false 关闭。
    if (seedDebugData ?? kDebugMode) {
      for (final doc in DiarySeedData.build(
        idGenerator: _ids,
        today: _clock.today(),
      )) {
        _entries[_keyOf(doc.date)] = _Entry.fromDraft(doc);
      }
    }
  }

  final SyIdGenerator _ids;
  final DiaryClock _clock;

  /// 模板成稿共用同一 ID 发生器（与仓储内容器/种子 ID 同源）。
  @override
  SyIdGenerator get idGenerator => _ids;

  /// key = yyyymmdd（仅日记日）。
  final Map<int, _Entry> _entries = {};

  @override
  DateTime today() => _clock.today();

  static int _keyOf(DateTime date) =>
      date.year * 10000 + date.month * 100 + date.day;

  static DateTime _dayOnly(DateTime date) =>
      DateTime(date.year, date.month, date.day);

  @override
  Future<List<int>> availableYears() async {
    final years = _entries.values.map((e) => e.date.year).toSet();
    return years.toList()..sort();
  }

  @override
  Future<List<int>> monthsOfYear(int year) async {
    final months = _entries.values
        .where((e) => e.date.year == year)
        .map((e) => e.date.month)
        .toSet();
    return months.toList()..sort();
  }

  @override
  Future<List<DiaryDaySummary>> daysOfMonth(int year, int month) async {
    final list =
        _entries.values
            .where((e) => e.date.year == year && e.date.month == month)
            .toList()
          ..sort((a, b) => a.date.compareTo(b.date));
    return list.map(_summaryOf).toList();
  }

  @override
  Future<int> draftCountOfMonth(int year, int month) async => _entries.values
      .where((e) => e.date.year == year && e.date.month == month)
      .length;

  @override
  Future<bool> isMonthFullyExported(int year, int month) async {
    final inMonth = _entries.values
        .where((e) => e.date.year == year && e.date.month == month)
        .toList();
    // 无记录不算「已导出」；有任何 draft 即未（全部）导出。
    return inMonth.isNotEmpty &&
        inMonth.every((e) => e.state != DiaryDocState.draft);
  }

  @override
  Future<DiaryDocument?> findDay(DateTime date) async {
    final entry = _entries[_keyOf(date)];
    final doc = entry?.doc;
    // exported 强制只读；不反向重置——测试可直接构造 locked 草稿。
    if (doc != null && entry!.state == DiaryDocState.exported) {
      doc.locked = true;
    }
    return doc;
  }

  @override
  Future<bool> dayExists(DateTime date) async =>
      _entries.containsKey(_keyOf(date));

  @override
  Future<DiaryDocState?> stateOfDay(DateTime date) async =>
      _entries[_keyOf(date)]?.state;

  @override
  Future<void> upsertDraft(DiaryDocument document) async {
    final key = _keyOf(document.date);
    final existing = _entries[key];
    if (existing != null && existing.state != DiaryDocState.draft) {
      throw StateError(
        '${existing.state} 态日记不可覆盖：'
        '${document.date.year}-${document.date.month}-${document.date.day}',
      );
    }
    if (existing != null) {
      existing.doc = document; // 保持 draft 身份与创建时间信息
    } else {
      _entries[key] = _Entry.fromDraft(document);
    }
    notifyListeners();
  }

  @override
  Future<List<DiaryDocument>> draftDocumentsOfYear(int year) async {
    final list =
        _entries.values
            .where((e) => e.state == DiaryDocState.draft && e.date.year == year)
            .map((e) => e.doc!)
            .toList()
          ..sort((a, b) => a.date.compareTo(b.date));
    return list;
  }

  @override
  Future<List<DiaryDocument>> draftDocumentsOfMonth(int year, int month) async {
    final list =
        _entries.values
            .where(
              (e) =>
                  e.state == DiaryDocState.draft &&
                  e.date.year == year &&
                  e.date.month == month,
            )
            .map((e) => e.doc!)
            .toList()
          ..sort((a, b) => a.date.compareTo(b.date));
    return list;
  }

  @override
  Future<DateTime?> oldestDraftBefore(DateTime cutoff) async {
    final cutoffDay = _dayOnly(cutoff);
    final candidates =
        _entries.values
            .where(
              (e) =>
                  e.state == DiaryDocState.draft && e.date.isBefore(cutoffDay),
            )
            .toList()
          ..sort((a, b) => a.date.compareTo(b.date));
    return candidates.isEmpty ? null : _dayOnly(candidates.first.date);
  }

  @override
  Future<void> markExported(
    Iterable<DateTime> dates, {
    required DateTime exportedAt,
  }) async {
    final entries = dates.map((d) => _entries[_keyOf(d)]).toList();
    for (var i = 0; i < entries.length; i++) {
      if (entries[i] == null) {
        throw StateError('导出目标不存在：第 ${i + 1} 篇');
      }
      requireStateTransition(entries[i]!.state, DiaryDocState.exported);
    }
    for (final entry in entries) {
      entry!
        ..state = DiaryDocState.exported
        ..exportedAt = exportedAt
        ..doc!.locked = true
        ..captureSummary();
    }
    notifyListeners();
  }

  @override
  Future<void> archiveDay(DateTime date) async {
    final entry = _entries[_keyOf(date)];
    if (entry == null) throw StateError('归档目标不存在：$date');
    requireStateTransition(entry.state, DiaryDocState.archived);
    entry
      ..state = DiaryDocState.archived
      ..doc = null; // 正文清除，meta 索引（日期/预览快照）保留
    notifyListeners();
  }

  @override
  Future<DiaryPruneResult> pruneEmptyBefore(
    DateTime cutoff,
    bool Function(DiaryDocument document) isEmpty, {
    bool dryRun = false,
  }) async {
    final cutoffDay = _dayOnly(cutoff);
    //  cutoff 之前的全部日记（含 exported/archived），按日期升序，
    //  保证删除清单与保留原因报告稳定。
    final before =
        _entries.values.where((e) => e.date.isBefore(cutoffDay)).toList()
          ..sort((a, b) => a.date.compareTo(b.date));
    final deleted = <DateTime>[];
    final kept = <(DateTime, String)>[];
    for (final entry in before) {
      final day = _dayOnly(entry.date);
      switch (entry.state) {
        case DiaryDocState.draft:
          if (isEmpty(entry.doc!)) {
            deleted.add(day);
            if (!dryRun) _entries.remove(_keyOf(day));
          } else {
            kept.add((day, 'non-empty'));
          }
        case DiaryDocState.exported:
          kept.add((day, 'exported'));
        case DiaryDocState.archived:
          kept.add((day, 'archived'));
      }
    }
    if (deleted.isNotEmpty && !dryRun) notifyListeners();
    return DiaryPruneResult(deleted: deleted, kept: kept);
  }

  @override
  Future<DiaryWipeResult> wipeAll() async {
    // archived 条目的正文已物理删除，故「文件数」只数仍持有正文者。
    final removedFiles = _entries.values.where((e) => e.doc != null).length;
    final removedDocs = _entries.length;
    _entries.clear();
    notifyListeners();
    return DiaryWipeResult(
      removedDocs: removedDocs,
      removedFiles: removedFiles,
    );
  }

  DiaryDaySummary _summaryOf(_Entry entry) {
    if (entry.state == DiaryDocState.archived || entry.doc == null) {
      return DiaryDaySummary(
        date: _dayOnly(entry.date),
        title: entry.title,
        preview: entry.preview,
        blockCount: entry.blockCount,
        state: DiaryDocState.archived,
        updatedAt: entry.updatedAt,
      );
    }
    return DiaryDaySummary.fromDocument(entry.doc!, state: entry.state);
  }
}

/// 一条 meta 行的内存形态：archived 后 [doc] 为 null，
/// [title]/[preview]/[blockCount]/[updatedAt] 保留归档前快照供列表渲染。
class _Entry {
  _Entry._({required this.date, required this.state, this.doc});

  factory _Entry.fromDraft(DiaryDocument doc) =>
      _Entry._(date: doc.date, state: DiaryDocState.draft, doc: doc);

  final DateTime date;
  DiaryDocState state;
  DiaryDocument? doc;
  String title = '';
  String preview = '';
  int blockCount = 0;
  DateTime updatedAt = DateTime.fromMillisecondsSinceEpoch(0);
  DateTime? exportedAt;

  /// 状态迁移前固化列表摘要（exported/archived 后不再依赖正文计算）。
  void captureSummary() {
    final document = doc;
    if (document == null) return;
    title = document.title;
    preview = DiaryDaySummary.previewOf(document);
    blockCount = document.blocks.length;
    updatedAt = document.updatedAt;
  }
}
