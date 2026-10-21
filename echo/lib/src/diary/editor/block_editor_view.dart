import 'dart:async';

import 'package:flutter/material.dart';

import '../../services/haptics.dart';
import '../sy/diary_model.dart';
import 'block_editor_controller.dart';
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
/// 但保持只读胶囊渲染、不进入文字编辑；拖动时间戳时整段随之搬移
/// （见 [BlockEditorController.moveBlockAt]），正文块仍是单块自由移动。
///
/// 拖动时间戳期间，段内其余正文块在列表原位隐藏（[Opacity] 0，仍占位，
/// 避免列表高度抖动），由拖拽代理把它们按静态预览一起浮起
/// （[BlockDragPreview]）——框架的代理只覆盖被拖的那一块，段其余部分
/// 只能由代理自行补画。
///
/// 内容超出视口时，列表尾部再补一段「可达留白」（约视口高度 1/3）：
/// 最后一块能继续上滑到屏幕下三分之一处，不被底部导航栏压住，便于
/// 聚焦操作；内容装得下时留白撤除，短文档仍不可空滚。
///
/// [header] 可选：挂在滚动区**首项**（如日页胶囊行），随正文一起滚动、
/// 不参与块结构（不进序列化），也不参与拖拽。
class BlockEditorView extends StatefulWidget {
  const BlockEditorView({
    super.key,
    this.contentPadding = const EdgeInsets.symmetric(vertical: 8),
    this.header,
  });

  final EdgeInsets contentPadding;

  /// 滚动区首项；null 时列表即块列表。
  final Widget? header;

  @override
  State<BlockEditorView> createState() => _BlockEditorViewState();
}

class _BlockEditorViewState extends State<BlockEditorView> {
  /// 正在整段拖动的时间戳段范围（null = 普通单块拖动或未在拖）。
  ///
  /// 仅用于两件事：隐藏原位正文块、让代理补画整段预览；落位后立即清空。
  int? _dragSegmentStart;
  int? _dragSegmentEnd;

  /// 松手后框架还要播 ~250ms 的代理回落动画，等它结束再恢复原位正文；
  /// 同位置落点不会触发 `onReorderItem`，故用定时器兜底清空。
  Timer? _dragClearTimer;

  /// 列表尾部额外留出的可滚动距离（0 = 内容未超出视口，不预留）。
  ///
  /// 占视口高度约 1/3：滚到底时最后一块停在屏幕下三分之一处，
  /// 不被底部导航栏遮挡。
  double _bottomOverscroll = 0;

  final ScrollController _scroll = ScrollController();

  @override
  void dispose() {
    _dragClearTimer?.cancel();
    _scroll.dispose();
    super.dispose();
  }

  /// 内容是否超出视口 → 维护尾部「可达留白」。
  ///
  /// 留白本身计入 `maxScrollExtent`，故用它与留白高度比较来判定：
  /// 内容超出时 `maxScrollExtent > 留白`；内容装得下时
  /// `maxScrollExtent ≤ 留白`，此时撤掉留白（短文档不产生空滚）。
  /// 视口高度变化（软键盘开合）时留白同步按新视口重算。
  void _syncBottomOverscroll() {
    if (!mounted || !_scroll.hasClients) return;
    final position = _scroll.position;
    if (!position.hasContentDimensions) return;
    const epsilon = 0.5;
    final target = position.viewportDimension / 3;
    final extra = _bottomOverscroll;
    if (extra == 0) {
      if (position.maxScrollExtent > epsilon) {
        setState(() => _bottomOverscroll = target);
      }
      return;
    }
    if ((extra - target).abs() > epsilon) {
      setState(() => _bottomOverscroll = target);
    } else if (position.maxScrollExtent <= extra + epsilon) {
      setState(() => _bottomOverscroll = 0);
    }
  }

  void _handleReorderStart(int index, BlockEditorController editor) {
    // 长按满阈值、真正拿起块的那一刻给一次确认震（离手前只触发一次），
    // 让「可拖动」有触觉确认；落位不震，避免噪声。走 Haptics 原生通道，
    // 绕过系统触感开关与 lightImpact 的弱映射（MIX 2S 上几乎无感）。
    Haptics.confirm();
    // 上一次拖拽的兜底定时器可能还在等：先取消，避免它清掉本次段范围。
    _dragClearTimer?.cancel();
    _dragClearTimer = null;
    final blocks = editor.blocks;
    if (index < 0 || index >= blocks.length || !blocks[index].block.isStamp) {
      // 非时间戳拖动：清掉可能残留的段范围，避免旧段继续透明占位。
      if (_dragSegmentStart != null) {
        setState(() {
          _dragSegmentStart = null;
          _dragSegmentEnd = null;
        });
      }
      return;
    }
    var end = index;
    while (end + 1 < blocks.length && !blocks[end + 1].block.isStamp) {
      end++;
    }
    if (end == index) return; // 段内没有正文可浮起，按单块处理
    setState(() {
      _dragSegmentStart = index;
      _dragSegmentEnd = end;
    });
  }

  /// 松手（或拖拽被取消）后延迟恢复段内正文的原位显示。
  void _scheduleDragClear() {
    if (_dragSegmentStart == null) return;
    _dragClearTimer?.cancel();
    _dragClearTimer = Timer(const Duration(milliseconds: 280), () {
      if (!mounted || _dragSegmentStart == null) return;
      setState(() {
        _dragSegmentStart = null;
        _dragSegmentEnd = null;
      });
    });
  }

  void _clearDragSegment() {
    _dragClearTimer?.cancel();
    _dragClearTimer = null;
    if (_dragSegmentStart == null) return;
    setState(() {
      _dragSegmentStart = null;
      _dragSegmentEnd = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final editor = BlockEditorScope.of(context);
    // 首帧/每次结构变化后量一次滚动范围，决定是否补尾部留白。
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => _syncBottomOverscroll(),
    );
    return ListenableBuilder(
      listenable: editor,
      builder: (context, _) {
        final states = editor.blocks;
        // 段边界逐块派生：与导出 `_rowSegments` 同一套位置语义，
        // 供块组件拼出连续的段框（不改列表结构）。
        final edges = DiaryStamp.edgesOf([
          for (final state in states) state.block,
        ]);
        final head = widget.header;
        // 原先单列表的 vertical padding 落在整表首尾；拆成两条 sliver 后，
        // top 归 header（无 header 时归块列表首项）、bottom 始终归块列表末
        // 项，首尾留白与旧实现逐项一致，header 与首块之间不新增空隙。
        EdgeInsets insets({required bool top, required bool bottom}) =>
            EdgeInsets.only(
              left: widget.contentPadding.left,
              right: widget.contentPadding.right,
              top: top ? widget.contentPadding.top : 0,
              bottom: bottom ? widget.contentPadding.bottom : 0,
            );
        return Listener(
          onPointerUp: (_) => _scheduleDragClear(),
          onPointerCancel: (_) => _scheduleDragClear(),
          // 打字/输入法改变块高时列表不重建，但滚动范围会变；
          // 借 metrics 通知在帧后重新评估尾部留白。
          child: NotificationListener<ScrollMetricsNotification>(
            onNotification: (_) {
              WidgetsBinding.instance.addPostFrameCallback(
                (_) => _syncBottomOverscroll(),
              );
              return false;
            },
            child: CustomScrollView(
              controller: _scroll,
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
                    onReorderStart: (index) =>
                        _handleReorderStart(index, editor),
                    // 松手后框架先回落代理、再回调本方法重排数据；同位置落点
                    // 不会回调本方法，由 [Listener] 的定时器兜底清空。
                    onReorderItem: (oldIndex, newIndex) {
                      editor.moveBlockAt(oldIndex, newIndex);
                      _clearDragSegment();
                    },
                    // 被拖块会被摘进 Overlay 重挂，那儿没有 Scaffold 的
                    // Material，而块内 TextField 断言必须有 Material 祖先——
                    // 代理里补一层透明 Material（与 ReorderableListView 内部
                    // 同法），顺带用轻微抬升阴影给出「拿起」反馈。
                    proxyDecorator: (child, index, animation) =>
                        _liftedBlockProxy(
                          child,
                          index,
                          animation,
                          editor: editor,
                          segmentStart: _dragSegmentStart,
                          segmentEnd: _dragSegmentEnd,
                        ),
                    itemBuilder: (context, index) {
                      final state = states[index];
                      final blockKey = ValueKey<String>(state.block.id);
                      final hidden =
                          _dragSegmentStart != null &&
                          _dragSegmentEnd != null &&
                          index > _dragSegmentStart! &&
                          index <= _dragSegmentEnd!;
                      // 外层常驻 [Opacity]/[IgnorePointer]，只切换参数，
                      // 拖动期间不重建段内正文的 TextField（焦点/控制器不丢）。
                      return Opacity(
                        key: blockKey,
                        opacity: hidden ? 0 : 1,
                        child: IgnorePointer(
                          ignoring: hidden,
                          child: BlockWidget(
                            key: blockKey,
                            state: state,
                            index: index,
                            segment: edges[index],
                          ),
                        ),
                      );
                    },
                  ),
                ),
                // 尾部可达留白：滚到底时把最后一块抬到屏幕下三分之一处。
                if (_bottomOverscroll > 0)
                  SliverToBoxAdapter(
                    child: SizedBox(height: _bottomOverscroll),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// 拖拽代理装饰：透明 [Material] 撑起被拖块的 Material 祖先，并按拿起动画
/// 叠一层抬升阴影（松手回落）。深色底上阴影克制，主要靠邻居让位动画读形。
///
/// 整段拖动时在代理里补画段内其余正文块的静态预览，让「拖着整个超级块」
/// 在视觉上成立；预览不建 TextField，实块仍在列表原位透明占位。
Widget _liftedBlockProxy(
  Widget child,
  int index,
  Animation<double> animation, {
  required BlockEditorController editor,
  required int? segmentStart,
  required int? segmentEnd,
}) {
  var content = child;
  final blocks = editor.blocks;
  final segEnd = segmentEnd;
  final isSegmentDrag =
      segmentStart == index &&
      segEnd != null &&
      segEnd > index &&
      index < blocks.length;
  if (isSegmentDrag) {
    final edges = DiaryStamp.edgesOf([
      for (final state in blocks) state.block,
    ]);
    final previews = <Widget>[child];
    for (var i = index + 1; i <= segEnd && i < blocks.length; i++) {
      previews.add(
        BlockDragPreview(state: blocks[i], segment: edges[i]),
      );
    }
    content = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: previews,
    );
  }
  return AnimatedBuilder(
    animation: animation,
    builder: (context, _) => Material(
      color: Colors.transparent,
      elevation: 8 * animation.value,
      shadowColor: const Color(0x99000000),
      child: content,
    ),
  );
}
