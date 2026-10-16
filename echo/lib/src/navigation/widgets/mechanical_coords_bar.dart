import 'package:flutter/material.dart';

import '../../services/console_stats_service.dart';
import '../../theme/app_colors.dart';
import '../../theme/mechanical_style.dart';

/// 顶部固定的设备状态读数条（机能风视觉层组件）。
///
/// 显示 `DEV 型号 · T 电池温度 · P 瞬时功耗`。读数与 5 秒轮询统一
/// 收口在 [ConsoleStatsService]（设计 §9.3）：本组件只负责格式化
/// 渲染，adb 命令、定时刷新、sys.info 与它同源。拿不到数据
///（测试环境/无传感器）时数值显示「—」。
///
/// 纯展示、[IgnorePointer] 不挡手势、固定不随翻页移动。
class MechanicalCoordsBar extends StatefulWidget {
  const MechanicalCoordsBar({super.key, this.stats});

  /// 装配层注入的同源服务；为空（widget 测试不经 ControlBootstrap）
  /// 时自建一个降级实例，行为与提升前一致（无通道 → 全「—」）。
  final ConsoleStatsService? stats;

  @override
  State<MechanicalCoordsBar> createState() => _MechanicalCoordsBarState();
}

class _MechanicalCoordsBarState extends State<MechanicalCoordsBar> {
  late final ConsoleStatsService _stats;
  late final bool _ownsStats;

  @override
  void initState() {
    super.initState();
    _ownsStats = widget.stats == null;
    _stats = widget.stats ?? ConsoleStatsService();
  }

  @override
  void dispose() {
    if (_ownsStats) _stats.dispose();
    super.dispose();
  }

  /// 数值保留 1 位小数；null/无效返回 null（视图层显示 —）。
  String? _format1(Object? value, String unit) {
    if (value is num && value.isFinite) {
      return '${value.toStringAsFixed(1)}$unit';
    }
    return null;
  }

  TextSpan _span(String text, {required bool highlighted}) => TextSpan(
    text: text,
    style: TextStyle(
      fontSize: MechanicalStyle.coordsFontSize,
      letterSpacing: MechanicalStyle.coordsLetterSpacing,
      color: highlighted ? AppColors.mechCoordsHi : AppColors.mechCoordsDim,
      height: 1.2,
    ),
  );

  @override
  Widget build(BuildContext context) {
    // 纯装饰视觉层，无障碍树中排除播报（G6）。
    return ExcludeSemantics(
      child: IgnorePointer(
        child: ListenableBuilder(
          listenable: _stats,
          builder: (context, _) {
            final s = _stats.snapshot;
            return FittedBox(
              fit: BoxFit.scaleDown,
              child: Text.rich(
                TextSpan(
                  children: [
                    _span('DEV ', highlighted: false),
                    _span(s.model, highlighted: true),
                    _span('  ·  T ', highlighted: false),
                    _span(_format1(s.tempC, '°C') ?? '—', highlighted: true),
                    _span('  ·  P ', highlighted: false),
                    _span(_format1(s.powerW, 'W') ?? '—', highlighted: true),
                  ],
                ),
                maxLines: 1,
              ),
            );
          },
        ),
      ),
    );
  }
}
