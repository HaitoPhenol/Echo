import 'package:flutter/material.dart';

import '../../data/diary_repository.dart';
import '../diary_composer_scope.dart';
import '../diary_route.dart';
import '../widgets/diary_shell.dart';
import '../widgets/diary_list_row.dart';
import 'day_editor_page.dart';
import 'day_list_page.dart';

/// 月级别：只列含日记的月份；当前月由自动成稿保证存在（§5.2 裁定 3）。
///
/// 顶栏「+ 补记」是过去空日的唯一入口：日期选择器可选范围 =
/// 过去任意日期 + 今天，未来日期禁用；选定后走同一个 ensureDay。
class MonthListPage extends StatefulWidget {
  const MonthListPage({super.key, required this.year});

  final int year;

  @override
  State<MonthListPage> createState() => _MonthListPageState();
}

class _MonthListPageState extends State<MonthListPage> {
  DiaryRepository? _subscribed;
  Future<_MonthData>? _dataFuture;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final repository = DiaryRepositoryScope.of(context);
    if (!identical(repository, _subscribed)) {
      _subscribed?.removeListener(_reload);
      _subscribed = repository..addListener(_reload);
    }
    _dataFuture ??= _load(repository);
  }

  void _reload() {
    if (!mounted) return;
    setState(() {
      _dataFuture = _load(_subscribed!);
    });
  }

  Future<void> _openMonth(int month) async {
    await Navigator.of(context).push(
      DiarySlideRoute(
        builder: (_) => DayListPage(year: widget.year, month: month),
        settings:
            RouteSettings(name: '/year/${widget.year}/month/$month'),
      ),
    );
    _reload();
  }

  /// 「+ 补记」：选定过去日期后直开编辑器（日页 ensureDay 负责成稿）。
  Future<void> _startBackfill() async {
    final today = DiaryComposerScope.of(context).clock.today();
    // 停留在所浏览年份：当年从今天选，往年从该年 12 月往回选。
    final initial = widget.year == today.year
        ? today
        : DateTime(widget.year, 12, 28);
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(2000),
      lastDate: today,
      helpText: '补记哪一天',
      selectableDayPredicate: (date) => !date.isAfter(today),
    );
    if (picked == null || !mounted) return;
    // 成稿交给日页 _load() 的同一个 ensureDay：那里还能判定「新开」
    // 并自动聚焦首个可写空段；选择器已保证不是未来日。
    await Navigator.of(context).push(
      DiarySlideRoute(
        builder: (_) => DayEditorPage(
          year: picked.year,
          month: picked.month,
          day: picked.day,
        ),
        settings: RouteSettings(
          name: '/day/${picked.year}/${picked.month}/${picked.day}',
        ),
      ),
    );
    _reload();
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
  void dispose() {
    _subscribed?.removeListener(_reload);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return DiaryShell(
      kicker: 'DIARY // ${widget.year}',
      title: '${widget.year}',
      onBack: () => Navigator.of(context).maybePop(),
      trailing: IconButton(
        tooltip: '补记',
        icon: const Icon(Icons.add, size: 20),
        onPressed: _startBackfill,
        visualDensity: VisualDensity.compact,
      ),
      child: FutureBuilder<_MonthData>(
        future: _dataFuture,
        builder: (context, snapshot) {
          if (!snapshot.hasData) return const SizedBox.shrink();
          final months = snapshot.data!.months;
          final counts = snapshot.data!.counts;
          if (months.isEmpty) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text(
                  '这一年还没有日记',
                  style: TextStyle(fontSize: 13, color: Color(0xFF8A8A8A)),
                ),
              ),
            );
          }
          return ListView.builder(
            padding: EdgeInsets.zero,
            itemCount: months.length,
            itemBuilder: (context, index) {
              final month = months[index];
              return DiaryListRow(
                head: '$month 月',
                sub: '${counts[month] ?? 0} 篇',
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
