import 'dart:io';

import 'protocol/command_spec.dart';
import 'protocol/control_error.dart';

/// App 沙盒目录的控制面视图（由 bootstrap / 日记 bootstrap 装配）。
///
/// 路径不属于任何业务服务（仓储是抽象的，内存实现没有文件根），故
/// 单独持有；命令层（如 `diary.export` 的落盘目录）按类型取用。
class ControlPaths {
  ControlPaths({this.diaryRoot, this.controlRoot});

  /// `<应用文档>/echo_diary`（DiaryPage 开库成功后回填）。
  Directory? diaryRoot;

  /// `<应用文档>/echo_control`（PIN 记录 pin.json 所在目录）。
  Directory? controlRoot;

  /// 导出 zip 暂存目录 `<diaryRoot>/exports`；diaryRoot 未就绪时调用方
  /// 应通过 `requireService<ControlPaths>` 的冲突错误兜底。
  Directory get diaryExports =>
      Directory('${diaryRoot!.path}${Platform.pathSeparator}exports');
}

/// ECP 服务注册表：各业务模块在自己的 bootstrap 完成后把**与 UI
/// 同源的实例**注册进来，命令适配器按类型取用。
///
/// 为什么不用 InheritedWidget/Scope：命令的调用方（adb 广播接收器、
/// 未来 MCP）在 widget 树之外，控制面是 App 级对象图；注册表只存放
/// 引用，不持有任何业务状态。典型装配：
/// - `SmartNavScreen.initState` 注册 `NavPhysicsController`；
/// - `DiaryPage` 开库成功后注册 clock/repository/composer/exportService；
/// - `ControlBootstrap` 注册 App 生命周期状态与设备快照。
///
/// 生命周期与各业务模块自身一致（导航屏常驻、日记页常驻），注册表
/// 不负责 dispose。
class ControlRegistry implements ControlServices {
  final Map<Type, Object> _services = {};

  /// 注册（或替换）一个同类型服务实例。
  void set<T extends Object>(T service) {
    _services[T] = service;
  }

  /// 移除注册（模块确实销毁时；当前两个注册方都常驻，预留）。
  void unset<T extends Object>() {
    _services.remove(T);
  }

  @override
  T? get<T extends Object>() => _services[T] as T?;

  @override
  T require<T extends Object>(String what) {
    final service = get<T>();
    if (service == null) {
      // NOT_READY 归 CONFLICT 退出码族（4）：模块尚未完成 bootstrap，
      // 调用方稍等重试即可，不是命令本身写错。
      throw ControlException(
        ControlErrorCode.conflict,
        '$what 尚未就绪，请先进入对应页面或稍后重试',
      );
    }
    return service;
  }
}
