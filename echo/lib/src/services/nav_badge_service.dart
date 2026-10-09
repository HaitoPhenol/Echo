import 'package:flutter/material.dart';

/// 导航锚点状态：页面需要用户注意的程度。
enum NavBadgeLevel {
  /// 正常：锚点白色、静止。
  normal,

  /// 通知：绿色呼吸闪烁（如聊天新消息）；页面被查看后恢复。
  notification,

  /// 异常：红色闪烁（如某模块发生异常）；必须显式处理完成才会恢复。
  exception,
}

/// 导航锚点状态服务：各模块向导航线上报「需要用户注意」的统一接口。
///
/// 这是预留的通知接口：消息等任何模块只依赖本类上报状态
/// （[postNotification] / [reportException]），导航条锚点自动响应，
/// UI 不关心状态由谁产生、何时清除。继承 [ChangeNotifier]，
/// 通过 [NavBadgeScope] 向子树提供实例并驱动刷新。
abstract class NavBadgeService extends ChangeNotifier {
  /// 第 [page] 页当前的锚点状态。
  NavBadgeLevel levelOf(int page);

  /// 上报一条通知（锚点变绿、呼吸闪烁）。
  void postNotification(int page);

  /// 上报一个异常（锚点变红、闪烁）。
  void reportException(int page);

  /// 页面被查看：通知态视为已读、恢复正常；异常态不受影响。
  void markViewed(int page);

  /// 异常处理完成：恢复正常。
  void resolveException(int page);
}

/// 内存实现：状态仅保存在进程内，重启清空（开发阶段使用）。
///
/// 后续接入真实模块时，各业务模块直接调用本实例的方法即可；
/// 如需跨重启保留，另写一个 [NavBadgeService] 实现替换。
class InMemoryNavBadgeService extends NavBadgeService {
  InMemoryNavBadgeService({required int pageCount})
    : _levels = List<NavBadgeLevel>.filled(pageCount, NavBadgeLevel.normal);

  final List<NavBadgeLevel> _levels;

  @override
  NavBadgeLevel levelOf(int page) => _levels[page];

  @override
  void postNotification(int page) => _set(page, NavBadgeLevel.notification);

  @override
  void reportException(int page) => _set(page, NavBadgeLevel.exception);

  @override
  void markViewed(int page) {
    // 仅通知态会被「查看」清除；异常必须显式处理完成。
    if (_levels[page] == NavBadgeLevel.notification) {
      _set(page, NavBadgeLevel.normal);
    }
  }

  @override
  void resolveException(int page) {
    if (_levels[page] == NavBadgeLevel.exception) {
      _set(page, NavBadgeLevel.normal);
    }
  }

  void _set(int page, NavBadgeLevel level) {
    if (_levels[page] == level) return;
    _levels[page] = level;
    notifyListeners();
  }
}

/// 向子树提供 [NavBadgeService]。
///
/// 基于 [InheritedNotifier]：服务状态变化时，依赖过本 scope 的
/// 组件自动重建，无需各组件手动监听。
class NavBadgeScope extends InheritedNotifier<NavBadgeService> {
  const NavBadgeScope({
    super.key,
    required NavBadgeService service,
    required super.child,
  }) : super(notifier: service);

  /// 取锚点服务（导航子树内必定可用，缺失即说明装配错误）。
  static NavBadgeService of(BuildContext context) {
    final service = maybeOf(context);
    assert(service != null, '子树中缺少 NavBadgeScope');
    return service!;
  }

  /// 取锚点服务；scope 之外返回 null。
  static NavBadgeService? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<NavBadgeScope>()?.notifier;
}
