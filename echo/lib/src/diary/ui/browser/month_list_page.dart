import 'package:flutter/material.dart';

import '../../../theme/app_colors.dart';
import '../../data/diary_repository.dart';
import '../diary_composer_scope.dart';
import '../diary_export_scope.dart';
import '../diary_route.dart';
import '../widgets/diary_shell.dart';
import '../widgets/diary_list_row.dart';
import 'day_editor_page.dart';
import 'day_list_page.dart';

/// 月级别：只列含日记的月份；当前月由自动成稿保证存在（§5.2 裁定 3）。
///
/// 列表**倒序**（最新月份在上，当年的 12→1）；含今天的月份（仅当
/// 所浏览年份即当前年）用强调色，其余月份走默认页名标签色，与日页
/// 「今天」的强弱口径一致。
///
/// 顶栏「+ 补记」是过去空日的唯一入口：日期选择器可选范围 =
/// 过去任意日期 + 今天，未来日期禁用；选定后走同一个 ensureDay。
///
/// 每行 trailing 为**月**增量导出入口（2026-10-18 由年行迁来）：
/// 打包该月全部 draft 为「日记」笔记本 .sy.zip 并经系统分享送出，
/// 用户在「确认已发送」对话框确认后批量置 exported；否认则保留
/// draft 可再次导出。该月所有笔记都无未导出时，导出按钮左侧另显
/// 「已导出」徽标（2026-10-19）。
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
    setState(() => _exportingMonth = month);
    final service = DiaryExportServiceScope.of(context);
    final messenger = ScaffoldMessenger.maybeOf(context);
    final year = widget.year;
    try {
      final outcome = await service.exportMonth(
        year,
        month,
        // Android 分享面板取消/成功无法区分，返回后由用户人工确认
        // 是否真的送达；否认则草稿保留、可再次导出。
        confirmShared: _confirmSent,
      );
      messenger?.clearSnackBars();
      messenger?.showSnackBar(
        SnackBar(
          content: Text(
            outcome.didShare
                ? '已分享 ${outcome.exportedCount} 篇 · 标记为已导出'
                : outcome.userDenied
                ? '未标记为已导出，草稿仍保留，可再次导出'
                : '$year 年 $month 月没有待导出的草稿',
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
      if (mounted) setState(() => _exportingMonth = null);
    }
  }

  /// 系统分享返回后的人工确认（share_plus 不回报真实发送结果）。
  /// 点「尚未发送」/ 点弹窗外关闭 → false，草稿不迁移。
  Future<bool> _confirmSent() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('确认已发送？'),
        content: const Text(
          '系统分享不会回报发送结果。请确认已把文件发送到思源'
          '（或另存成功）后，再标记为已导出。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('尚未发送'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('确认已发送'),
          ),
        ],
      ),
    );
    return confirmed ?? false;
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
      // 裸图标 + 手势而非 IconButton：头部行统一 28px 中线，见
      // diary_shell.dart 头部注释；IconButton 最小点击高度会撑高行。
      trailing: Tooltip(
        message: '补记',
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: _startBackfill,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6),
            child: Icon(Icons.add, size: 17, color: AppColors.pageLabel),
          ),
        ),
      ),
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
                    _MonthExportButton(
                      year: widget.year,
                      month: month,
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

/// 月行尾部导出按钮：空闲显分享图标，进行中转圈。
class _MonthExportButton extends StatelessWidget {
  const _MonthExportButton({
    required this.year,
    required this.month,
    required this.exporting,
    required this.enabled,
    required this.onPressed,
  });

  final int year;
  final int month;
  final bool exporting;
  final bool enabled;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final color = enabled
        ? AppColors.pageLabel
        : AppColors.mechInkDim.withValues(alpha: 0.45);
    // 裸图标 + 手势而非 IconButton：头部行统一 28px 中线，见
    // diary_shell.dart 头部注释；IconButton 最小点击高度会撑高行。
    return Tooltip(
      message: '导出 $year 年 $month 月草稿',
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: enabled && !exporting ? onPressed : null,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6),
          child: exporting
              ? SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2, color: color),
                )
              : Icon(Icons.ios_share, size: 17, color: color),
        ),
      ),
    );
  }
}
