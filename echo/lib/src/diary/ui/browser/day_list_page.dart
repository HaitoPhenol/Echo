import 'package:flutter/material.dart';

import '../../data/diary_repository.dart';
import '../diary_composer_scope.dart';
import '../diary_route.dart';
import '../widgets/diary_shell.dart';
import '../widgets/diary_list_row.dart';
import 'day_editor_page.dart';

/// 日级别：只显示真实存在的日记（UI 倒序）。
///
/// M4 行为反转（§5.2 硬裁定 3）：删除整月逐日枚举、空日弱化行与
/// 「今天置顶」特例行——今天由进模块自动成稿保证自然出现在列表顶部；
/// 未来日期没有任何入口，过去空日补记在月页完成。
class DayListPage extends StatefulWidget {
  const DayListPage({super.key, required this.year, required this.month});

  final int year;
  final int month;

  @override
  State<DayListPage> createState() => _DayListPageState();
}

class _DayListPageState extends State<DayListPage> {
  static const List<String> _weekdays = [
    '一', '二', '三', '四', '五', '六', '日',
  ];

  DiaryRepository? _subscribed;
  Future<List<DiaryDaySummary>>? _daysFuture;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final repository = DiaryRepositoryScope.of(context);
    if (!identical(repository, _subscribed)) {
      _subscribed?.removeListener(_reload);
      _subscribed = repository..addListener(_reload);
    }
    _daysFuture ??= repository.daysOfMonth(widget.year, widget.month);
  }

  void _reload() {
    if (!mounted) return;
    setState(() {
      _daysFuture =
          _subscribed!.daysOfMonth(widget.year, widget.month);
    });
  }

  Future<void> _openDay(int day) async {
    await Navigator.of(context).push(
      DiarySlideRoute(
        builder: (_) =>
            DayEditorPage(year: widget.year, month: widget.month, day: day),
        settings: RouteSettings(
          name: '/day/${widget.year}/${widget.month}/$day',
        ),
      ),
    );
    // 从编辑页返回后刷新草稿预览（页面在路由下一直保活）。
    _reload();
  }

  @override
  void dispose() {
    _subscribed?.removeListener(_reload);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final clock = DiaryComposerScope.of(context).clock;
    final today = clock.today();
    final isCurrentMonth =
        today.year == widget.year && today.month == widget.month;

    return DiaryShell(
      kicker: 'DIARY // ${widget.year}.${widget.month}',
      title: '${widget.month} 月',
      onBack: () => Navigator.of(context).maybePop(),
      child: FutureBuilder<List<DiaryDaySummary>>(
        future: _daysFuture,
        builder: (context, snapshot) {
          final summaries = [...?snapshot.data]
            ..sort((a, b) => b.date.compareTo(a.date)); // 倒序：新的在上

          if (summaries.isEmpty) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text(
                  '本月还没有日记',
                  style: TextStyle(fontSize: 13, color: Color(0xFF8A8A8A)),
                ),
              ),
            );
          }

          return ListView.builder(
            padding: EdgeInsets.zero,
            itemCount: summaries.length,
            itemBuilder: (context, index) {
              final summary = summaries[index];
              final date = summary.date;
              final isToday = isCurrentMonth && date.day == today.day;
              return DiaryListRow(
                head: isToday ? '今天' : '${date.day}日',
                highlight: isToday,
                sub: summary.preview.isEmpty
                    ? '周${_weekdays[date.weekday - 1]}（空稿）'
                    : summary.preview,
                trailing: Text(
                  '${summary.blockCount} 块',
                  style: const TextStyle(
                    fontSize: 11,
                    color: Color(0xFF646464),
                  ),
                ),
                onTap: () => _openDay(date.day),
              );
            },
          );
        },
      ),
    );
  }
}
