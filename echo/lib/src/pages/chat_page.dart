import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

/// 聊天页（页面化第一步：会话列表骨架）。
///
/// **没有标题栏**：整页就是一条纵向会话列表，铺满导航页面轨道
/// 分配的整块屏幕，最大化可用画面。状态栏安全区作为列表顶部
/// 内边距；底部悬浮着把手 / AI / 导航三条停靠条，故列表底部
/// 预留等高内边距，使最后一行能滚到停靠条之上而不被永久遮挡。
///
/// 当前 [conversationCount] 个会话行全部是**空白占位行**：
/// 只有统一行高与一条 tone1 细分隔线（与 AI 对话框顶部分隔线
/// 同一视觉语言）。头像、名称、最新消息、时间等内容后续在
/// [ChatListRow] 内逐个填充。
class ChatPage extends StatelessWidget {
  const ChatPage({super.key});

  /// 占位会话行数。
  ///
  /// 脚手架阶段写死为 30，接入会话数据源后本行常量随之移除、
  /// 行数改由列表数据驱动。
  static const int conversationCount = 30;

  /// 会话行统一高度。
  ///
  /// 按后续承载「头像 + 名称 / 最新消息两行文案」的典型会话行
  /// 规格预留；当前空白行也保持该高度，便于先确认列表节奏。
  static const double rowHeight = 72;

  /// 底部为悬浮停靠三条预留的高度：底边距 16 + 条高 10。
  ///
  /// 数值对齐 navigation 层的 `DockGeometry.bottomMargin + barHeight`。
  /// 页面层不反向依赖 navigation 层（依赖方向是导航持有页面），
  /// 故此处按页面自身所需的避让高度就近定义；停靠几何调整时需
  /// 同步检查本常量。
  static const double _dockReservedHeight = 26;

  @override
  Widget build(BuildContext context) {
    final safePadding = MediaQuery.paddingOf(context);

    return ListView.builder(
      key: const ValueKey<String>('chat-page-list'),
      itemExtent: rowHeight,
      itemCount: conversationCount,
      // 安全区与停靠条避让走列表内边距而非外包 SafeArea/SizedBox：
      // 列表本身始终铺满全屏，滚动时内容可从停靠条下方穿过。
      padding: EdgeInsets.only(
        top: safePadding.top,
        bottom: safePadding.bottom + _dockReservedHeight,
      ),
      itemBuilder: (context, index) {
        // 稳定 key：当前 30 行内容完全相同，接入真实数据（头像/
        // 未读态/滑动操作等）后用于保持各行渲染对象身份。
        return ChatListRow(key: ValueKey<String>('chat-row-$index'));
      },
    );
  }
}

/// 一个空白会话列表行。
///
/// 当前只在底部绘制一条 tone1 细分隔线，无任何内容，也不响应
/// 点击——没有可触发的行为，故不挂手势（不构成「死按钮」）。
/// 后续在此填充头像 / 名称 / 最新消息 / 时间，并接入点击进入会话。
class ChatListRow extends StatelessWidget {
  const ChatListRow({super.key});

  @override
  Widget build(BuildContext context) {
    return const DecoratedBox(
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: AppColors.tone1)),
      ),
    );
  }
}
