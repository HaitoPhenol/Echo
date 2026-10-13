import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

/// G4-BUG-3 slash 提交后 IME hide「终态补帧器」（MIX 2S / Android 10 /
/// MIUI + 豆包 IME 真机坐标对照实验实锤后的纯 Dart 修复）。
///
/// 根因（不是 relayout、不是失焦）：触屏 IME 点「完成」提交 slash 指令
/// 后豆包 IME 自 hide，窗口 surface 从键盘压缩尺寸 resize 回全屏。
/// Flutter 的布局与 hit-test 会随**最终全屏 metrics** 正确更新（真机实测
/// 红按钮真实命中盒在物理 y≈1893），但引擎在 surface resize 期间把
/// 「最终布局帧」丢了/没提交上屏——SurfaceView 可见的最后一帧停在键盘
/// 动画中途（按钮画在物理 y≈1595）。此后 app 静止、无脏区不再产帧，
/// 于是「视觉残影 vs 触摸已正确」：点视觉位置无响应，点视觉空白处
/// 反而命中。任何后续产帧（BACK、点中后的状态变化）都会让画面立刻
/// 对齐，反证根因就是少一帧。
///
/// 修复模型（补帧，不再 relayout/unfocus）：slash 提交后打开一个短时
/// 补帧窗口（[scheduleAfterSlashSubmit]）；窗口内收到「表面已恢复全屏、
/// 底部 inset 归零」的终态 metrics 时，对根 RenderView 标脏
/// （markNeedsLayout），强制管线产出并向新 surface 重新提交一帧
/// scene；并在该帧结束后的下一个 vsync 再标脏一次，覆盖 ROM 的
/// surface resize 完成晚于首个全屏 metrics 回调的时序。另设提交后
/// 200ms 的定时器兜底（metrics 回调缺失/时序抖动时同样强补一帧）。
/// 窗口（默认 1.2s）外不做任何事，常态零开销；不挂钩普通搜索/日记
/// 编辑路径，非 Android 平台一律静默。
///
/// 历史方案（均经 MIX 2S 真机证伪，代码已删，仅留档防回退）：
/// - 二修：原生 `echo/window_insets#refreshInsets`
///   （requestApplyInsets + softInputMode ADJUST_NOTHING/RESIZE toggle）
///   ——平台 View 尺寸早已正确，不产生真实尺寸变化的 relayout 不会让
///   引擎重发 metrics，机理上注定无效；
/// - 三修：提交后程序化 `primaryFocus.unfocus()`——豆包「完成」到达
///     Dart 时焦点链不产生 dispose 时那次干净的 IMM 断开，且缺陷与
///   metrics/焦点无关；
/// - 四修（方案 C）：TextInput.hide + clearClient 复刻 dispose 链
///   ——metrics 本就到达、布局本就正确，问题在丢帧；动 IME 连接不能
///   补回被 surface resize 吞掉的那一帧，且有输入连接副作用。
abstract final class WindowInsetRefresher {
  /// slash 提交后的补帧窗口长度：覆盖 IME hide 动画（多数机型
  /// 100-200ms）+ ROM surface resize 抖动余量；窗口外零开销，
  /// 取 1.2s 既远离误判窗口、又早于用户任何「放着不动再点」的场景
  /// （3s 后点按钮依赖的是已对齐的画面，不需要窗口仍开着）。
  static const Duration _defaultWindow = Duration(milliseconds: 1200);

  /// 提交后兜底强补帧延时：metrics 回调正常时本定时器只是「surface
  /// 已稳定」的再一次补帧；异常（回调缺失/时序不符）时它是主补救。
  /// 取 200ms：晚于多数机型 hide 动画收尾，且早于人手下一步点按。
  static const Duration _defaultFallbackDelay = Duration(milliseconds: 200);

  /// widget 测试覆盖窗口长度用（fake-async 下无需真等 IME 动画）。
  @visibleForTesting
  static Duration? windowOverride;

  /// widget 测试覆盖兜底延时时用；null 取 [_defaultFallbackDelay]。
  @visibleForTesting
  static Duration? fallbackDelayOverride;

  static MetricsFramePacer? _pacer;

  /// 注册 app 级补帧单例（幂等）。
  ///
  /// 由宿主主屏启动时调用一次：早于任何 slash 提交，使补帧器在键盘
  /// 尚未弹起时就建立「全屏物理高」基线。[scheduleAfterSlashSubmit]
  /// 内部也会兜底注册。
  static void ensureRegistered() {
    if (defaultTargetPlatform != TargetPlatform.android) return;
    _pacer ??= MetricsFramePacer();
  }

  /// slash 指令提交后打开补帧窗口（仅 Android；fire-and-forget）。
  ///
  /// 连续提交以最后一次为准（重置窗口与兜底定时器）。
  static void scheduleAfterSlashSubmit() {
    if (defaultTargetPlatform != TargetPlatform.android) return;
    ensureRegistered();
    _pacer!.openWindow(
      window: windowOverride ?? _defaultWindow,
      fallbackDelay: fallbackDelayOverride ?? _defaultFallbackDelay,
    );
  }

  /// 测试缝：截至当前补帧器对根 RenderView 标脏的次数（每次触发
  /// = 当帧一次 + 次帧跟进一次）。
  @visibleForTesting
  static int get debugForcedFrameCount => _pacer?.forcedFrameCount ?? 0;

  /// 测试缝：补帧窗口是否处于打开状态。
  @visibleForTesting
  static bool get debugWindowActive => _pacer?.active ?? false;

  /// 测试缝：重置单例（摘除 observer、取消定时器、清基线与计数），
  /// 避免同一进程内多个用例互相污染。
  @visibleForTesting
  static void debugReset() {
    _pacer?.dispose();
    _pacer = null;
  }
}

/// [WindowInsetRefresher] 的实际实现：一个 app 级 [WidgetsBindingObserver]
/// 单例，只在短补帧窗口内响应 metrics。
class MetricsFramePacer with WidgetsBindingObserver {
  MetricsFramePacer() {
    _fullPhysicalHeight = _primaryView?.physicalSize.height ?? 0;
    WidgetsBinding.instance.addObserver(this);
  }

  /// 非补帧期观测到的最大表面物理高（即无键盘全屏基线）。
  ///
  /// 宿主启动时（键盘未弹起）即注册，初值就是全屏高；普通搜索/日记
  /// 路径键盘弹压只见到更小值，不会抬升基线，键盘收起回到同值。
  double _fullPhysicalHeight = 0;

  Timer? _windowTimer;
  Timer? _fallbackTimer;

  bool _active = false;

  /// 累计对根 RenderView 标脏次数（测试缝读 [debugForcedFrameCount]）。
  @visibleForTesting
  int forcedFrameCount = 0;

  static const double _heightEpsilon = 0.5;

  bool get active => _active;

  ui.FlutterView? get _primaryView {
    final views = WidgetsBinding.instance.platformDispatcher.views;
    return views.isEmpty ? null : views.first;
  }

  /// 打开补帧窗口：重置窗口超时与兜底定时器。
  void openWindow({required Duration window, required Duration fallbackDelay}) {
    _active = true;
    _windowTimer?.cancel();
    _fallbackTimer?.cancel();
    _windowTimer = Timer(window, _closeWindow);
    _fallbackTimer = Timer(fallbackDelay, () {
      // 不要求终态 metrics：此刻正常情况下 hide 已收尾、布局已是全屏，
      // 补这一帧正好落在 surface 稳定之后；键盘未收起（如物理 ENTER
      // 提交）时按当前尺寸重提一帧，内容不变、视觉无扰动。
      if (_active) forceCatchUpFrames();
    });
  }

  void _closeWindow() {
    _active = false;
    _windowTimer = null;
    _fallbackTimer?.cancel();
    _fallbackTimer = null;
  }

  @override
  void didChangeMetrics() {
    final view = _primaryView;
    if (view == null) return;
    final height = view.physicalSize.height;

    if (!_active) {
      // 只在窗口外抬升基线，确保基线始终是「无键盘全屏」而不是
      // slash 提交时的键盘压缩高。
      if (height > _fullPhysicalHeight) _fullPhysicalHeight = height;
      return;
    }

    // 终态判定：表面物理高回到全屏基线、且无底部 view inset。
    // adjustResize 机型 hide 动画中途的中间高度一律忽略；只有最终
    // 全屏 metrics 才值得补帧（中间态补了也会随后续 metrics 继续产帧，
    // 故即便 ROM 一次性跳到全屏、resize 尚未完成，次帧跟进也兜得住）。
    if (view.viewInsets.bottom == 0 &&
        height >= _fullPhysicalHeight - _heightEpsilon) {
      if (height > _fullPhysicalHeight) _fullPhysicalHeight = height;
      forceCatchUpFrames();
    }
  }

  /// 强制管线产出并重提一帧 scene，并在下一个 vsync 再补一帧。
  ///
  /// [RenderObject.markNeedsLayout] 把根 RenderView 挂进管线布局脏表
  /// （owner.requestVisualPosition 顺带确保调度一帧）；随后
  /// drawFrame 末尾 RenderView.compositeFrame 会无条件用当前 layer 树
  /// buildScene 并提交给引擎——布局/hit-test 既已正确，重提的这一帧
  /// 就是视觉对齐的最终布局帧。次帧跟进覆盖 surface resize 完成晚于
  /// 首个全屏 metrics 的时序（被吞的是第 N 帧，就补到 N+1）。
  void forceCatchUpFrames() {
    _markRootsDirty();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      // 窗口可能恰好在本帧前关闭；窗口外绝不产帧。
      if (_active) _markRootsDirty();
    });
  }

  void _markRootsDirty() {
    final renderViews = RendererBinding.instance.renderViews;
    for (final renderView in renderViews) {
      renderView.markNeedsLayout();
    }
    forcedFrameCount += renderViews.length;
  }

  /// 摘除 observer 并取消全部定时器（仅测试/单例销毁时调用）。
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _windowTimer?.cancel();
    _fallbackTimer?.cancel();
    _windowTimer = null;
    _fallbackTimer = null;
    _active = false;
  }
}
