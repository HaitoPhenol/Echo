import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// 机能风读数条的一次设备快照（`echo/device_stats` 通道子集）。
///
/// 只保留读数条与 `console.*` 命令关心的三个字段；版本/构建号等
/// sys.info 字段由通道原始 map 承载，不进本值对象。
@immutable
class ConsoleStatsSnapshot {
  const ConsoleStatsSnapshot({this.model = '—', this.tempC, this.powerW});

  /// 未知/降级时型号显「—」；数值为 null 时视图层同样显「—」。
  static const ConsoleStatsSnapshot empty = ConsoleStatsSnapshot();

  final String model;
  final num? tempC;
  final num? powerW;

  Map<String, Object?> toJson() => {
    'model': model,
    'tempC': tempC,
    'powerW': powerW,
  };

  @override
  bool operator ==(Object other) =>
      other is ConsoleStatsSnapshot &&
      other.model == model &&
      other.tempC == tempC &&
      other.powerW == powerW;

  @override
  int get hashCode => Object.hash(model, tempC, powerW);
}

/// 设备读数读取函数：返回通道原始 map（含 sys.info 需要的全部字段），
/// 失败由实现吞掉平台异常并返回空 map。
typedef ConsoleStatsReader = Future<Map<String, Object?>> Function();

/// 机能风读数条的唯一读数收口（设计 §9.3 ConsoleRefreshTrigger）。
///
/// 提升前 channel 与 5s 定时器埋在 [MechanicalCoordsBar] 的 State 里，
/// sys.info 又另有一份直读；提升后三处同源：
/// - UI（读数条）消费本服务的 [snapshot]，notify 即重建；
/// - 5s 定时轮询与 `console.refresh` 命令都只调 [refresh]；
/// - `sys.info` 经 [readRaw] 取通道原始字段（版本/构建号等）。
///
/// 通道异常/测试环境无插件时保持上一次快照（首次失败即全「—」），
/// 与提升前的降级行为一致。
class ConsoleStatsService extends ChangeNotifier {
  ConsoleStatsService({
    ConsoleStatsReader? reader,
    this.pollInterval = const Duration(seconds: 5),
    bool autoStart = true,
  }) : _reader = reader ?? _defaultReader {
    if (autoStart) start();
  }

  /// 轮询周期：状态量变化慢，5 秒足够且几乎零开销。
  final Duration pollInterval;
  final ConsoleStatsReader _reader;

  Timer? _timer;
  Future<ConsoleStatsSnapshot>? _inFlight;
  ConsoleStatsSnapshot _snapshot = ConsoleStatsSnapshot.empty;

  /// 最近一次读数（视图层与 console.snapshot 命令共用）。
  ConsoleStatsSnapshot get snapshot => _snapshot;

  /// 立即拉取一次通道原始 map（sys.info 同源入口；吞平台异常）。
  Future<Map<String, Object?>> readRaw() => _reader();

  /// 启动定时轮询并立即刷新一次；重复调用不叠加定时器。
  void start() {
    _timer ??= Timer.periodic(pollInterval, (_) => refresh());
    refresh();
  }

  /// 停止轮询（测试/dispose 用）。
  void stop() {
    _timer?.cancel();
    _timer = null;
  }

  /// 立即刷新读数；手动触发与定时器同一路径。并发调用共享同一个
  /// in-flight Future，不重复打通道。
  Future<ConsoleStatsSnapshot> refresh() {
    return _inFlight ??= _doRefresh();
  }

  Future<ConsoleStatsSnapshot> _doRefresh() async {
    try {
      final raw = await _reader();
      final next = ConsoleStatsSnapshot(
        model: (raw['model'] as String?)?.isNotEmpty == true
            ? raw['model'] as String
            : '—',
        tempC: raw['tempC'] as num?,
        powerW: raw['powerW'] as num?,
      );
      if (next != _snapshot) {
        _snapshot = next;
        notifyListeners();
      }
    } finally {
      _inFlight = null;
    }
    return _snapshot;
  }

  @override
  void dispose() {
    stop();
    super.dispose();
  }

  /// 生产读取：绑定 `echo/device_stats`（MainActivity.readDeviceStats，
  /// 零三方库零权限）；插件缺失/平台异常一律空 map 降级。
  static Future<Map<String, Object?>> _defaultReader() async {
    try {
      final raw = await const MethodChannel('echo/device_stats')
          .invokeMapMethod<String, dynamic>('snapshot');
      return raw?.cast<String, Object?>() ?? const {};
    } on PlatformException {
      return const {};
    } on MissingPluginException {
      return const {};
    }
  }
}
