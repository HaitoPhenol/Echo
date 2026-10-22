import 'package:flutter/material.dart';

import '../../data/diary_repository.dart';
import '../../export/diary_export_service.dart';
import '../diary_export_flow.dart';
import '../diary_export_scope.dart';
import '../diary_route.dart';
import '../widgets/diary_shell.dart';
import '../widgets/diary_list_row.dart';
import 'month_list_page.dart';

/// 年级别：只列含日记的年份；当前年由进模块自动成稿保证出现。
///
/// 列表**倒序**（最新年份在上）；含今天的年份（即当前年）用强调色，
/// 其余年份走默认页名标签色，与日页「今天」的强弱口径一致。
///
/// 每行 trailing 为**年**导出入口（2026-10-22 用户裁定：导出粒度跟随
/// 页面层级）：点导出先提示范围「导出范围：yyyy 年」并选渠道，打包该年
/// **全部**日记（含已导出）为「日记」笔记本 .sy.zip；迁移规则同月导出
/// （今日草稿入包但保持可编辑）。月列表内仍保留月粒度导出入口。
class YearListPage extends StatefulWidget {
  const YearListPage({super.key});

  @override
  State<YearListPage> createState() => _YearListPageState();
}

class _YearListPageState extends State<YearListPage> {
  /// 正在导出的年份（同一时刻只允许一个；null = 空闲）。
  int? _exportingYear;

  Future<void> _exportYear(int year) async {
    if (_exportingYear != null) return;
    final scopeLabel = '$year 年';
    final channel = await showDiaryExportChannelSheet(
      context,
      scopeLabel: scopeLabel,
    );
    if (channel == null || !mounted) return;
    setState(() => _exportingYear = year);
    final service = DiaryExportServiceScope.of(context);
    final messenger = ScaffoldMessenger.maybeOf(context);
    try {
      final outcome = await service.exportYear(
        year,
        channel: channel,
        confirmShared: channel == DiaryExportChannel.share
            ? () => confirmDiaryShareSent(context)
            : null,
      );
      messenger?.clearSnackBars();
      messenger?.showSnackBar(
        SnackBar(
          content: Text(diaryExportResultText(outcome)),
          duration: const Duration(seconds: 2),
        ),
      );
    } catch (_) {
      messenger?.clearSnackBars();
      messenger?.showSnackBar(
        SnackBar(
          content: Text('导出失败，$scopeLabel内容已保留，请重试'),
          duration: const Duration(seconds: 2),
        ),
      );
    } finally {
      if (mounted) setState(() => _exportingYear = null);
    }
  }

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
                trailing: DiaryExportIconButton(
                  tooltip: '导出 $year 年全部日记',
                  exporting: _exportingYear == year,
                  // 任一年导出进行中时其余年行禁用，避免并发迁移。
                  enabled: _exportingYear == null,
                  onPressed: () => _exportYear(year),
                ),
              );
            },
          );
        },
      ),
    );
  }
}
