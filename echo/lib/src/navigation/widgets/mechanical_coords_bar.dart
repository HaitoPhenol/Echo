import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../theme/app_colors.dart';
import '../../theme/mechanical_style.dart';

/// 顶部固定的设备状态读数条（机能风视觉层组件）。
///
/// 显示 `DEV 型号 · T 电池温度 · P 瞬时功耗`，数据来自原生通道
/// `echo/device_stats`（见 MainActivity.kt，零三方库零权限），
/// 每 5 秒轮询一次；拿不到数据（测试环境/无传感器）时数值显示「—」。
///
/// 纯展示、[IgnorePointer] 不挡手势、固定不随翻页移动。
class MechanicalCoordsBar extends StatefulWidget {
  const MechanicalCoordsBar({super.key});

  @override
  State<MechanicalCoordsBar> createState() => _MechanicalCoordsBarState();
}

class _MechanicalCoordsBarState extends State<MechanicalCoordsBar> {
  static const _channel = MethodChannel('echo/device_stats');

  /// 轮询周期：状态量变化慢，5 秒足够且几乎零开销。
  static const _pollInterval = Duration(seconds: 5);

  Timer? _timer;
  String _model = '—';
  String? _tempC;
  String? _powerW;

  @override
  void initState() {
    super.initState();
    _refresh();
    _timer = Timer.periodic(_pollInterval, (_) => _refresh());
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _refresh() async {
    try {
      final data =
          await _channel.invokeMapMethod<String, dynamic>('snapshot');
      if (!mounted || data == null) return;
      setState(() {
        _model = (data['model'] as String?) ?? '—';
        _tempC = _format1(data['tempC'], '°C');
        _powerW = _format1(data['powerW'], 'W');
      });
    } on MissingPluginException {
      // widget 测试 / 非 Android 环境：保持「—」降级显示。
    } on PlatformException {
      // 原生侧异常：同样降级，不影响页面。
    }
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
      color: highlighted
          ? AppColors.mechCoordsHi
          : AppColors.mechCoordsDim,
      height: 1.2,
    ),
  );

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: FittedBox(
        fit: BoxFit.scaleDown,
        child: Text.rich(
          TextSpan(
            children: [
              _span('DEV ', highlighted: false),
              _span(_model, highlighted: true),
              _span('  ·  T ', highlighted: false),
              _span(_tempC ?? '—', highlighted: true),
              _span('  ·  P ', highlighted: false),
              _span(_powerW ?? '—', highlighted: true),
            ],
          ),
          maxLines: 1,
        ),
      ),
    );
  }
}
