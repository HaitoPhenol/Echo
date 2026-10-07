import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

/// 聊天页（页面化第一步：会话列表骨架）。
///
/// **没有标题栏**：整页就是一条纵向会话列表，铺满导航页面轨道
/// 分配的整块屏幕，最大化可用画面。状态栏安全区作为列表顶部
/// 内边距；底部悬浮着把手 / AI / 导航三条停靠条，故列表底部
/// 预留等高内边距，使最后一行能滚到停靠条之上而不被永久遮挡。
///
/// 当前 [conversationCount] 个会话行是脚手架占位行：每行包含
/// 圆形头像框（空白）、昵称、消息预览三个槽位，文案全部相同，
/// 另有一条 tone1 细分隔线（与 AI 对话框顶部分隔线同一视觉
/// 语言）。接入会话数据源后，行内容改由数据驱动、占位文案移除。
class ChatPage extends StatelessWidget {
  const ChatPage({super.key});

  /// 占位会话行数。
  ///
  /// 脚手架阶段写死为 30，接入会话数据源后本常量随之移除、
  /// 行数改由列表数据驱动。
  static const int conversationCount = 30;

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

  /// 昵称占位文案。
  static const String placeholderNickname = '昵称';

  /// 消息预览占位文案。
  static const String placeholderPreview = '消息预览…';

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
        return ChatListRow(
          key: ValueKey<String>('chat-row-$index'),
          nickname: placeholderNickname,
          preview: placeholderPreview,
        );
      },
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

/// 一个会话列表行（脚手架阶段）。
///
/// 布局：左侧圆形头像框 [ChatAvatar]，右侧上为昵称、下为消息预览
/// 两行文案（均单行省略）；底部分隔线与文案列左边对齐
/// （从头像右侧开始，不贯通屏幕左缘）。当前不响应点击——没有
/// 可触发的行为，故不挂手势（不构成「死按钮」），后续接入点击
/// 进入会话与未读态/时间等元素。
class ChatListRow extends StatelessWidget {
  const ChatListRow({super.key, required this.nickname, required this.preview});

  /// 会话昵称。
  final String nickname;

  /// 最新一条消息的预览文案。
  final String preview;

  @override
  Widget build(BuildContext context) {
    return Column(
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
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        nickname,
                        style: _nicknameStyle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: ChatPage.textLineGap),
                      Text(
                        preview,
                        style: _previewStyle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        // 分隔线从文案列左缘起：屏边距 + 头像 + 头像文案间距。
        Padding(
          padding: const EdgeInsets.only(
            left:
                ChatPage.rowHorizontalPadding +
                ChatPage.avatarSize +
                ChatPage.avatarTextGap,
            right: ChatPage.rowHorizontalPadding,
          ),
          child: const SizedBox(
            height: 1,
            child: ColoredBox(color: AppColors.tone1),
          ),
        ),
      ],
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
