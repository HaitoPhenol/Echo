import 'package:flutter/widgets.dart';

import 'block_editor_controller.dart';

/// 向编辑子树提供 [BlockEditorController]（块组件经它读样式、发命令；
/// 结构变化时整棵子树 rebuild，ListView 外的状态不丢）。
///
/// 继承 [InheritedTheme] 而非 [InheritedNotifier]：块拖拽时
/// `SliverReorderableList` 会把被拖块**摘到 Overlay 里重挂**，只用
/// `InheritedTheme.capture` 把途经的 theme 类祖先一并搬过去。若本 scope
/// 不参与该机制，代理子树里 `of(context)` 会取不到控制器而断言失败。
/// 重建通知不依赖 scope——`BlockEditorView` 自建 `ListenableBuilder` 监听，
/// 故这里只需在控制器换实例时通知（正常恒为同一实例、不外泄）。
class BlockEditorScope extends InheritedTheme {
  const BlockEditorScope({
    super.key,
    required this.controller,
    required super.child,
  });

  final BlockEditorController controller;

  static BlockEditorController of(BuildContext context) {
    final controller = maybeOf(context);
    assert(controller != null, '子树中缺少 BlockEditorScope');
    return controller!;
  }

  static BlockEditorController? maybeOf(BuildContext context) => context
      .dependOnInheritedWidgetOfExactType<BlockEditorScope>()
      ?.controller;

  @override
  Widget wrap(BuildContext context, Widget child) =>
      BlockEditorScope(controller: controller, child: child);

  @override
  bool updateShouldNotify(BlockEditorScope oldWidget) =>
      controller != oldWidget.controller;
}
