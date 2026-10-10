import 'package:flutter/material.dart';

import '../../data/diary_repository.dart';
import '../diary_route.dart';
import '../widgets/diary_shell.dart';
import '../widgets/diary_list_row.dart';
import 'day_editor_page.dart';

/// 日级别：整月逐日枚举（降序），有草稿显示预览；
/// 查看当前月时顶部置顶「今天」快捷入口。
class DayListPage extends StatefulWidget {
  const DayListPage({super.key, required this.year, required this.month});

  final int year;
  final int month;

  @override
  State<DayListPage> createState() => _DayListPageState();
}

class _DayListPageState extends State<DayListPage> {
  static const List<String> _weekdays = ['一', '二', '三', '四', '五', '六', '日'];

  Future<List<DiaryDaySummary>>? _daysFuture;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _daysFuture ??= DiaryRepositoryScope.of(context)
        .daysOfMonth(widget.year, widget.month);
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
    if (mounted) {
      setState(() {
        _daysFuture = DiaryRepositoryScope.of(context)
            .daysOfMonth(widget.year, widget.month);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final isCurrentMonth = now.year == widget.year && now.month == widget.month;
    final daysInMonth = DateTime(widget.year, widget.month + 1, 0).day;
    final daysFuture = _daysFuture;

    return DiaryShell(
      kicker: 'DIARY // ${widget.year}.${widget.month}',
      title: '${widget.month} 月',
      onBack: () => Navigator.of(context).maybePop(),
      child: daysFuture == null
          ? const SizedBox.shrink()
          : FutureBuilder<List<DiaryDaySummary>>(
              future: daysFuture,
              builder: (context, snapshot) {
                final summaries = {
                  for (final s in snapshot.data ?? const <DiaryDaySummary>[])
                    s.date.day: s,
                };

                return ListView.builder(
                  padding: EdgeInsets.zero,
                  itemCount: daysInMonth + (isCurrentMonth ? 1 : 0),
                  itemBuilder: (context, index) {
                    if (isCurrentMonth && index == 0) {
                      final todaySummary = summaries[now.day];
                      return DiaryListRow(
                        head: '今天',
                        sub:
                            todaySummary?.preview ??
                            '${now.month}月${now.day}日 周${_weekdays[now.weekday - 1]}',
                        highlight: true,
                        onTap: () => _openDay(now.day),
                      );
                    }
                    final day =
                        daysInMonth - (index - (isCurrentMonth ? 1 : 0));
                    if (isCurrentMonth && day == now.day) {
                      return const SizedBox.shrink(); // 已置顶
                    }
                    final summary = summaries[day];
                    final date = DateTime(widget.year, widget.month, day);
                    return DiaryListRow(
                      head: '$day日',
                      dim: summary == null,
                      sub:
                          summary?.preview ?? '周${_weekdays[date.weekday - 1]}',
                      trailing: summary == null
                          ? null
                          : Text(
                              '${summary.blockCount} 块',
                              style: const TextStyle(
                                fontSize: 11,
                                color: Color(0xFF646464),
                              ),
                            ),
                      onTap: () => _openDay(day),
                    );
                  },
                );
              },
            ),
    );
  }
}
