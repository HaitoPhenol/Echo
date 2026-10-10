import 'package:flutter/material.dart';

/// 日记层级右侧滑入 + 淡入路由（240ms）。
///
/// 刻意**不**用 CupertinoPageRoute：它的全屏边缘返回手势会和外层
/// 导航页横向切换冲突。本路由不挂边缘手势，返回靠标题区按钮与
/// 系统返回键（DiaryPage 的 PopScope 统一收口到嵌套 Navigator）。
///
/// [opaque] 必须为 true：push 完成后下层路由会被 Overlay 移出
/// 绘制（Offstage 保活）。若为 false，Flutter 在转场结束后会把
/// secondaryAnimation 复位为 dismissed，半透明页会永久透出下层
/// 年/月列表（实测叠影）。机械网格纹理画在内层 Navigator 之外，
/// opaque 不影响它透上来；转场期下层页仍随 secondary 左移。
class DiarySlideRoute<T> extends PageRouteBuilder<T> {
  DiarySlideRoute({required WidgetBuilder builder, super.settings})
    : super(
        transitionDuration: const Duration(milliseconds: 240),
        reverseTransitionDuration: const Duration(milliseconds: 240),
        opaque: true,
        barrierDismissible: false,
        pageBuilder: (context, animation, secondaryAnimation) =>
            builder(context),
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          final primary = CurvedAnimation(
            parent: animation,
            curve: Curves.easeOutCubic,
            reverseCurve: Curves.easeInCubic,
          );
          final secondary = CurvedAnimation(
            parent: secondaryAnimation,
            curve: Curves.easeOutCubic,
            reverseCurve: Curves.easeInCubic,
          );
          // 新页入场：右 6% 滑入 + 淡入。
          return FadeTransition(
            opacity: primary,
            child: SlideTransition(
              position: Tween<Offset>(
                begin: const Offset(0.06, 0),
                end: Offset.zero,
              ).animate(primary),
              // 下层页转场期同步左移（结束即被 Overlay 移除绘制）。
              child: SlideTransition(
                position: Tween<Offset>(
                  begin: Offset.zero,
                  end: const Offset(-0.06, 0),
                ).animate(secondary),
                child: child,
              ),
            ),
          );
        },
      );
}
