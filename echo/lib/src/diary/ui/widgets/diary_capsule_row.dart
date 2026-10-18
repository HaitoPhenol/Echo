import 'package:flutter/material.dart';

import '../../../theme/app_colors.dart';
import '../../editor/block_editor_controller.dart';
import '../../editor/diary_capsule_chip.dart';
import '../../sy/diary_capsule_items.dart';

/// 日页标题下方的胶囊行（2026-10-18 模板重设）。
///
/// 承载自动生成的数据与心情：温度 → 湿度 → 天气 → 日程 → 心情。
/// 胶囊**不是块**、不进 `.sy` 块列表，但属于笔记内容——数值全部读自
/// 文档根 `custom-*` 属性（`SySerializer` 导出时天然携带）。
///
/// 数据面与展示口径由 `sy/diary_capsule_items.dart` 收口（与导出编码共用）；
/// 外观基元复用 `editor/diary_capsule_chip.dart` 的 [DiaryCapsuleChip]。
///
/// 挂在滚动区首项（`BlockEditorView.header`），随正文滚动；不使用
/// 横向滚动，一行放不下由 [Wrap] 自动换行，行内 `WrapAlignment.spaceBetween`
/// 做首尾贴边、间距均分的分散对齐。
class DiaryCapsuleRow extends StatelessWidget {
  const DiaryCapsuleRow({
    super.key,
    required this.controller,
    this.onRefreshData,
    this.onPickMood,
    this.refreshing = false,
  });

  final BlockEditorController controller;

  /// 点按任一数据胶囊（温度/湿度/天气/日程）触发；null 或文档锁定
  /// （已导出只读）时数据胶囊不可点。
  final VoidCallback? onRefreshData;

  /// 点按心情胶囊触发（弹五档 sheet）；null 或文档锁定时不可点。
  final VoidCallback? onPickMood;

  /// 取数中：数据胶囊降透明度且不响应点按（心情胶囊不受影响）。
  final bool refreshing;

  /// 缺值统一显示占位符，保持五槽恒显、行高稳定。
  static const String _dash = '—';

  /// 槽位键 → 稳定 ValueKey 串（渲染对象身份，供测试与动画锚定）。
  static const Map<String, String> _valueKeys = {
    kCapsuleTempKey: 'diary-capsule-temp',
    kCapsuleHumidityKey: 'diary-capsule-humidity',
    kCapsuleWeatherKey: 'diary-capsule-weather',
    kCapsuleScheduleKey: 'diary-capsule-schedule',
    kCapsuleMoodKey: 'diary-capsule-mood',
  };

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final items = buildDiaryCapsuleItems(controller.documentCustom);
        final dataTap = (onRefreshData != null && !refreshing)
            ? onRefreshData
            : null;

        return Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Wrap(
            alignment: WrapAlignment.spaceBetween,
            runSpacing: 6,
            children: [
              for (final item in items)
                if (item.key == kCapsuleMoodKey)
                  DiaryCapsuleChip(
                    key: ValueKey<String>(_valueKeys[item.key]!),
                    leading: _moodLeading(item.label),
                    // 未设心情显示占位文字「心情」，已设置仅显 emoji。
                    label: item.label == null ? '心情' : null,
                    onTap: onPickMood,
                  )
                else
                  DiaryCapsuleChip(
                    key: ValueKey<String>(_valueKeys[item.key]!),
                    leading: DiaryCapsuleEmoji(item.emoji),
                    label: item.label ?? _dash,
                    onTap: dataTap,
                    dimmed: refreshing,
                  ),
            ],
          ),
        );
      },
    );
  }

  /// 心情胶囊前导：已设置显示 emoji，未设置显示空心表情图标。
  static Widget _moodLeading(String? mood) => mood == null
      ? const Icon(Icons.mood_outlined, size: 12, color: AppColors.pageLabel)
      : DiaryCapsuleEmoji(mood);
}
