/// 日页胶囊行的五个固定槽位数据面（纯 Dart，UI 与导出编码共用）。
///
/// 胶囊**不是块**、不进 `.sy` 块列表，数值全写在文档根 `custom-*` 属性里；
/// 本文件收口键名与展示口径，避免 UI（胶囊行）与导出（首行 col 超级块）
/// 两处各自硬编码字符串而漂移。
///
/// 槽位顺序固定：温度 → 湿度 → 天气 → 日程 → 心情。
library;

/// 文档根 `custom-*` 键名（导出后即思源文档属性名）。
const String kCapsuleTempKey = 'custom-iot-temp';
const String kCapsuleHumidityKey = 'custom-iot-humidity';
const String kCapsuleWeatherKey = 'custom-weather';
const String kCapsuleScheduleKey = 'custom-schedule-count';

/// 心情键（与 `diary_mood_picker.dart` 的 `kDiaryMoodKey` 同值）。
const String kCapsuleMoodKey = 'custom-mood';

/// 单个胶囊槽位的展示数据。
class DiaryCapsuleItem {
  const DiaryCapsuleItem({
    required this.key,
    required this.emoji,
    required this.label,
    this.exportText,
  });

  /// 文档根 custom 中的键名（UI 与导出共同定位该槽位）。
  final String key;

  /// 前导表情；心情未设置时 UI 以图标替代（导出该槽位不输出）。
  final String emoji;

  /// App 内所示值（含单位）；null 表示该源本次无值（UI 显示占位 `—`）。
  final String? label;

  /// 导出用整串文本（emoji + 值）；null 表示该槽位本次无值，
  /// 不写入导出的水平超级块。
  final String? exportText;

  /// 该槽位本次是否有值（导出判据）。
  bool get hasValue => exportText != null;
}

/// 由文档根 `custom-*` 构造五个固定槽位（缺值槽位 `label`/`exportText` 为 null）。
///
/// 导出文本与参考样本保持一致（`🌡️21°C` / `💧45%` / `☁️ 多云` / `📅3 条`
/// / 心情 emoji）；温度单位沿用 App 显示口径 `°C`。
List<DiaryCapsuleItem> buildDiaryCapsuleItems(Map<String, String> custom) {
  String? value(String key) {
    final raw = custom[key];
    if (raw == null || raw.trim().isEmpty) return null;
    return raw;
  }

  String? withUnit(String key, String unit) {
    final raw = value(key);
    return raw == null ? null : '$raw$unit';
  }

  final temp = withUnit(kCapsuleTempKey, '°C');
  final humidity = withUnit(kCapsuleHumidityKey, '%');
  final weather = value(kCapsuleWeatherKey);
  final schedule = withUnit(kCapsuleScheduleKey, ' 条');
  final mood = value(kCapsuleMoodKey);

  return [
    DiaryCapsuleItem(
      key: kCapsuleTempKey,
      emoji: '🌡️',
      label: temp,
      exportText: temp == null ? null : '🌡️$temp',
    ),
    DiaryCapsuleItem(
      key: kCapsuleHumidityKey,
      emoji: '💧',
      label: humidity,
      exportText: humidity == null ? null : '💧$humidity',
    ),
    DiaryCapsuleItem(
      key: kCapsuleWeatherKey,
      emoji: '☁️',
      label: weather,
      // 天气短语与 emoji 之间留一个空格（参考样本 `☁️ 多云`）。
      exportText: weather == null ? null : '☁️ $weather',
    ),
    DiaryCapsuleItem(
      key: kCapsuleScheduleKey,
      emoji: '📅',
      label: schedule,
      exportText: schedule == null ? null : '📅$schedule',
    ),
    DiaryCapsuleItem(
      key: kCapsuleMoodKey,
      // 未设置心情时给导出兜底表情（该槽位无 exportText，导出不输出）。
      emoji: mood ?? '☺️',
      label: mood,
      exportText: mood,
    ),
  ];
}
