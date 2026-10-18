import 'package:flutter/material.dart';

import '../../data/diary_repository.dart';
import '../diary_route.dart';
import '../widgets/diary_shell.dart';
import '../widgets/diary_list_row.dart';
import 'month_list_page.dart';

/// 年级别：只列含日记的年份；当前年由进模块自动成稿保证出现。
///
/// 列表**倒序**（最新年份在上）；含今天的年份（即当前年）用强调色，
/// 其余年份走默认页名标签色，与日页「今天」的强弱口径一致。
///
/// 导出入口已由年行迁至**月列表每行**（2026-10-18 用户裁定：导出
/// 粒度年 → 月），本页只负责导航到月份列表。
class YearListPage extends StatefulWidget {
  const YearListPage({super.key});

  @override
  State<YearListPage> createState() => _YearListPageState();
}

class _YearListPageState extends State<YearListPage> {
  @override
  Widget build(BuildContext context) {
    // 依赖仓储：草稿落盘 / 状态迁移通知会让本页随 InheritedNotifier
    // 自动重建，FutureBuilder 取到新 future，列表即时刷新。
    final repository = DiaryRepositoryScope.of(context);
    // 「今天」以仓储同源时钟为准（04:00 日界）：当前年行用强调色。
    final todayYear = repository.today().year;

    return DiaryShell(
      kicker: 'DIARY // YEAR',
      title: '日记',
      child: FutureBuilder<List<int>>(
        future: repository.availableYears(),
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const SizedBox.shrink();
          }
          // 仓储按升序返回，列表倒序展示（最新年份在上）。
          final years = [...snapshot.data!]..sort((a, b) => b.compareTo(a));
          if (years.isEmpty) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text(
                  '还没有日记',
                  style: TextStyle(fontSize: 13, color: Color(0xFF8A8A8A)),
                ),
              ),
            );
          }
          return ListView.builder(
            padding: EdgeInsets.zero,
            itemCount: years.length,
            itemBuilder: (context, index) {
              final year = years[index];
              return DiaryListRow(
                head: '$year 年',
                highlight: year == todayYear,
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
