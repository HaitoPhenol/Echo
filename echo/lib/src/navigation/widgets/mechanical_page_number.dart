import 'package:flutter/material.dart';

import '../../theme/mechanical_style.dart';

/// 每页随横滑移动的空心大页码（机能风实验 feat/page-background-art）。
///
/// 120sp 白描边空心数字（稿 .idx：top:5vh/right 靠中间收，
/// 填充透明、1dp 白α.10 描边），IgnorePointer 不挡手势；
/// 画在页面轨道内、与页面一起横滑，固定背景与读数条不动。
/// 实验放弃时本文件随背景层一起删除。
class MechanicalPageNumber extends StatelessWidget {
  const MechanicalPageNumber({super.key, required this.index});

  /// 页码序号（0 起），显示为两位数 01、02……
  final int index;

  @override
  Widget build(BuildContext context) {
    final screenSize = MediaQuery.sizeOf(context);
    return Positioned(
      top: screenSize.height * MechanicalStyle.pageNumberTopFactor,
      right: screenSize.width * MechanicalStyle.pageNumberRightFactor,
      child: IgnorePointer(
        child: Text(
          (index + 1).toString().padLeft(2, '0'),
          style: TextStyle(
            fontSize: MechanicalStyle.pageNumberFontSize,
            fontWeight: FontWeight.w700,
            height: 1,
            letterSpacing: 0,
            // 只描边不填充（稿 -webkit-text-stroke；不能再给 color，
            // TextStyle 不允许 color 与 foreground 并存）。
            foreground:
                Paint()
                  ..style = PaintingStyle.stroke
                  ..strokeWidth = MechanicalStyle.pageNumberStrokeWidth
                  ..color = MechanicalStyle.pageNumberStrokeColor,
          ),
        ),
      ),
    );
  }
}
