import 'package:flutter/material.dart';

import '../../data/diary_repository.dart';
import '../diary_route.dart';
import '../widgets/diary_shell.dart';
import '../widgets/diary_list_row.dart';
import 'month_list_page.dart';

/// 年级别：列出可浏览年份（当前年恒在列，保证「今天」可达）。
class YearListPage extends StatelessWidget {
  const YearListPage({super.key});

  @override
  Widget build(BuildContext context) {
    // 依赖仓储：草稿落盘通知会让本页随 InheritedNotifier 自动重建，
    // FutureBuilder 取到新 future，列表即时刷新。
    final repository = DiaryRepositoryScope.of(context);

    return DiaryShell(
      kicker: 'DIARY // YEAR',
      title: '日记',
      child: FutureBuilder<List<int>>(
        future: repository.availableYears(),
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const SizedBox.shrink();
          }
          final years = snapshot.data!;
          return ListView.builder(
            padding: EdgeInsets.zero,
            itemCount: years.length,
            itemBuilder: (context, index) {
              final year = years[index];
              return DiaryListRow(
                head: '$year',
                onTap: () => Navigator.of(context).push(
                  DiarySlideRoute(
                    builder: (_) => MonthListPage(year: year),
                    settings: RouteSettings(name: '/year/$year'),
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
