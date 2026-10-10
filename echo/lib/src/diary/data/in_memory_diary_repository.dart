import 'dart:math';

import 'package:flutter/foundation.dart';

import '../sy/diary_model.dart';
import '../sy/sy_id.dart';
import 'diary_repository.dart';

/// 内存版 [DiaryRepository]（M2）。
///
/// 进程内 Map 存储，重启清空；M5 用 sqflite + `.sy` 草稿文件替换，
/// 浏览页与编辑器代码不变。
///
/// 可达性保证：即使仓为空，当前年/月仍出现在浏览层级中（日列表页
/// 自行枚举整月日期），用户永远能点进「今天」并开始写。
class InMemoryDiaryRepository extends DiaryRepository {
  InMemoryDiaryRepository({
    SyIdGenerator? idGenerator,
    DateTime Function()? now,
    bool? seedDebugData,
  })  : _ids = idGenerator ?? SyIdGenerator(random: Random(0xE0C0)),
        _now = now ?? DateTime.now {
    // 默认 debug 构建装种子、release 空仓；测试显式传 false 关闭。
    if (seedDebugData ?? kDebugMode) _installDebugSeeds();
  }

  final SyIdGenerator _ids;
  final DateTime Function() _now;

  /// key = yyyymmdd（仅自然日），value = 文档。
  final Map<int, DiaryDocument> _docs = {};

  @override
  DateTime today() {
    final n = _now();
    return DateTime(n.year, n.month, n.day);
  }

  static int _keyOf(DateTime date) =>
      date.year * 10000 + date.month * 100 + date.day;

  static DateTime _dayOnly(DateTime date) =>
      DateTime(date.year, date.month, date.day);

  @override
  Future<List<int>> availableYears() async {
    final years = _docs.values.map((d) => d.date.year).toSet()
      ..add(_now().year);
    return years.toList()..sort();
  }

  @override
  Future<List<int>> monthsOfYear(int year) async {
    final months = _docs.values
        .where((d) => d.date.year == year)
        .map((d) => d.date.month)
        .toSet();
    final today = _now();
    if (year == today.year) months.add(today.month);
    return months.toList()..sort();
  }

  @override
  Future<List<DiaryDaySummary>> daysOfMonth(int year, int month) async {
    final list = _docs.values
        .where((d) => d.date.year == year && d.date.month == month)
        .toList()
      ..sort((a, b) => a.date.compareTo(b.date));
    return list.map(_summaryOf).toList();
  }

  @override
  Future<int> draftCountOfMonth(int year, int month) async => _docs.values
      .where((d) => d.date.year == year && d.date.month == month)
      .length;

  @override
  Future<DiaryDocument?> findDay(DateTime date) async =>
      _docs[_keyOf(date)];

  @override
  Future<void> upsertDraft(DiaryDocument document) async {
    _docs[_keyOf(document.date)] = document;
    notifyListeners();
  }

  DiaryDaySummary _summaryOf(DiaryDocument doc) {
    final preview = doc.blocks
        .map((b) => b.text.replaceAll('\n', ' ').trim())
        .firstWhere((t) => t.isNotEmpty, orElse: () => '');
    return DiaryDaySummary(
      date: _dayOnly(doc.date),
      preview: preview.length > 40 ? preview.substring(0, 40) : preview,
      blockCount: doc.blocks.length,
      state: DiaryDocState.draft,
    );
  }

  /// 开发期种子：今天/昨天/上月各一篇，层级与编辑器打开即有内容可看。
  /// release 构建不安装（空仓）。
  void _installDebugSeeds() {
    final today = _dayOnly(_now());
    final yesterday = today.subtract(const Duration(days: 1));
    final lastMonth = DateTime(today.year, today.month - 1,
        min(today.day, 28));
    _seed(lastMonth, ['补一条上月的备忘。']);
    _seed(yesterday, ['昨天随手记的一行。', '第二段，测试分块之间的留白。']);
    _seed(today, ['今天的第一条记录。']);
  }

  void _seed(DateTime day, List<String> paragraphs) {
    final doc = DiaryDocument(
      id: SyIdGenerator.dayContainer(day),
      date: day,
      title: '${day.month}月${day.day}日 '
          '${const ['周一', '周二', '周三', '周四', '周五', '周六', '周日'][day.weekday - 1]}',
      blocks: [
        for (final text in paragraphs)
          DiaryBlock(id: _ids.next(), text: text),
      ],
    );
    _docs[_keyOf(day)] = doc;
  }
}
