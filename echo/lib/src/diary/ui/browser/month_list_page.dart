import 'package:flutter/material.dart';

import '../../data/diary_repository.dart';
import '../diary_route.dart';
import '../widgets/diary_shell.dart';
import '../widgets/diary_list_row.dart';
import 'day_list_page.dart';

/// 月级别：列出某年可浏览月份（当前月恒在列）。
class MonthListPage extends StatelessWidget {
  const MonthListPage({super.key, required this.year});

  final int year;

  @override
  Widget build(BuildContext context) {
    final repository = DiaryRepositoryScope.of(context);

    return DiaryShell(
      kicker: 'DIARY // $year',
      title: '$year',
      onBack: () => Navigator.of(context).maybePop(),
      child: FutureBuilder<List<int>>(
        future: repository.monthsOfYear(year),
        builder: (context, snapshot) {
          if (!snapshot.hasData) return const SizedBox.shrink();
          final months = snapshot.data!;
          return ListView.builder(
            padding: EdgeInsets.zero,
            itemCount: months.length,
            itemBuilder: (context, index) {
              final month = months[index];
              return DiaryListRow(
                head: '$month 月',
                sub: '$year.$month',
                onTap: () => Navigator.of(context).push(
                  DiarySlideRoute(
                    builder: (_) =>
                        DayListPage(year: year, month: month),
                    settings: RouteSettings(name: '/year/$year/month/$month'),
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}
