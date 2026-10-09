import 'package:flutter/material.dart';

import '../services/chat_store.dart';
import '../services/haptics.dart';
import '../theme/app_colors.dart';

/// 聊天页（会话列表）。
///
/// **没有标题栏**：整页就是一条纵向会话列表，铺满导航页面轨道
/// 分配的整块屏幕，最大化可用画面。状态栏安全区作为列表顶部
/// 内边距；底部悬浮着把手 / AI / 导航三条停靠条，故列表底部
/// 预留等高内边距，使最后一行能滚到停靠条之上而不被永久遮挡。
///
/// 数据来自 [ChatStore]：列表初始为空，居中显示「暂无消息」小字，
/// 收到第一条消息后切换为列表。每行含圆形头像框（空白占位）、
/// 昵称、消息预览，行间为屏宽 80%、水平居中的 1px 分隔线；
/// 未读会话右上角有与导航消息锚点同色同节奏的呼吸绿点。交互：
/// - 点按未读行：标记已读（绿点消失，全部已读后导航锚点恢复）；
/// - 左滑行：恒露出等宽两个操作按钮——左为读状态切换（已读行
///   显示「未读」、未读行显示「已读」），右为红色「删除」。
class ChatPage extends StatefulWidget {
  const ChatPage({super.key});

  /// 会话行统一高度：内容区（头像 48 居中）+ 底部 1px 分隔线。
  static const double rowHeight = 72;

  /// 行内容左右边距（与底部停靠三条的屏边留白取同一节奏）。
  static const double rowHorizontalPadding = 14;

  /// 圆形头像框直径。
  static const double avatarSize = 48;

  /// 头像与文案列的间距。
  static const double avatarTextGap = 12;

  /// 昵称 / 预览文案间的行距。
  static const double textLineGap = 4;

  /// 未读绿点直径。
  static const double unreadDotSize = 8;

  /// 单个左滑操作按钮的宽度（操作区恒为两个按钮，总宽 = 2 × 本值）。
  static const double actionButtonWidth = 76;

  /// 行间分隔线占屏幕宽度的比例（水平居中，两侧各留 10%）。
  static const double dividerWidthRatio = 0.8;

  /// 空列表时居中展示的提示文案。
  static const String emptyHint = '暂无消息';

  /// 底部为悬浮停靠三条预留的高度：底边距 16 + 条高 10。
  ///
  /// 数值对齐 navigation 层的 `DockGeometry.bottomMargin + barHeight`。
  /// 页面层不反向依赖 navigation 层（依赖方向是导航持有页面），
  /// 故此处按页面自身所需的避让高度就近定义；停靠几何调整时需
  /// 同步检查本常量。
  static const double _dockReservedHeight = 26;

  @override
  State<ChatPage> createState() => _ChatPageState();
}

class _ChatPageState extends State<ChatPage> {
  /// 当前展开着操作区的行 id（全局只允许一行展开；开另一行会
  /// 通过 open 标记驱动旧行动画收回）。
  String? _openRowId;

  ChatStore get _store => ChatStoreScope.of(context);

  @override
  Widget build(BuildContext context) {
    final store = _store;
    final safePadding = MediaQuery.paddingOf(context);

    // 空态：没有会话时整页居中展示小字提示（无标题栏、无列表）。
    if (store.conversations.isEmpty) {
      return const Center(
        child: Text(ChatPage.emptyHint, style: _emptyHintStyle),
      );
    }

    // 列表开始竖向滚动时收回展开的操作区，避免「行开着滑走」。
    return NotificationListener<ScrollStartNotification>(
      onNotification: (notification) {
        if (notification.depth == 0 &&
            _openRowId != null &&
            notification.dragDetails != null) {
          setState(() => _openRowId = null);
        }
        return false;
      },
      child: ListView.builder(
        key: const ValueKey<String>('chat-page-list'),
        itemExtent: ChatPage.rowHeight,
        itemCount: store.conversations.length,
        // 安全区与停靠条避让走列表内边距而非外包 SafeArea/SizedBox：
        // 列表本身始终铺满全屏，滚动时内容可从停靠条下方穿过。
        padding: EdgeInsets.only(
          top: safePadding.top,
          bottom: safePadding.bottom + ChatPage._dockReservedHeight,
        ),
        itemBuilder: (context, index) {
          final conversation = store.conversations[index];
          return ChatListRow(
            key: ValueKey<String>('chat-row-${conversation.id}'),
            conversation: conversation,
            open: _openRowId == conversation.id,
            onOpenChanged: (open) {
              setState(() => _openRowId = open ? conversation.id : null);
            },
          );
        },
      ),
    );
  }
}

/// 昵称文字样式：主文字（tone4）16px。
const TextStyle _nicknameStyle = TextStyle(
  fontSize: 16,
  color: AppColors.textPrimary,
);

/// 消息预览样式：次级文字（tone2）14px。
const TextStyle _previewStyle = TextStyle(
  fontSize: 14,
  color: AppColors.textMuted,
);

/// 空态提示样式：次级文字（tone2）13px 小字。
const TextStyle _emptyHintStyle = TextStyle(
  fontSize: 13,
  color: AppColors.textMuted,
);

/// 一个会话列表行。
///
/// 由 [_SwipeToReveal] 承载左滑手势：底层是右对齐的操作按钮，
/// 上层前景（不透明页面底色）跟手平移；分隔线画在前景底部、
/// 随前景一起滑动。操作区恒为两个按钮——左为读状态切换
/// （已读行显示「未读」，未读行显示「已读」）、右为「删除」，
/// 宽度不随已读状态变化；未读行点按前景同样是标记已读。
class ChatListRow extends StatelessWidget {
  const ChatListRow({
    super.key,
    required this.conversation,
    required this.open,
    required this.onOpenChanged,
  });

  final ChatConversation conversation;

  /// 操作区是否处于展开态（开合状态由列表统一持有）。
  final bool open;

  /// 开合状态变化通知（吸附到展开/收起时回调）。
  final ValueChanged<bool> onOpenChanged;

  @override
  Widget build(BuildContext context) {
    final store = ChatStoreScope.of(context);
    // 操作区恒为「读状态切换 + 删除」两按钮、恒宽，读状态变化不引发布局跳动。
    const actionWidth = ChatPage.actionButtonWidth * 2;

    return _SwipeToReveal(
      open: open,
      actionWidth: actionWidth.toDouble(),
      onOpenChanged: onOpenChanged,
      // 操作区：右对齐，左为读状态切换，「删除」恒在最右。
      actions: [
        _RowAction(
          label: conversation.unread ? '已读' : '未读',
          color: AppColors.tone2,
          foregroundColor: AppColors.inverse,
          onTap: () {
            Haptics.tick();
            if (conversation.unread) {
              store.markRead(conversation.id);
            } else {
              store.markUnread(conversation.id);
            }
            onOpenChanged(false);
          },
        ),
        _RowAction(
          label: '删除',
          color: AppColors.anchorRed,
          foregroundColor: AppColors.tone4,
          onTap: () {
            Haptics.confirm();
            store.remove(conversation.id);
          },
        ),
      ],
      // 已读行无点按行为；未读行点按即已读。
      onTap: conversation.unread
          ? () {
              Haptics.tick();
              store.markRead(conversation.id);
            }
          : null,
      child: _RowForeground(conversation: conversation),
    );
  }
}

/// 行前景：头像 + 文案 + 未读绿点 + 底部分隔线。
///
/// 机能风实验期（feat/page-background-art）底色透明，让固定背景
/// 纹理透到会话行；左滑操作按钮的遮挡改由 _SwipeToReveal 对操作区
/// 按露出宽度裁剪实现（不再依赖本行不透明实底）。
/// 实验放弃时：本行还原不透明底色、操作区裁剪同步移除。
class _RowForeground extends StatelessWidget {
  const _RowForeground({required this.conversation});

  final ChatConversation conversation;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(color: Colors.transparent),
      child: Stack(
        children: [
          Column(
            children: [
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: ChatPage.rowHorizontalPadding,
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      const ChatAvatar(),
                      const SizedBox(width: ChatPage.avatarTextGap),
                      Expanded(
                        child: Padding(
                          // 未读时文案右侧让出绿点位置，
                          // 避免省略号压在点下。
                          padding: EdgeInsets.only(
                            right: conversation.unread ? 16 : 0,
                          ),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                conversation.nickname,
                                style: _nicknameStyle,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              const SizedBox(height: ChatPage.textLineGap),
                              Text(
                                conversation.preview,
                                style: _previewStyle,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              // 分隔线：屏宽 80%、水平居中（Column 默认交叉轴居中），
              // 置于行底并随前景一起左滑。
              SizedBox(
                width:
                    MediaQuery.sizeOf(context).width *
                    ChatPage.dividerWidthRatio,
                height: 1,
                child: const ColoredBox(color: AppColors.tone1),
              ),
            ],
          ),
          // 未读呼吸绿点：行内容右上角。
          if (conversation.unread)
            const Positioned(
              right: ChatPage.rowHorizontalPadding,
              top: 14,
              child: UnreadDot(),
            ),
        ],
      ),
    );
  }
}

/// 左滑操作区里的单个按钮：填满分配的宽高，纯实色 + 居中文字。
class _RowAction extends StatelessWidget {
  const _RowAction({
    required this.label,
    required this.color,
    required this.foregroundColor,
    required this.onTap,
  });

  final String label;
  final Color color;
  final Color foregroundColor;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: ColoredBox(
        color: color,
        child: SizedBox(
          width: ChatPage.actionButtonWidth,
          child: Center(
            child: Text(
              label,
              style: TextStyle(fontSize: 14, color: foregroundColor),
            ),
          ),
        ),
      ),
    );
  }
}

/// 圆形头像占位框：tone1 描边的空心圆，不填充任何头像内容。
///
/// 接入真实数据后在此挂载头像图片（或首字母占位），框尺寸由
/// [ChatPage.avatarSize] 统一规定。
class ChatAvatar extends StatelessWidget {
  const ChatAvatar({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: ChatPage.avatarSize,
      height: ChatPage.avatarSize,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: AppColors.tone1),
      ),
    );
  }
}

/// 未读呼吸绿点。
///
/// 视觉参数与导航消息锚点完全一致：anchorGreen、1700ms
/// easeInOut 反向循环、不透明度 0.35→1.0、同色辉光
/// blurRadius 8（透明度 0→0.75），保证行内绿点与导航条
/// 锚点「同呼吸」。
class UnreadDot extends StatefulWidget {
  const UnreadDot({super.key});

  @override
  State<UnreadDot> createState() => _UnreadDotState();
}

class _UnreadDotState extends State<UnreadDot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1700),
  )..repeat(reverse: true);

  late final CurvedAnimation _curve = CurvedAnimation(
    parent: _controller,
    curve: Curves.easeInOut,
  );

  @override
  Widget build(BuildContext context) {
    // 必须随动画每帧重建，否则呼吸会冻结（与导航锚点同一教训）。
    return AnimatedBuilder(
      animation: _curve,
      builder: (context, _) {
        final t = _curve.value;
        return Container(
          width: ChatPage.unreadDotSize,
          height: ChatPage.unreadDotSize,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: AppColors.anchorGreen.withValues(alpha: 0.35 + 0.65 * t),
            boxShadow: [
              BoxShadow(
                color: AppColors.anchorGreen.withValues(alpha: 0.75 * t),
                blurRadius: 8,
              ),
            ],
          ),
        );
      },
    );
  }

  @override
  void dispose() {
    _curve.dispose();
    _controller.dispose();
    super.dispose();
  }
}

/// 左滑露出操作区的容器。
///
/// - 底层（[actions]）：右对齐的操作按钮行；
/// - 上层前景（[child]）：不透明，跟手横移，松手按速度/行程
///   吸附到全开或全关，吸附动画 180ms；
/// - 只允许向左滑开：全关时向右的拖动被夹在 0；
/// - 展开状态由父级持有（[open] / [onOpenChanged]），本组件只
///   负责呈现与手势，因此「同时只开一行」由列表统一裁决。
class _SwipeToReveal extends StatefulWidget {
  const _SwipeToReveal({
    required this.open,
    required this.actionWidth,
    required this.actions,
    required this.onOpenChanged,
    required this.child,
    this.onTap,
  });

  final bool open;
  final double actionWidth;
  final List<Widget> actions;
  final ValueChanged<bool> onOpenChanged;
  final Widget child;
  final VoidCallback? onTap;

  @override
  State<_SwipeToReveal> createState() => _SwipeToRevealState();
}

class _SwipeToRevealState extends State<_SwipeToReveal>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 180),
  )..addListener(() => setState(() {}));

  /// 前景水平偏移：0 = 全关，-actionWidth = 全开。
  double get _closedOffset => 0;
  double get _openOffset => -widget.actionWidth;

  /// 吸附动画进行中的值曲线；非动画期间为 null。
  Animation<Offset>? _snapAnim;

  /// 吸附序号：每次启动新吸附 +1，作废旧动画的完成回调
  /// （旧动画被打断时 whenCompleteOrCancel 仍会触发）。
  int _snapSeq = 0;

  /// 是否正在跟手拖动（拖动期间直接写偏移、不响应外部 open 变化）。
  bool _dragging = false;

  /// 跟手阶段的实时偏移。
  double _dragOffset = 0;

  double get _currentOffset {
    if (_dragging) return _dragOffset;
    final anim = _snapAnim;
    if (anim != null) return anim.value.dx;
    return widget.open ? _openOffset : _closedOffset;
  }

  @override
  void didUpdateWidget(_SwipeToReveal oldWidget) {
    super.didUpdateWidget(oldWidget);
    // 外部裁决（开了另一行 / 列表滚动 / 操作后收起）驱动吸附，
    // 但不能打断正在进行的跟手拖动。
    if (!_dragging && widget.open != oldWidget.open) {
      // 此时 widget.open 已是新值，_currentOffset 的静止回退会直接
      // 读到新目标位，必须显式从「当前呈现位置」起播：动画在途取
      // 动画值，否则取旧 widget 对应的静止位——否则会跳变无动画。
      final from = _snapAnim != null
          ? _snapAnim!.value.dx
          : (oldWidget.open ? _openOffset : _closedOffset);
      _animateTo(widget.open ? _openOffset : _closedOffset, from: from);
    }
  }

  /// 启动吸附动画到 [target]；[from] 为起播位置，必须由调用方显式
  /// 给出——动画启动的同一帧内拖动标志 / widget.open 都可能已切换，
  /// 从状态反推起点会拿到旧状态位或新目标位，导致画面先弹回再重播。
  void _animateTo(double target, {required double from}) {
    final start = from;
    final seq = ++_snapSeq;
    if ((start - target).abs() < 0.5) {
      _snapAnim = null;
      _controller.value = 1;
      // 对齐无动画路径的状态同步（如外部要求展开但已在展开位）。
      final willOpen = target == _openOffset;
      if (widget.open != willOpen) widget.onOpenChanged(willOpen);
      return;
    }
    _snapAnim = Tween<Offset>(
      begin: Offset(start, 0),
      end: Offset(target, 0),
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOut));
    _controller
      ..stop()
      ..forward(from: 0).whenCompleteOrCancel(() {
        // 吸附落位：仅当本次仍是最新动画时同步，避免被打断的旧
        // 动画回传过期开合状态（取消也会触发本回调）。
        if (!mounted || seq != _snapSeq) return;
        final willOpen = target == _openOffset;
        if (widget.open != willOpen) {
          Haptics.tick();
          widget.onOpenChanged(willOpen);
        }
      });
  }

  void _onDragStart(DragStartDetails _) {
    // 必须在置起拖动标志之前抓住当前呈现位置：_dragging=true 后
    // _currentOffset 改读 _dragOffset（上一次松手时的旧值，未必等于
    // 吸附终态），先置标志再赋值等于自赋值——再次拖动的首帧会从
    // 终态瞬间跳回上一次松手位置，表现为「弹回旧状态再播」。
    final from = _currentOffset;
    _dragging = true;
    // 作废任何在途吸附动画的完成回调。
    _snapSeq++;
    _snapAnim = null;
    _controller.stop();
    _dragOffset = from;
  }

  void _onDragUpdate(DragUpdateDetails details) {
    // 全关后只允许向左；全开后可继续向左的余量夹死。
    final next = (_dragOffset + details.delta.dx).clamp(
      _openOffset,
      _closedOffset,
    );
    setState(() => _dragOffset = next);
  }

  void _onDragEnd(DragEndDetails details) {
    // 必须先抓住手指离开的位置再起播：_dragging 置 false 后
    // _currentOffset 会回退到 widget.open 的旧静止位（0 或全开位），
    // 从那里起播就会出现「先弹回旧状态、再重新吸附」的穿帮。
    final from = _dragOffset;
    _dragging = false;
    // 快速甩动按方向决定，否则按半程吸附。
    final velocity = details.velocity.pixelsPerSecond.dx;
    final bool willOpen;
    if (velocity.abs() > 300) {
      willOpen = velocity < 0;
    } else {
      willOpen = from < _openOffset / 2;
    }
    final target = willOpen ? _openOffset : _closedOffset;
    _animateTo(target, from: from);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final offset = _currentOffset;
    return Stack(
      children: [
        // 操作区：右对齐铺满行高，始终在树中（左滑跟手时要即时露出）。
        // 机能风实验期行前景透明，遮挡方式从「前景不透明实底」改为
        // 「按前景实时偏移裁剪操作区」：ClipRect 全尺寸裁剪，内部右对齐
        // 的可见窗口宽度恒等于已露出宽度（0 ~ actionWidth）；
        // OverflowBox 让按钮 Row 始终以 actionWidth 完整布局、右贴窗口，
        // 窗口外部分被 ClipRect 裁掉且不参与 hit test。
        // （不能用 Align(widthFactor) 收窄：Positioned.fill 是紧约束，
        // widthFactor 在紧约束下被忽略，会导致收起态按钮整排穿出。）
        Positioned.fill(
          child: ExcludeSemantics(
            excluding: offset == _closedOffset,
            child: ClipRect(
              child: Align(
                alignment: Alignment.centerRight,
                child: SizedBox(
                  width: (-offset).clamp(0.0, widget.actionWidth),
                  height: double.infinity,
                  child: OverflowBox(
                    alignment: Alignment.centerRight,
                    minWidth: widget.actionWidth,
                    maxWidth: widget.actionWidth,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      // stretch：让操作按钮填满整行高度。
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: widget.actions,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
        // 前景：跟手平移；展开时点前景只负责收回，收起时才触发
        // 行自身的 onTap（标记已读）。
        Positioned.fill(
          left: offset,
          right: -offset,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onHorizontalDragStart: _onDragStart,
            onHorizontalDragUpdate: _onDragUpdate,
            onHorizontalDragEnd: _onDragEnd,
            onTap: () {
              if (widget.open) {
                widget.onOpenChanged(false);
              } else {
                widget.onTap?.call();
              }
            },
            child: widget.child,
          ),
        ),
      ],
    );
  }
}
