import 'package:flutter/material.dart';

import '../../services/haptics.dart';
import 'block_widget.dart';
import 'editor_scope.dart';

/// 块列表：懒加载（200 块目标），块状态由控制器持有、翻页不销毁。
///
/// 结构变化（拆/合块、转标题、底色、拖动重排）由控制器 notify 触发整列表
/// rebuild；普通打字只走各自 TextEditingController，不重建列表。
///
/// 滚动体用 [CustomScrollView] + [SliverReorderableList]：块把手内置
/// `ReorderableDelayedDragStartListener`，长按起拖、松手由框架落位并回调
/// [BlockEditorController.moveBlockAt]（生效即压撤销快照），拖动代理与
/// 空位让渡动画均由框架接管。时间戳块同样有把手、可长按拖动换位，
/// 但保持只读胶囊渲染、不进入文字编辑。
///
/// [header] 可选：挂在滚动区**首项**（如日页胶囊行），随正文一起滚动、
/// 不参与块结构（不进序列化），也不参与拖拽。
class BlockEditorView extends StatelessWidget {
  const BlockEditorView({
    super.key,
    this.contentPadding = const EdgeInsets.symmetric(vertical: 8),
    this.header,
  });

  final EdgeInsets contentPadding;

  /// 滚动区首项；null 时列表即块列表。
  final Widget? header;

  @override
  Widget build(BuildContext context) {
    final editor = BlockEditorScope.of(context);
    return ListenableBuilder(
      listenable: editor,
      builder: (context, _) {
        final states = editor.blocks;
        final head = header;
        // 原先单列表的 vertical padding 落在整表首尾；拆成两条 sliver 后，
        // top 归 header（无 header 时归块列表首项）、bottom 始终归块列表末
        // 项，首尾留白与旧实现逐项一致，header 与首块之间不新增空隙。
        EdgeInsets insets({required bool top, required bool bottom}) =>
            EdgeInsets.only(
              left: contentPadding.left,
              right: contentPadding.right,
              top: top ? contentPadding.top : 0,
              bottom: bottom ? contentPadding.bottom : 0,
            );
        return CustomScrollView(
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          slivers: [
            if (head != null)
              SliverPadding(
                padding: insets(top: true, bottom: false),
                sliver: SliverToBoxAdapter(
                  child: KeyedSubtree(
                    key: const ValueKey<String>('diary-capsule-row'),
                    child: head,
                  ),
                ),
              ),
            SliverPadding(
              padding: insets(top: head == null, bottom: true),
              sliver: SliverReorderableList(
                itemCount: states.length,
                // 长按满阈值、真正拿起块的那一刻给一次确认震（离手前只触发
                // 一次），让「可拖动」有触觉确认；落位不震，避免噪声。
                // 走 Haptics 原生通道，绕过系统触感开关与 lightImpact 的
                // 弱映射（MIX 2S 上几乎无感）。
                onReorderStart: (_) => Haptics.confirm(),
                onReorderItem: editor.moveBlockAt,
                // 被拖块会被摘进 Overlay 重挂，那儿没有 Scaffold 的 Material，
                // 而块内 TextField 断言必须有 Material 祖先——代理里补一层
                // 透明 Material（与 ReorderableListView 内部同法），顺带
                // 用轻微抬升阴影给出「拿起」反馈。
                proxyDecorator: _liftedBlockProxy,
                itemBuilder: (context, index) {
                  final state = states[index];
                  return BlockWidget(
                    key: ValueKey<String>(state.block.id),
                    state: state,
                    index: index,
                  );
                },
              ),
            ),
          ],
        );
      },
    );
  }
}

/// 拖拽代理装饰：透明 [Material] 撑起被拖块的 Material 祖先，并按拿起动画
/// 叠一层抬升阴影（松手回落）。深色底上阴影克制，主要靠邻居让位动画读形。
Widget _liftedBlockProxy(Widget child, int index, Animation<double> animation) {
  return AnimatedBuilder(
    animation: animation,
    builder: (context, _) => Material(
      color: Colors.transparent,
      elevation: 8 * animation.value,
      shadowColor: const Color(0x99000000),
      child: child,
    ),
  );
}
