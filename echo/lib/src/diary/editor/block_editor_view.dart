import 'package:flutter/material.dart';

import 'block_widget.dart';
import 'editor_scope.dart';

/// 块列表：懒加载（200 块目标），块状态由控制器持有、翻页不销毁。
///
/// 结构变化（拆/合块、转标题、底色）由控制器 notify 触发整列表
/// rebuild；普通打字只走各自 TextEditingController，不重建列表。
///
/// [header] 可选：挂在滚动区**首项**（如日页胶囊行），随正文一起滚动、
/// 不参与块结构（不进序列化）。
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
        final offset = head == null ? 0 : 1;
        return ListView.builder(
          padding: contentPadding,
          itemCount: offset + states.length,
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          itemBuilder: (context, index) {
            if (head != null && index == 0) {
              return KeyedSubtree(
                key: const ValueKey<String>('diary-capsule-row'),
                child: head,
              );
            }
            final state = states[index - offset];
            return BlockWidget(
              key: ValueKey<String>(state.block.id),
              state: state,
            );
          },
        );
      },
    );
  }
}
