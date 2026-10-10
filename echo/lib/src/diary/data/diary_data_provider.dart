/// 家居环境快照（温湿度）。
typedef HomeEnvironment = ({double tempC, int humidityPct});

/// 日记自动记录的数据提供方（tech-plan §5、§5.1 第 1 条）。
///
/// 所有方法以**日记日**（04:00 日界后的归一日期）为参数：M4 假实现
/// 忽略日期返回常量；真实 IoT/日程/天气源就绪后只换实现、按日期判空。
/// 单源失败/无数据返回 null，composer 逐源容错，互不连坐。
///
/// [isSampleData] 为 true 时（M4 假实现）快照行追加「（示例数据）」
/// 标注；真实源实现返回 false，标注自动消失。
abstract interface class DiaryDataProvider {
  /// 室温/湿度（custom-iot-temp、custom-iot-humidity）。
  Future<HomeEnvironment?> fetchHomeEnvironment(DateTime diaryDate);

  /// 当天日程条数（custom-schedule-count）。
  Future<int?> fetchScheduleCount(DateTime diaryDate);

  /// 天气一句话文案（custom-weather）。
  Future<String?> fetchWeather(DateTime diaryDate);

  /// 当前提供的是否为假数据（决定快照行示例标注）。
  bool get isSampleData;
}

/// M4 假实现：21°C / 45% / 3 条日程 / 多云。
///
/// 可注入固定结果或抛异常（测 composer 容错）；[throwOnCall] 非空时
/// 三个源统一抛该异常。
class FakeDiaryDataProvider implements DiaryDataProvider {
  FakeDiaryDataProvider({
    this.homeEnvironment = const (tempC: 21, humidityPct: 45),
    this.scheduleCount = 3,
    this.weather = '多云',
    this.throwOnCall,
    this.delay = Duration.zero,
  });

  final HomeEnvironment? homeEnvironment;
  final int? scheduleCount;
  final String? weather;
  final Object? throwOnCall;
  final Duration delay;

  @override
  bool get isSampleData => true;

  Future<void> _simulate() async {
    if (delay > Duration.zero) await Future<void>.delayed(delay);
    final error = throwOnCall;
    if (error != null) throw error;
  }

  @override
  Future<HomeEnvironment?> fetchHomeEnvironment(DateTime diaryDate) async {
    await _simulate();
    return homeEnvironment;
  }

  @override
  Future<int?> fetchScheduleCount(DateTime diaryDate) async {
    await _simulate();
    return scheduleCount;
  }

  @override
  Future<String?> fetchWeather(DateTime diaryDate) async {
    await _simulate();
    return weather;
  }
}
