import 'package:flutter/material.dart';

import '../../navigation/dock_geometry.dart';
import '../../theme/app_colors.dart';
import '../export/diary_export_service.dart';

/// 年/月列表共用的导出交互：范围提示、渠道弹窗、分享确认、结果文案。
///
/// 打包与状态迁移由 [DiaryExportService] 负责；本文件只收敛 UI 口径，
/// 避免年、月两个列表页各写一份弹窗与文案。

/// 导出渠道选择弹窗：顶部固定显示当前导出范围（如「2026 年」或
/// 「2026 年 10 月」），下方为分享 / 另存两个入口。
///
/// 点遮罩 / 返回键关闭返回 null，调用方据此不触发导出。
///
/// 弹窗挂在日记内层 Navigator 的 Overlay 上，层级低于主屏底部停靠件
/// （把手条 / AI 条 / 导航胶囊），三者不会让位、会直接盖住弹窗底边。
/// 因此底部按 [DockGeometry] 额外留出「停靠件 + 间隙」的高度，
/// 让分享 / 另存两个选项整体落在导航栏之上，不被遮挡。
Future<DiaryExportChannel?> showDiaryExportChannelSheet(
  BuildContext context, {
  required String scopeLabel,
}) {
  // 停靠件上沿 = 安全区 + bottomMargin + barHeight；再留 12dp 间隙，
  // 与 AI 对话框收在导航条上方的口径一致。
  const dockClearance = DockGeometry.bottomMargin + DockGeometry.barHeight + 12;
  return showModalBottomSheet<DiaryExportChannel>(
    context: context,
    backgroundColor: AppColors.overlaySurface,
    barrierColor: Colors.black54,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
    ),
    builder: (sheetContext) => SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.only(bottom: dockClearance),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '导出范围：$scopeLabel',
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: AppColors.pageLabel,
                    ),
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    '范围内全部日记都会完整打包（含已导出）',
                    style: TextStyle(fontSize: 11, color: AppColors.mechInkDim),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            ListTile(
              leading: const Icon(Icons.ios_share, size: 20),
              title: const Text('分享'),
              subtitle: const Text('发送到思源或其他应用'),
              onTap: () =>
                  Navigator.of(sheetContext).pop(DiaryExportChannel.share),
            ),
            ListTile(
              leading: const Icon(Icons.save_alt, size: 20),
              title: const Text('另存'),
              subtitle: const Text('保存到本机选定的位置'),
              onTap: () =>
                  Navigator.of(sheetContext).pop(DiaryExportChannel.save),
            ),
          ],
        ),
      ),
    ),
  );
}

/// 系统分享返回后的人工确认（share_plus 不回报真实发送结果）。
/// 点「尚未发送」/ 点弹窗外关闭 → false，草稿不迁移。
Future<bool> confirmDiaryShareSent(BuildContext context) async {
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

/// 导出结果文案：范围 + 渠道 + 入包篇数；有今日草稿 / 已导出内容时
/// 说明它们不会被迁移。
String diaryExportResultText(DiaryExportOutcome outcome) {
  final scope = outcome.scopeLabel;
  if (!outcome.didExport) {
    if (!outcome.userDenied) return '$scope没有可导出的日记';
    return outcome.channel == DiaryExportChannel.save
        ? '已取消另存，$scope日记仍保留'
        : '未标记为已导出，$scope草稿仍保留';
  }

  final verb = outcome.channel == DiaryExportChannel.save ? '已另存' : '已分享';
  final parts = <String>['$verb $scope ${outcome.exportedCount} 篇'];
  if (outcome.markedCount > 0) {
    parts.add('标记 ${outcome.markedCount} 篇为已导出');
  }
  if (outcome.todayKeptCount > 0) {
    parts.add('今日 ${outcome.todayKeptCount} 篇保持草稿');
  }
  if (outcome.markedCount == 0 && outcome.todayKeptCount == 0) {
    parts.add('均为已导出内容');
  }
  return parts.join(' · ');
}

/// 年/月行尾部导出按钮：空闲显分享图标，进行中转圈。
///
/// 裸图标 + 手势而非 IconButton：列表行统一 28px 中线，
/// IconButton 最小点击高度会撑高行（见 diary_shell.dart 头部注释）。
class DiaryExportIconButton extends StatelessWidget {
  const DiaryExportIconButton({
    super.key,
    required this.tooltip,
    required this.exporting,
    required this.enabled,
    required this.onPressed,
  });

  final String tooltip;
  final bool exporting;
  final bool enabled;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final color = enabled
        ? AppColors.pageLabel
        : AppColors.mechInkDim.withValues(alpha: 0.45);
    return Tooltip(
      message: tooltip,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: enabled && !exporting ? onPressed : null,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6),
          child: exporting
              ? SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: color,
                  ),
                )
              : Icon(Icons.ios_share, size: 17, color: color),
        ),
      ),
    );
  }
}
