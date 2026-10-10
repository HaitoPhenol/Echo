/// 日记日时钟（M4，tech-plan §5.2 第 1 条用户硬裁定）。
///
/// 日界是凌晨 **04:00**：00:00–03:59 仍属于前一天。全模块对「今天」
/// 的一切判定（标题、容器 ID、provider 日期参数、清理与补记未来禁用）
/// 只准走本时钟，禁止直接用 `DateTime.now()` 的日期。
///
/// 纯日期计算 [diaryDate] 是静态纯函数，容器 ID 等确定性逻辑可直接
/// 复用；墙上时间注入点只有构造函数一处（测试/设备时间复验）。
class DiaryClock {
  DiaryClock({DateTime Function()? now}) : _now = now ?? DateTime.now;

  final DateTime Function() _now;

  /// 时钟所认为的今天（归一到年月日的日记日）。
  DateTime today() => diaryDate(_now());

  /// 墙上时间 → 日记日：`hour < 4` 归前一自然日，否则归当日。
  ///
  /// 借 `DateTime` 归一化处理跨月/跨年（如 1 月 1 日 03:xx → 上年 12/31）。
  static DateTime diaryDate(DateTime wall) {
    final day = DateTime(wall.year, wall.month, wall.day);
    return wall.hour < 4 ? day.subtract(const Duration(days: 1)) : day;
  }
}
