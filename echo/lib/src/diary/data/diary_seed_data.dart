import 'dart:math';

import '../sy/diary_model.dart';
import '../sy/sy_id.dart';

/// 开发期种子数据（debug 首装验证年→月→日层级下钻；release 空仓）。
///
/// 内存仓储与 M5 持久仓储共用本构造，防止两条装配路径种子漂移。
/// 今天不种子——M4 起今天由进模块 `composer.ensureDay` 自动成稿接管。
class DiarySeedData {
  const DiarySeedData._();

  /// 构造「上月一篇 + 昨天一篇」两份草稿（日期按日记日时钟的今天回推）。
  static List<DiaryDocument> build({
    required SyIdGenerator idGenerator,
    required DateTime today,
  }) {
    final yesterday = today.subtract(const Duration(days: 1));
    // 日取 28 号：任意月份回退一个月都不会越界（DateTime 会归一 12→1 月）。
    final lastMonth =
        DateTime(today.year, today.month - 1, min(today.day, 28));
    return [
      _seedDoc(idGenerator, lastMonth, ['补一条上月的备忘。']),
      _seedDoc(
        idGenerator,
        yesterday,
        ['昨天随手记的一行。', '第二段，测试分块之间的留白。'],
      ),
    ];
  }

  static DiaryDocument _seedDoc(
    SyIdGenerator ids,
    DateTime day,
    List<String> paragraphs,
  ) {
    const weekdays = ['周一', '周二', '周三', '周四', '周五', '周六', '周日'];
    return DiaryDocument(
      id: SyIdGenerator.dayContainer(day),
      date: day,
      title: '${day.month}月${day.day}日 ${weekdays[day.weekday - 1]}',
      blocks: [
        for (final text in paragraphs)
          DiaryBlock(id: ids.next(), text: text),
      ],
    );
  }
}
