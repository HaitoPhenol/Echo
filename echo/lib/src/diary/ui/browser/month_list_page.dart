import 'package:flutter/material.dart';

import '../../data/diary_repository.dart';
import '../diary_route.dart';
import '../widgets/diary_shell.dart';
import '../widgets/diary_list_row.dart';
import 'day_list_page.dart';

/// 月级别：列出某年可浏览月份（当前月恒在列）。
///
/// 视觉层级：有草稿的月份常亮并标篇数；当月无草稿时弱化并标「本月」；
/// 当月有草稿时强调（与日列表「今天」同级语言）。
class MonthListPage extends StatefulWidget {
  const MonthListPage({super.key, required this.year});

  final int year;

  @override
  State<MonthListPage> createState() => _MonthListPageState();
}

class _MonthListPageState extends State<MonthListPage> {
  Future<_MonthData>? _dataFuture;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // InheritedNotifier（仓储）变化（从编辑器返回带新草稿）时重建 future。
    _dataFuture ??= _load(DiaryRepositoryScope.of(context));
  }

  Future<void> _openMonth(int month) async {
    await Navigator.of(context).push(
      DiarySlideRoute(
        builder: (_) => DayListPage(year: widget.year, month: month),
        settings:
            RouteSettings(name: '/year/${widget.year}/month/$month'),
      ),
    );
    // 从日列表/编辑器返回：可能新增了草稿，重新装载篇数。
    if (mounted) {
      setState(() {
        _dataFuture = _load(DiaryRepositoryScope.of(context));
      });
    }
  }

  Future<_MonthData> _load(DiaryRepository repository) async {
    final months = await repository.monthsOfYear(widget.year);
    final counts = <int, int>{
      for (final month in months)
        month: await repository.draftCountOfMonth(widget.year, month),
    };
    return _MonthData(months, counts);
  }

  @override
  Widget build(BuildContext context) {
    final now = DiaryRepositoryScope.of(context).today();

    return DiaryShell(
      kicker: 'DIARY // ${widget.year}',
      title: '${widget.year}',
      onBack: () => Navigator.of(context).maybePop(),
      child: FutureBuilder<_MonthData>(
        future: _dataFuture,
        builder: (context, snapshot) {
          if (!snapshot.hasData) return const SizedBox.shrink();
          final months = snapshot.data!.months;
          final counts = snapshot.data!.counts;
          return ListView.builder(
            padding: EdgeInsets.zero,
            itemCount: months.length,
            itemBuilder: (context, index) {
              final month = months[index];
              final count = counts[month] ?? 0;
              final isCurrent =
                  widget.year == now.year && month == now.month;
              final hasContent = count > 0;
              final sub = isCurrent
                  ? (hasContent ? '本月 · $count 篇' : '本月')
                  : '$count 篇';
              return DiaryListRow(
                head: '$month 月',
                sub: sub,
                dim: !hasContent,
                highlight: isCurrent && hasContent,
                onTap: () => _openMonth(month),
              );
            },
          );
        },
      ),
    );
  }
}

/// 月列表一次性装载结果：月份序列 + 各月草稿篇数。
class _MonthData {
  const _MonthData(this.months, this.counts);

  final List<int> months;
  final Map<int, int> counts;
}
