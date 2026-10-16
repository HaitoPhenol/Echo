import 'package:flutter/material.dart';

/// 一次手势生命周期的记录。
class DragGesture {
  DragGesture({
    required this.pointer,
    required this.x0,
    required this.y0,
    required this.doubleTap,
  });

  /// 指针 id（多指情况下区分）。
  final int pointer;

  /// 按下位置
  final double x0;
  final double y0;

  /// 本次按下是否构成双击的第二击。
  final bool doubleTap;

  /// 是否已完成方向锁定。
  bool moved = false;

  /// 是否为竖直上甩（快捷弧）手势。
  bool isQuick = false;
}

/// 把手条上的一次手势：方向锁定后要么横拖抽屉，要么因竖直占优
/// 进入死区；都不是则松手按点按处理（开竖单 / 关抽屉）。
class HandleGesture {
  HandleGesture({
    required this.pointer,
    required this.x0,
    required this.y0,
    required this.startK,
  });

  final int pointer;
  final double x0;
  final double y0;

  /// 手势开始时的抽屉进度（跟手位移在此基础上增减）。
  final double startK;

  /// 是否已锁定主方向。
  bool locked = false;

  /// 锁定为横向：跟手拖动抽屉。
  bool horizontal = false;

  /// 锁定为竖直方向：把手无竖直动作，本次手势作废。
  bool dead = false;
}

/// AI 条上的一次长按。
class AiHold {
  AiHold({required this.pointer, required this.x0, required this.y0});

  final int pointer;
  final double x0;
  final double y0;

  /// 移动超 8px：取消长按。
  bool cancelled = false;

  /// 已满 450ms 呼出对话框（保留记录直到松手，以复位按压外观）。
  bool fired = false;
}

/// 一个涟漪的位置描述。
class RippleSpec {
  RippleSpec({required this.center});

  /// 涟漪圆心。
  final Offset center;
}
