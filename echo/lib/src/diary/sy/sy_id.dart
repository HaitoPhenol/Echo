import 'dart:math';

/// 思源块 ID 生成器。
///
/// 金标准（思源 3.8.6，见 docs/diary/sy-format-golden-3.8.6.md §2）：
/// `YYYYMMDDHHMMSS-XXXXXXX`，14 位秒级时间戳 + `-` + 7 位 [a-z0-9]。
///
/// 年/月/日容器文档使用确定性 ID（后缀固定为 [containerSuffix]），
/// 保证同一自然日重复导出时路径幂等，规避思源对同 ID 文档
/// 重复导入覆盖行为不确定的风险。
class SyIdGenerator {
  SyIdGenerator({Random? random, DateTime Function()? now})
      : _random = random ?? Random.secure(),
        _now = now ?? DateTime.now;

  /// 22 位块 ID 校验正则。
  static final RegExp pattern = RegExp(r'^\d{14}-[a-z0-9]{7}$');

  /// 确定性容器文档的随机段（合法的 7 位小写字母数字）。
  static const String containerSuffix = 'echo000';

  static const String _alphabet = 'abcdefghijklmnopqrstuvwxyz0123456789';

  final Random _random;
  final DateTime Function() _now;
  final Set<String> _used = {};

  static String _pad(int value, int width) =>
      value.toString().padLeft(width, '0');

  /// 格式化为 14 位秒级时间戳 `YYYYMMDDHHMMSS`。
  static String timestamp(DateTime t) =>
      '${_pad(t.year, 4)}${_pad(t.month, 2)}${_pad(t.day, 2)}'
      '${_pad(t.hour, 2)}${_pad(t.minute, 2)}${_pad(t.second, 2)}';

  /// 生成一个新的普通块 ID，同秒批量生成时进程内去重。
  String next() {
    for (;;) {
      final buffer = StringBuffer('${timestamp(_now())}-');
      for (var i = 0; i < 7; i++) {
        buffer.write(_alphabet[_random.nextInt(_alphabet.length)]);
      }
      final id = buffer.toString();
      if (_used.add(id)) return id;
    }
  }

  /// 年容器文档 ID：`{yyyy}0101000000-echo000`。
  static String yearContainer(int year) =>
      '${_pad(year, 4)}0101000000-$containerSuffix';

  /// 月容器文档 ID：`{yyyyMM}01000000-echo000`。
  static String monthContainer(DateTime date) =>
      '${_pad(date.year, 4)}${_pad(date.month, 2)}01000000-$containerSuffix';

  /// 日文档 ID：`{yyyyMMdd}080000-echo000`（晨间 08:00 占位，ID 即日期）。
  static String dayContainer(DateTime date) =>
      '${_pad(date.year, 4)}${_pad(date.month, 2)}${_pad(date.day, 2)}'
      '080000-$containerSuffix';

  /// 校验 ID 是否符合 22 位思源规范。
  static bool isValid(String id) => pattern.hasMatch(id);
}
