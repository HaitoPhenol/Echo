import 'package:flutter/material.dart';

import 'block_widget.dart';
import 'editor_scope.dart';

/// 块列表：懒加载（200 块目标），块状态由控制器持有、翻页不销毁。
///
/// 结构变化（拆/合块、转标题、底色）由控制器 notify 触发整列表
/// rebuild；普通打字只走各自 TextEditingController，不重建列表。
class BlockEditorView extends StatelessWidget {
  const BlockEditorView({
    super.key,
    this.contentPadding = const EdgeInsets.symmetric(vertical: 8),
  });

  final EdgeInsets contentPadding;

  @override
  Widget build(BuildContext context) {
    final editor = BlockEditorScope.of(context);
    return ListenableBuilder(
      listenable: editor,
      builder: (context, _) {
        final states = editor.blocks;
        return ListView.builder(
          padding: contentPadding,
          itemCount: states.length,
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          itemBuilder: (context, index) {
            final state = states[index];
            return BlockWidget(key: ValueKey<String>(state.block.id), state: state);
          },
        );
      },
    );
  }
}
