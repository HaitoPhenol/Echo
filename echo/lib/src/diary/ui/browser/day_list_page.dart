import 'package:flutter/material.dart';

import '../../../theme/app_colors.dart';
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
///
/// M5 状态徽标：exported 行尾显「已导出」（仍可点入只读查看）；
/// archived 行置灰、行尾「已归档」、点按拦截提示（正文已清理）。
class DayListPage extends StatefulWidget {
  const DayListPage({super.key, required this.year, required this.month});

  final int year;
  final int month;

  @override
  State<DayListPage> createState() => _DayListPageState();
}

class _DayListPageState extends State<DayListPage> {
  static const List<String> _weekdays = ['一', '二', '三', '四', '五', '六', '日'];

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
      _daysFuture = _subscribed!.daysOfMonth(widget.year, widget.month);
    });
  }

  Future<void> _openDay(DiaryDaySummary summary) async {
    if (summary.state == DiaryDocState.archived) {
      // 终态：正文已从本机清理，不进入编辑器。
      final messenger = ScaffoldMessenger.maybeOf(context);
      messenger?.clearSnackBars();
      messenger?.showSnackBar(
        const SnackBar(
          content: Text('已归档：正文已从本机清理，仅保留索引'),
          duration: Duration(seconds: 2),
        ),
      );
      return;
    }
    await Navigator.of(context).push(
      DiarySlideRoute(
        builder: (_) => DayEditorPage(
          year: widget.year,
          month: widget.month,
          day: summary.date.day,
        ),
        settings: RouteSettings(
          name: '/day/${widget.year}/${widget.month}/${summary.date.day}',
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
              final archived = summary.state == DiaryDocState.archived;
              final weekday = '周${_weekdays[date.weekday - 1]}';
              return DiaryListRow(
                head: isToday ? '今天' : '${date.day}日',
                highlight: isToday,
                dim: archived,
                // 归档稿保留的是归档前预览快照；空预览退化为星期小字，
                // 不显示「空稿」（已导出的日记不存在空稿语义）。
                sub: summary.preview.isNotEmpty ? summary.preview : weekday,
                trailing: switch (summary.state) {
                  DiaryDocState.archived => const _StateBadge(
                    text: '已归档',
                    dim: true,
                  ),
                  DiaryDocState.exported => const _StateBadge(text: '已导出'),
                  DiaryDocState.draft => Text(
                    '${summary.blockCount} 块',
                    style: const TextStyle(
                      fontSize: 11,
                      color: Color(0xFF646464),
                    ),
                  ),
                },
                onTap: () => _openDay(summary),
              );
            },
          );
        },
      ),
    );
  }
}

/// 日行尾部状态徽标（已导出 / 已归档）。
class _StateBadge extends StatelessWidget {
  const _StateBadge({required this.text, this.dim = false});

  final String text;
  final bool dim;

  @override
  Widget build(BuildContext context) {
    final color = dim ? AppColors.mechInkDim : AppColors.pageLabel;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: AppColors.tone1,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: AppColors.tone1),
      ),
      child: Text(
        text,
        style: TextStyle(fontSize: 10, letterSpacing: 1.2, color: color),
      ),
    );
  }
}
