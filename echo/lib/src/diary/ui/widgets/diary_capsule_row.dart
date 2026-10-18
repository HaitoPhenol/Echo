import 'package:flutter/material.dart';

import '../../../theme/app_colors.dart';
import '../../editor/block_editor_controller.dart';
import 'diary_mood_picker.dart';

/// 日页标题下方的胶囊行（2026-10-18 模板重设）。
///
/// 承载自动生成的数据与心情：温度 → 湿度 → 天气 → 日程 → 心情。
/// 胶囊**不是块**、不进 `.sy` 块列表，但属于笔记内容——数值全部读自
/// 文档根 `custom-*` 属性（`SySerializer` 导出时天然携带）。
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

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final custom = controller.documentCustom;
        final dataTap = (onRefreshData != null && !refreshing)
            ? onRefreshData
            : null;

        return Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Wrap(
            alignment: WrapAlignment.spaceBetween,
            runSpacing: 6,
            children: [
              _Capsule(
                key: const ValueKey<String>('diary-capsule-temp'),
                leading: const _Emoji('🌡️'),
                label: _valueWithUnit(custom['custom-iot-temp'], '°C'),
                onTap: dataTap,
                dimmed: refreshing,
              ),
              _Capsule(
                key: const ValueKey<String>('diary-capsule-humidity'),
                leading: const _Emoji('💧'),
                label: _valueWithUnit(custom['custom-iot-humidity'], '%'),
                onTap: dataTap,
                dimmed: refreshing,
              ),
              _Capsule(
                key: const ValueKey<String>('diary-capsule-weather'),
                leading: const _Emoji('☁️'),
                label: _valueOrDash(custom['custom-weather']),
                onTap: dataTap,
                dimmed: refreshing,
              ),
              _Capsule(
                key: const ValueKey<String>('diary-capsule-schedule'),
                leading: const _Emoji('📅'),
                label: _valueWithUnit(custom['custom-schedule-count'], ' 条'),
                onTap: dataTap,
                dimmed: refreshing,
              ),
              _Capsule(
                key: const ValueKey<String>('diary-capsule-mood'),
                leading: _moodLeading(custom[kDiaryMoodKey]),
                label: custom[kDiaryMoodKey] == null ? '心情' : null,
                onTap: onPickMood,
              ),
            ],
          ),
        );
      },
    );
  }

  /// 缺值统一显示占位符，保持五槽恒显、行高稳定。
  static const String _dash = '—';

  /// 带单位的数值胶囊：无值或空串显示 `—`。
  static String _valueWithUnit(String? value, String unit) =>
      (value == null || value.isEmpty) ? _dash : '$value$unit';

  /// 无单位的文本胶囊：无值或空串显示 `—`。
  static String _valueOrDash(String? value) =>
      (value == null || value.isEmpty) ? _dash : value;

  /// 心情胶囊前导：已设置显示 emoji，未设置显示空心表情图标。
  static Widget _moodLeading(String? mood) => mood == null
      ? const Icon(Icons.mood_outlined, size: 12, color: AppColors.pageLabel)
      : _Emoji(mood);
}

/// 单个胶囊：导航条胶囊同款底色（tone1 + 全圆角），不透明命中区可点按。
class _Capsule extends StatelessWidget {
  const _Capsule({
    super.key,
    this.leading,
    this.label,
    this.onTap,
    this.dimmed = false,
  });

  /// 前导表情/图标；null 时只有文字。
  final Widget? leading;

  /// 文字；null 时只有前导（心情已设置时仅显示 emoji）。
  final String? label;

  final VoidCallback? onTap;

  /// 取数中降透明度（仅数据胶囊使用）。
  final bool dimmed;

  @override
  Widget build(BuildContext context) {
    final children = <Widget>[
      if (leading != null) ...[leading!, const SizedBox(width: 4)],
      if (label != null)
        Text(
          label!,
          style: const TextStyle(fontSize: 11, color: AppColors.pageLabel),
        ),
    ];

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Opacity(
        opacity: dimmed ? 0.45 : 1,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: BoxDecoration(
            color: AppColors.tone1,
            borderRadius: BorderRadius.circular(999),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: children),
        ),
      ),
    );
  }
}

/// 胶囊前导 emoji：字号随胶囊文字（11）略大一号，保证表情可辨。
class _Emoji extends StatelessWidget {
  const _Emoji(this.glyph);

  final String glyph;

  @override
  Widget build(BuildContext context) =>
      Text(glyph, style: const TextStyle(fontSize: 12));
}
