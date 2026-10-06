import 'package:flutter/material.dart';

import '../../theme/app_colors.dart';

/// 底部三条最左侧的**把手条**。
///
/// 视觉与导航条本体完全一致（tone1、半圆端、10px 高、宽 12% 屏宽），
/// 功能上是一组手势的总入口（手势识别全部在父级 SmartNavScreen）：
/// - 单击：本页操作竖单向上生长；
/// - 右拖：侧边空壳抽屉跟手滑出；
/// - 抽屉打开后点按/拖回：关闭抽屉。
///
/// 按压与拖动期间**无外观变化**（用户拍板，同拇指滑块）——反馈由
/// 竖单/抽屉的状态变化与振动承担。竖单展开期间本组件由父级隐藏，
/// 竖单起始帧外观与本组件完全一致（同位置同色的半圆小条）。
class HandleBar extends StatelessWidget {
  const HandleBar({super.key});

  @override
  Widget build(BuildContext context) {
    return const DecoratedBox(
      decoration: BoxDecoration(
        color: AppColors.tone1,
        borderRadius: BorderRadius.all(Radius.circular(999)),
      ),
    );
  }
}
