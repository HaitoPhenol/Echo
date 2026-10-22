import 'package:flutter/material.dart';

import '../../data/diary_repository.dart';
import '../../export/diary_export_service.dart';
import '../diary_export_flow.dart';
import '../diary_export_scope.dart';
import '../diary_route.dart';
import '../widgets/diary_list_row.dart';
import '../widgets/diary_shell.dart';
import 'day_list_page.dart';

/// 月级别：只列含日记的月份；当前月由自动成稿保证存在（§5.2 裁定 3）。
///
/// 列表**倒序**（最新月份在上，当年的 12→1）；含今天的月份（仅当
/// 所浏览年份即当前年）用强调色，其余月份走默认页名标签色，与日页
/// 「今天」的强弱口径一致。
///
/// 「补记过去某天」自 2026-10-19 起移入**把手条快捷竖单**（笔记页常驻
/// 入口，见 `navigation/page_action.dart` 与 `DiaryPageState.startBackfill`），
/// 本页顶栏不再有「+」。
///
/// 每行 trailing 为**月**导出入口（2026-10-18 由年行迁来）：
/// 点导出先显示当前范围（「导出范围：yyyy 年 M 月」）并选渠道
/// （分享 / 另存，2026-10-22），打包该月**全部**日记（含已导出，
/// 2026-10-22 用户裁定）为「日记」笔记本 .sy.zip；分享经「确认已发送」、
/// 另存保存成功后才把早于今天的 draft 批量置 exported。**今日（未结束）
/// 的日记仍入包，但保持 draft 可继续写**，故当月再次导出会重复包含今日内容。
/// 该月所有笔记都无未导出时，导出按钮左侧另显「已导出」徽标（2026-10-19）。
class MonthListPage extends StatefulWidget {
  const MonthListPage({super.key, required this.year});

  final int year;

  @override
  State<MonthListPage> createState() => _MonthListPageState();
}

class _MonthListPageState extends State<MonthListPage> {
  DiaryRepository? _subscribed;
  Future<_MonthData>? _dataFuture;

  /// 正在导出的月份（同一时刻只允许一个；null = 空闲）。
  int? _exportingMonth;

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

  Future<void> _exportMonth(int month) async {
    if (_exportingMonth != null) return;
    final scopeLabel = '${widget.year} 年 $month 月';
    final channel = await showDiaryExportChannelSheet(
      context,
      scopeLabel: scopeLabel,
    );
    if (channel == null || !mounted) return;
    setState(() => _exportingMonth = month);
    final service = DiaryExportServiceScope.of(context);
    final messenger = ScaffoldMessenger.maybeOf(context);
    try {
      final outcome = await service.exportMonth(
        widget.year,
        month,
        channel: channel,
        // 分享面板取消/成功无法区分，返回后由用户人工确认是否真的送达；
        // 否认则草稿保留、可再次导出。另存有明确结果，无需确认。
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
      if (mounted) setState(() => _exportingMonth = null);
    }
  }

  Future<void> _openMonth(int month) async {
    await Navigator.of(context).push(
      DiarySlideRoute(
        builder: (_) => DayListPage(year: widget.year, month: month),
        settings: RouteSettings(name: '/year/${widget.year}/month/$month'),
      ),
    );
    _reload();
  }

  Future<_MonthData> _load(DiaryRepository repository) async {
    final months = await repository.monthsOfYear(widget.year);
    final counts = <int, int>{};
    final fullyExported = <int>{};
    for (final month in months) {
      counts[month] = await repository.draftCountOfMonth(widget.year, month);
      // 该月所有笔记都没有未导出（无 draft）→ 行尾显「已导出」徽标。
      if (await repository.isMonthFullyExported(widget.year, month)) {
        fullyExported.add(month);
      }
    }
    return _MonthData(months, counts, fullyExported);
  }

  @override
  void dispose() {
    _subscribed?.removeListener(_reload);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // 「今天」以仓储同源时钟为准（04:00 日界）：所浏览年份即当前年
    // 时，当前月行用强调色。
    final today = DiaryRepositoryScope.of(context).today();

    return DiaryShell(
      kicker: 'DIARY // ${widget.year}',
      title: '${widget.year} 年',
      onBack: () => Navigator.of(context).maybePop(),
      child: FutureBuilder<_MonthData>(
        future: _dataFuture,
        builder: (context, snapshot) {
          if (!snapshot.hasData) return const SizedBox.shrink();
          // 仓储按升序返回，列表倒序展示（最新月份在上）。
          final months = [...snapshot.data!.months]
            ..sort((a, b) => b.compareTo(a));
          final counts = snapshot.data!.counts;
          final fullyExported = snapshot.data!.fullyExported;
          // 仅当所浏览年份即当前年时，当前月才是「含今天的月份」。
          final isCurrentYear = widget.year == today.year;
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
                highlight: isCurrentYear && month == today.month,
                onTap: () => _openMonth(month),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // 「已导出」徽标（2026-10-19）：该月所有笔记都没有
                    // 未导出时才出现，置于导出按钮左侧。
                    if (fullyExported.contains(month)) ...[
                      const DiaryStateBadge(text: '已导出'),
                      const SizedBox(width: 6),
                    ],
                    DiaryExportIconButton(
                      tooltip: '导出 ${widget.year} 年 $month 月全部日记',
                      exporting: _exportingMonth == month,
                      // 任一月导出进行中时其余月行禁用，避免并发迁移。
                      enabled: _exportingMonth == null,
                      onPressed: () => _exportMonth(month),
                    ),
                  ],
                ),
              );
            },
          );
        },
      ),
    );
  }
}

/// 月列表一次性装载结果：月份序列 + 各月总篇数 + 各月「已全部导出」集合。
class _MonthData {
  const _MonthData(this.months, this.counts, this.fullyExported);

  final List<int> months;
  final Map<int, int> counts;

  /// 「已全部导出」的月份（该月存在记录且无 draft），月行据此显徽标。
  final Set<int> fullyExported;
}
