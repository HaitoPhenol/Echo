import 'package:flutter/material.dart';

import '../../../theme/app_colors.dart';
import '../../editor/block_editor_controller.dart';

/// 心情在文档 custom 中的键；序列化后即思源文档属性 custom-mood。
const String kDiaryMoodKey = 'custom-mood';

/// 五档固定离散心情（顺序：由正向到负向）。
///
/// 固定取值保证思源属性视图可按 custom-mood 聚合成图；
/// M5 不做自由文本 / 评分 / sleep / 统计。
const List<String> kDiaryMoodValues = ['😄', '🙂', '😐', '😕', '😢'];

/// 心情选择结果：[mood] 为选中的 emoji，null 表示清除心情。
///
/// 与「未选择（弹窗取消）」区分：取消时 [showDiaryMoodPicker]
/// 直接返回 null（即 [DiaryMoodSelection]? 为 null）。
class DiaryMoodSelection {
  const DiaryMoodSelection(this.mood);

  final String? mood;
}

/// 编辑页标题栏的心情入口。
///
/// 已设置时显示当前 emoji；未设置时显示空心表情图标 + 极小字「心情」。
/// 随控制器重建（选择后立刻刷新）；文档锁定（导出只读）时只展示
/// 当前值、不可点按。
class DiaryMoodChip extends StatelessWidget {
  const DiaryMoodChip({super.key, required this.controller, this.onPick});

  final BlockEditorController controller;

  /// 点按回调（编辑页注入：弹 sheet、写控制器、触发落盘）；
  /// 为 null 或文档锁定时 chip 不可交互。
  final VoidCallback? onPick;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final mood = controller.documentCustom[kDiaryMoodKey];
        final enabled = onPick != null && !controller.locked;
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: enabled ? onPick : null,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
            child: mood != null
                ? Text(mood, style: const TextStyle(fontSize: 16))
                : Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.mood_outlined,
                        size: 15,
                        color: enabled
                            ? AppColors.pageLabel
                            : AppColors.mechInkDim,
                      ),
                      const SizedBox(width: 3),
                      Text(
                        '心情',
                        style: TextStyle(
                          fontSize: 10,
                          letterSpacing: 1.2,
                          color: enabled
                              ? AppColors.pageLabel
                              : AppColors.mechInkDim,
                        ),
                      ),
                    ],
                  ),
          ),
        );
      },
    );
  }
}

/// 弹出五档心情 bottom sheet。
///
/// 返回 [DiaryMoodSelection]（选中或清除）；弹窗被取消 / 点遮罩
/// 关闭时返回 null。
Future<DiaryMoodSelection?> showDiaryMoodPicker(
  BuildContext context, {
  String? current,
}) {
  return showModalBottomSheet<DiaryMoodSelection>(
    context: context,
    backgroundColor: AppColors.overlaySurface,
    barrierColor: Colors.black54,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
    ),
    builder: (context) => _DiaryMoodSheet(current: current),
  );
}

class _DiaryMoodSheet extends StatelessWidget {
  const _DiaryMoodSheet({required this.current});

  final String? current;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 36,
                height: 3,
                decoration: BoxDecoration(
                  color: AppColors.tone2,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 14),
            const Text(
              '今天心情',
              style: TextStyle(
                fontSize: 12,
                letterSpacing: 2,
                color: AppColors.pageLabel,
              ),
            ),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                for (final mood in kDiaryMoodValues)
                  _MoodOption(
                    mood: mood,
                    selected: mood == current,
                    onTap: () =>
                        Navigator.of(context).pop(DiaryMoodSelection(mood)),
                  ),
              ],
            ),
            const SizedBox(height: 6),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: current == null
                    ? null
                    : () =>
                          Navigator.of(context)
                              .pop(const DiaryMoodSelection(null)),
                icon: const Icon(Icons.close, size: 15),
                label: const Text('清除心情'),
                style: TextButton.styleFrom(
                  foregroundColor: AppColors.textMuted,
                  disabledForegroundColor: AppColors.mechInkDim,
                  textStyle: const TextStyle(fontSize: 12, letterSpacing: 1),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 单个表情档：圆环选中态，横向均布。
class _MoodOption extends StatelessWidget {
  const _MoodOption({
    required this.mood,
    required this.selected,
    required this.onTap,
  });

  final String mood;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        width: 52,
        height: 52,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: selected ? AppColors.tone2 : Colors.transparent,
          shape: BoxShape.circle,
          border: Border.all(
            color: selected ? AppColors.tone3 : AppColors.tone1,
          ),
        ),
        child: Text(mood, style: const TextStyle(fontSize: 22)),
      ),
    );
  }
}
