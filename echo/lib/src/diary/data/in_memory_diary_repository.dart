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
  })  : _ids = idGenerator ?? SyIdGenerator(random: Random(0xE0C0)),
        _clock = clock ?? DiaryClock() {
    // 默认 debug 构建装种子、release 空仓；测试显式传 false 关闭。
    if (seedDebugData ?? kDebugMode) {
      for (final doc
          in DiarySeedData.build(idGenerator: _ids, today: _clock.today())) {
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
    final list = _entries.values
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
      throw StateError('${existing.state} 态日记不可覆盖：'
          '${document.date.year}-${document.date.month}-${document.date.day}');
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
    final list = _entries.values
        .where((e) => e.state == DiaryDocState.draft && e.date.year == year)
        .map((e) => e.doc!)
        .toList()
      ..sort((a, b) => a.date.compareTo(b.date));
    return list;
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
  Future<int> pruneEmptyBefore(
    DateTime cutoff,
    bool Function(DiaryDocument document) isEmpty,
  ) async {
    final cutoffDay = _dayOnly(cutoff);
    final doomed = _entries.entries
        .where((kv) =>
            kv.value.state == DiaryDocState.draft &&
            kv.value.date.isBefore(cutoffDay) &&
            isEmpty(kv.value.doc!))
        .map((kv) => kv.key)
        .toList(growable: false);
    for (final key in doomed) {
      _entries.remove(key);
    }
    if (doomed.isNotEmpty) notifyListeners();
    return doomed.length;
  }

  DiaryDaySummary _summaryOf(_Entry entry) {
    if (entry.state == DiaryDocState.archived || entry.doc == null) {
      return DiaryDaySummary(
        date: _dayOnly(entry.date),
        preview: entry.preview,
        blockCount: entry.blockCount,
        state: DiaryDocState.archived,
      );
    }
    return DiaryDaySummary.fromDocument(entry.doc!, state: entry.state);
  }
}

/// 一条 meta 行的内存形态：archived 后 [doc] 为 null，
/// [preview]/[blockCount] 保留归档前快照供列表渲染。
class _Entry {
  _Entry._({
    required this.date,
    required this.state,
    this.doc,
  });

  factory _Entry.fromDraft(DiaryDocument doc) =>
      _Entry._(date: doc.date, state: DiaryDocState.draft, doc: doc);

  final DateTime date;
  DiaryDocState state;
  DiaryDocument? doc;
  String preview = '';
  int blockCount = 0;
  DateTime? exportedAt;

  /// 状态迁移前固化列表摘要（exported/archived 后不再依赖正文计算）。
  void captureSummary() {
    final document = doc;
    if (document == null) return;
    preview = DiaryDaySummary.previewOf(document);
    blockCount = document.blocks.length;
  }
}
