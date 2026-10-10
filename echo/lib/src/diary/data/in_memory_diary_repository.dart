import 'dart:math';

import 'package:flutter/foundation.dart';

import '../sy/diary_model.dart';
import '../sy/sy_id.dart';
import 'diary_clock.dart';
import 'diary_repository.dart';

/// 内存版 [DiaryRepository]（M2-M4）。
///
/// 进程内 Map 存储，重启清空；M5 用 sqflite + `.sy` 草稿文件替换，
/// 浏览页与编辑器代码不变。
///
/// 「今天」一律取自注入的 [DiaryClock]（04:00 日界）。M4 起
/// 可达性不再由仓储兜底：空仓年/月列表为空，当前年月由
/// 模块初始化自动成稿（composer.ensureDay）保证自然出现。
class InMemoryDiaryRepository extends DiaryRepository {
  InMemoryDiaryRepository({
    SyIdGenerator? idGenerator,
    DiaryClock? clock,
    bool? seedDebugData,
  })  : _ids = idGenerator ?? SyIdGenerator(random: Random(0xE0C0)),
        _clock = clock ?? DiaryClock() {
    // 默认 debug 构建装种子、release 空仓；测试显式传 false 关闭。
    if (seedDebugData ?? kDebugMode) _installDebugSeeds();
  }

  final SyIdGenerator _ids;
  final DiaryClock _clock;

  /// 模板成稿共用同一 ID 发生器（与仓储内容器/种子 ID 同源）。
  SyIdGenerator get idGenerator => _ids;

  /// key = yyyymmdd（仅日记日），value = 文档。
  final Map<int, DiaryDocument> _docs = {};

  @override
  DateTime today() => _clock.today();

  static int _keyOf(DateTime date) =>
      date.year * 10000 + date.month * 100 + date.day;

  static DateTime _dayOnly(DateTime date) =>
      DateTime(date.year, date.month, date.day);

  @override
  Future<List<int>> availableYears() async {
    final years = _docs.values.map((d) => d.date.year).toSet();
    return years.toList()..sort();
  }

  @override
  Future<List<int>> monthsOfYear(int year) async {
    final months = _docs.values
        .where((d) => d.date.year == year)
        .map((d) => d.date.month)
        .toSet();
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

  @override
  Future<int> pruneEmptyBefore(
    DateTime cutoff,
    bool Function(DiaryDocument document) isEmpty,
  ) async {
    final cutoffDay = _dayOnly(cutoff);
    final doomed = _docs.values
        .where((d) => d.date.isBefore(cutoffDay) && isEmpty(d))
        .map((d) => _keyOf(d.date))
        .toList(growable: false);
    for (final key in doomed) {
      _docs.remove(key);
    }
    if (doomed.isNotEmpty) notifyListeners();
    return doomed.length;
  }

  DiaryDaySummary _summaryOf(DiaryDocument doc) {
    // 预览 = 用户写下的第一句：跳过 readonly data 快照与标题骨架
    // （模板成稿但一个字没写时预览为空，列表显「周X（空稿）」）。
    final preview = doc.blocks
        .where((b) =>
            !b.readonly && b.kind == DiaryBlockKind.paragraph)
        .map((b) => b.text.replaceAll('\n', ' ').trim())
        .firstWhere((t) => t.isNotEmpty, orElse: () => '');
    return DiaryDaySummary(
      date: _dayOnly(doc.date),
      preview: preview.length > 40 ? preview.substring(0, 40) : preview,
      blockCount: doc.blocks.length,
      state: DiaryDocState.draft,
    );
  }

  /// 开发期种子：昨天、上月各一篇，验证层级下钻；今天不种子——
  /// M4 起今天由进模块自动成稿接管。release 构建不安装（空仓）。
  void _installDebugSeeds() {
    final today = _clock.today();
    final yesterday = today.subtract(const Duration(days: 1));
    final lastMonth = DateTime(today.year, today.month - 1,
        min(today.day, 28));
    _seed(lastMonth, ['补一条上月的备忘。']);
    _seed(yesterday, ['昨天随手记的一行。', '第二段，测试分块之间的留白。']);
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
