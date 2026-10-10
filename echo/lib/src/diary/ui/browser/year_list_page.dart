import 'package:flutter/material.dart';

import '../../../theme/app_colors.dart';
import '../../data/diary_repository.dart';
import '../diary_export_scope.dart';
import '../diary_route.dart';
import '../widgets/diary_shell.dart';
import '../widgets/diary_list_row.dart';
import 'month_list_page.dart';

/// 年级别：只列含日记的年份；当前年由进模块自动成稿保证出现。
///
/// M5 起每行 trailing 为年增量导出入口：打包该年全部 draft 为
/// 「日记」笔记本 .sy.zip 并经系统分享送出，成功后批量置 exported。
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
    setState(() => _exportingYear = year);
    final service = DiaryExportServiceScope.of(context);
    final messenger = ScaffoldMessenger.maybeOf(context);
    try {
      final outcome = await service.exportYear(year);
      messenger?.clearSnackBars();
      messenger?.showSnackBar(
        SnackBar(
          content: Text(
            outcome.didShare
                ? '已分享 ${outcome.exportedCount} 篇 · 标记为已导出'
                : '$year 年没有待导出的草稿',
          ),
          duration: const Duration(seconds: 2),
        ),
      );
    } catch (_) {
      messenger?.clearSnackBars();
      messenger?.showSnackBar(
        const SnackBar(
          content: Text('导出失败，草稿已保留，请重试'),
          duration: Duration(seconds: 2),
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
              final exporting = _exportingYear == year;
              return DiaryListRow(
                head: '$year',
                onTap: () => Navigator.of(context).push(
                  DiarySlideRoute(
                    builder: (_) => MonthListPage(year: year),
                    settings: RouteSettings(name: '/year/$year'),
                  ),
                ),
                trailing: _YearExportButton(
                  year: year,
                  exporting: exporting,
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

/// 年行尾部导出按钮：空闲显分享图标，进行中转圈。
class _YearExportButton extends StatelessWidget {
  const _YearExportButton({
    required this.year,
    required this.exporting,
    required this.enabled,
    required this.onPressed,
  });

  final int year;
  final bool exporting;
  final bool enabled;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final color = enabled
        ? AppColors.pageLabel
        : AppColors.mechInkDim.withValues(alpha: 0.45);
    return IconButton(
      onPressed: enabled && !exporting ? onPressed : null,
      icon: exporting
          ? SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2, color: color),
            )
          : Icon(Icons.ios_share, size: 17, color: color),
      iconSize: 17,
      visualDensity: VisualDensity.compact,
      constraints: const BoxConstraints(minWidth: 32, minHeight: 28),
      padding: const EdgeInsets.symmetric(horizontal: 4),
      splashRadius: 14,
      tooltip: '导出 $year 年草稿',
    );
  }
}
