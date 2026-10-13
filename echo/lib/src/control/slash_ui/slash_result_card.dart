/// slash 结果卡片：把纯 Dart 的 ResultView 渲染成紧凑卡片
/// （G2 搜索栏；未来终端页换皮复用同一个 view model）。
///
/// - [ErrorView]：红色语义条 + 有线码 + 人话消息（need/elevate/
///   retryAfterMs 扁平呈现，PIN 引导由控制器层自动驱动）；
/// - [TableView]：横向可滚的紧凑表格；
/// - [KeyValueView]：键值两栏，嵌套 Map 递归、List/复杂值内嵌 JSON；
/// - [JsonView]：等宽字体块，**长按复制**全文（剪贴板）。
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../theme/app_colors.dart';
import '../slash/result_view.dart';

class SlashResultCard extends StatelessWidget {
  const SlashResultCard({super.key, required this.view});

  final ResultView view;

  @override
  Widget build(BuildContext context) {
    final child = switch (view) {
      ErrorView e => _ErrorBody(view: e),
      TableView t => _TableBody(view: t),
      KeyValueView k => _KeyValueBody(view: k),
      JsonView j => _JsonBody(view: j),
    };
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.overlaySurface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: view is ErrorView
              ? AppColors.anchorRed.withValues(alpha: 0.5)
              : AppColors.tone1,
        ),
      ),
      child: child,
    );
  }
}

// ---- 错误 ---------------------------------------------------------------

class _ErrorBody extends StatelessWidget {
  const _ErrorBody({required this.view});

  final ErrorView view;

  @override
  Widget build(BuildContext context) {
    final cooldown = view.retryAfterMs;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            Icon(Icons.error_outline, size: 14, color: AppColors.anchorRed),
            const SizedBox(width: 6),
            Text(
              view.code,
              style: const TextStyle(
                color: AppColors.anchorRed,
                fontSize: 11,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.5,
              ),
            ),
            if (view.need != null) ...[
              const SizedBox(width: 8),
              Text(
                '需要 ${view.need} 级',
                style: const TextStyle(
                  color: AppColors.textMuted,
                  fontSize: 11,
                ),
              ),
            ],
          ],
        ),
        const SizedBox(height: 4),
        Text(
          cooldown != null
              ? '${view.message}（剩余 ${(cooldown / 1000).ceil()} 秒）'
              : view.message,
          style: const TextStyle(color: AppColors.textPrimary, fontSize: 13),
        ),
        if (view.elevate != null) ...[
          const SizedBox(height: 4),
          Text(
            '提权路径：${view.elevate}',
            style: const TextStyle(color: AppColors.textMuted, fontSize: 11),
          ),
        ],
      ],
    );
  }
}

// ---- 表格 ---------------------------------------------------------------

class _TableBody extends StatelessWidget {
  const _TableBody({required this.view});

  final TableView view;

  @override
  Widget build(BuildContext context) {
    if (view.rows.isEmpty) {
      return const Text(
        '（空列表）',
        style: TextStyle(color: AppColors.textMuted, fontSize: 12),
      );
    }
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Table(
        defaultColumnWidth: const IntrinsicColumnWidth(),
        border: TableBorder.all(color: AppColors.tone1),
        children: [
          TableRow(
            decoration: const BoxDecoration(color: Color(0x14FFFFFF)),
            children: [
              for (final c in view.columns)
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 5,
                  ),
                  child: Text(
                    c,
                    style: const TextStyle(
                      color: AppColors.pageLabel,
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
            ],
          ),
          for (final row in view.rows)
            TableRow(
              children: [
                for (final cell in row)
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 5,
                    ),
                    child: Text(
                      cell?.toString() ?? '—',
                      style: const TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 12,
                      ),
                    ),
                  ),
              ],
            ),
        ],
      ),
    );
  }
}

// ---- 键值 ---------------------------------------------------------------

class _KeyValueBody extends StatelessWidget {
  const _KeyValueBody({required this.view});

  final KeyValueView view;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [for (final e in view.entries) _KvRow(entry: e)],
    );
  }
}

class _KvRow extends StatelessWidget {
  const _KvRow({required this.entry});

  final KvEntry entry;

  @override
  Widget build(BuildContext context) {
    final v = entry.value;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 96,
            child: Text(
              entry.key,
              style: const TextStyle(color: AppColors.textMuted, fontSize: 12),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(child: _ValueView(value: v)),
        ],
      ),
    );
  }
}

class _ValueView extends StatelessWidget {
  const _ValueView({required this.value});

  final Object? value;

  @override
  Widget build(BuildContext context) {
    return switch (value) {
      null => const Text(
        '—',
        style: TextStyle(color: AppColors.textMuted, fontSize: 12),
      ),
      final JsonView j => Padding(
        padding: const EdgeInsets.only(top: 2),
        child: _JsonBlock(json: j.json),
      ),
      final KeyValueView k => Container(
        padding: const EdgeInsets.only(left: 8),
        decoration: const BoxDecoration(
          border: Border(left: BorderSide(color: AppColors.tone1)),
        ),
        child: _KeyValueBody(view: k),
      ),
      final bool b => Text(
        b ? 'true' : 'false',
        style: TextStyle(
          color: b ? AppColors.anchorGreen : AppColors.textMuted,
          fontSize: 12,
        ),
      ),
      _ => Text(
        value.toString(),
        style: const TextStyle(color: AppColors.textPrimary, fontSize: 12),
      ),
    };
  }
}

// ---- JSON（长按复制） ---------------------------------------------------

class _JsonBody extends StatelessWidget {
  const _JsonBody({required this.view});

  final JsonView view;

  @override
  Widget build(BuildContext context) => _JsonBlock(json: view.json);
}

/// 等宽 JSON 块；长按复制全文，轻触给一次 SnackBar 反馈。
class _JsonBlock extends StatelessWidget {
  const _JsonBlock({required this.json});

  final String json;

  Future<void> _copy(BuildContext context) async {
    await Clipboard.setData(ClipboardData(text: json));
    if (!context.mounted) return;
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(
      const SnackBar(content: Text('已复制结果'), duration: Duration(seconds: 1)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onLongPress: () => _copy(context),
      behavior: HitTestBehavior.opaque,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: const Color(0x0DFFFFFF),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(
          json,
          style: const TextStyle(
            color: AppColors.textPrimary,
            fontSize: 11,
            height: 1.4,
            fontFamily: 'monospace',
          ),
        ),
      ),
    );
  }
}
