import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// 应用触感反馈统一入口。
///
/// - Android：通过原生方法通道直接驱动振动马达（见 MainActivity），
///   不依赖系统「触感反馈」开关，可稳定输出轻微短震；
/// - iOS：使用系统触感生成器（UISelectionFeedbackGenerator 等），
///   系统会自动选择合适的触感强度；
/// - 其他平台：静默忽略。
abstract final class Haptics {
  static const MethodChannel _channel = MethodChannel('echo/haptics');

  /// 轻微短震：页面切换、快捷项选择等细粒度反馈。
  static Future<void> tick() {
    if (defaultTargetPlatform == TargetPlatform.android) {
      return _channel.invokeMethod('tick');
    }
    if (defaultTargetPlatform == TargetPlatform.iOS) {
      return HapticFeedback.selectionClick();
    }
    return SynchronousFuture(null);
  }

  /// 稍强确认震：长按展开搜索、快捷操作触发等。
  static Future<void> confirm() {
    if (defaultTargetPlatform == TargetPlatform.android) {
      return _channel.invokeMethod('confirm');
    }
    if (defaultTargetPlatform == TargetPlatform.iOS) {
      return HapticFeedback.mediumImpact();
    }
    return SynchronousFuture(null);
  }
}
