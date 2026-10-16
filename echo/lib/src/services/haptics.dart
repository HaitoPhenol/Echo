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

  /// 触感是非关键能力：通道异常（插件未就绪、马达不可用等）静默降级
  /// （规范 1.11），不得打断交互主流程；调用方均为 fire-and-forget，
  /// 若不在此收口会成为未捕获异步错误。
  static Future<void> _invoke(String method) {
    return _channel.invokeMethod<void>(method).catchError((Object _) {});
  }

  /// 轻微短震：页面切换、快捷项选择等细粒度反馈。
  static Future<void> tick() {
    if (defaultTargetPlatform == TargetPlatform.android) {
      return _invoke('tick');
    }
    if (defaultTargetPlatform == TargetPlatform.iOS) {
      return HapticFeedback.selectionClick();
    }
    return SynchronousFuture(null);
  }

  /// 稍强确认震：长按展开搜索、快捷操作触发等。
  static Future<void> confirm() {
    if (defaultTargetPlatform == TargetPlatform.android) {
      return _invoke('confirm');
    }
    if (defaultTargetPlatform == TargetPlatform.iOS) {
      return HapticFeedback.mediumImpact();
    }
    return SynchronousFuture(null);
  }
}
