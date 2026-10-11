/// 日记日时钟（M4，tech-plan §5.2 第 1 条用户硬裁定；
/// P1 起增加进程内拨钟能力，供 ECP `sys.clock.set` 同路复用）。
///
/// 日界是凌晨 **04:00**：00:00–03:59 仍属于前一天。全模块对「今天」
/// 的一切判定（标题、容器 ID、provider 日期参数、清理与补记未来禁用）
/// 只准走本时钟，禁止直接用 `DateTime.now()` 的日期。
///
/// 纯日期计算 [diaryDate] 是静态纯函数，容器 ID 等确定性逻辑可直接
/// 复用；墙上时间注入点只有构造函数一处（测试/设备时间复验）。
///
/// 拨钟（ECP）：[overrideTo] 把时钟固定到指定时刻，**只影响本实例的
/// 读时结果、不触碰系统时间**，且仅进程内存活——冷启动构造新实例即
/// 恢复真实墙钟。仓储/composer/命令共用同一实例，因此拨钟后 UI 与
/// 命令看到的「今天」一致（同路原则，不存在第二套时间）。
class DiaryClock {
  DiaryClock({DateTime Function()? now}) : _now = now ?? DateTime.now;

  /// 墙钟取时函数；被 [_override] 固定时不再调用。
  final DateTime Function() _now;

  /// 非 null 时时钟固定在该时刻（ECP `sys.clock.set --time`）。
  DateTime? _override;

  /// 当前时刻：拨钟时返回固定值，否则取墙钟。
  ///
  /// composer 的 `updatedAt` 等时间戳也应取本方法，保证拨钟后全链路
  /// 时间语义一致。
  DateTime now() => _override ?? _now();

  /// 时钟所认为的今天（归一到年月日的日记日）。
  DateTime today() => diaryDate(now());

  /// 是否处于拨钟状态（`sys.clock.set` 返回 before/after 用）。
  bool get isOverridden => _override != null;

  /// 固定时钟到 [time]（保留原时分秒，命令侧按 ISO 解析传入）。
  void overrideTo(DateTime time) {
    _override = time;
  }

  /// 恢复真实墙钟（`sys.clock.set --reset`）。
  void clearOverride() {
    _override = null;
  }

  /// 墙上时间 → 日记日：`hour < 4` 归前一自然日，否则归当日。
  ///
  /// 借 `DateTime` 归一化处理跨月/跨年（如 1 月 1 日 03:xx → 上年 12/31）。
  static DateTime diaryDate(DateTime wall) {
    final day = DateTime(wall.year, wall.month, wall.day);
    return wall.hour < 4 ? day.subtract(const Duration(days: 1)) : day;
  }
}
