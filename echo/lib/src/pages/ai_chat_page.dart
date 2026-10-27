import 'package:flutter/material.dart';

import '../ai/ai_chat_controller.dart';
import '../ai/ui/ai_chat_panel.dart';
import '../theme/app_colors.dart';
import 'chat_page.dart';

/// AI 对话视图（聊天页「AI 助手」行点入后在页内展开的整屏形态）。
///
/// 由 [ChatPage] 在自身页面里承载（不压路由），因此导航屏的机能风
/// 背景纹理天然透上来，返回也走页内切换。
///
/// 与 AI 条长按弹出的对话框共用同一份 [AiChatController] 与聊天仓储：
/// 这里发出去的消息，对话框里立刻可见；反之亦然。
///
/// 布局：无系统标题栏，顶部一行 48px 自绘返回键 + 标题 + 最近用量；
/// 中间消息流、底部输入行，安全区由 [SafeArea] 承担，键盘避让交给
/// 本页的 Scaffold（导航屏根 Scaffold 关闭了自动避让）。
class AiChatPage extends StatefulWidget {
  const AiChatPage({super.key, this.onBack});

  /// 返回回调；为 null 时退回当前路由（独立压栈的场景）。
  final VoidCallback? onBack;

  /// 顶部标题。
  static const String title = 'AI 助手';

  /// 顶部栏高度。
  static const double headerHeight = 48;

  /// 左右与输入行的共同边距。
  static const double horizontalPadding = 14;

  @override
  State<AiChatPage> createState() => _AiChatPageState();
}

class _AiChatPageState extends State<AiChatPage> {
  @override
  Widget build(BuildContext context) {
    final chat = AiChatScope.of(context);
    final usage = chat.lastUsage;
    // 键盘弹起时：页面轨道已整体上垫了 keyboardInset（导航屏统一补偿），
    // 本页不能再让 Scaffold 避让一次，否则输入行被推高整整一个键盘高度。
    final keyboardOpen = MediaQuery.viewInsetsOf(context).bottom > 0;

    return Scaffold(
      // 透明底：让导航屏的机能风背景纹理透上来，
      // 与会话列表行同一种视觉基底。
      backgroundColor: Colors.transparent,
      resizeToAvoidBottomInset: false,
      body: SafeArea(
        child: Column(
          children: [
            SizedBox(
              height: AiChatPage.headerHeight,
              child: Row(
                children: [
                  const SizedBox(width: 4),
                  IconButton(
                    tooltip: '返回',
                    onPressed:
                        widget.onBack ?? () => Navigator.of(context).maybePop(),
                    icon: const Icon(
                      Icons.arrow_back_ios_new,
                      size: 18,
                      color: AppColors.textMuted,
                    ),
                  ),
                  Expanded(
                    child: Text(
                      AiChatPage.title,
                      style: const TextStyle(
                        fontSize: 16,
                        color: AppColors.textPrimary,
                      ),
                    ),
                  ),
                  if (usage != null && !usage.isEmpty)
                    Padding(
                      padding: const EdgeInsets.only(right: 16),
                      child: Text(
                        usage.label,
                        style: const TextStyle(
                          fontSize: 11,
                          color: AppColors.textMuted,
                        ),
                      ),
                    ),
                ],
              ),
            ),
            const Expanded(
              child: AiChatTranscript(
                showUsage: false,
                padding: EdgeInsets.fromLTRB(
                  AiChatPage.horizontalPadding,
                  6,
                  AiChatPage.horizontalPadding,
                  8,
                ),
              ),
            ),
            AiChatComposer(
              hintText: '发消息…',
              // 键盘收起时让出悬浮停靠三条的高度，避免被停靠条压住；
              // 键盘弹起时停靠条已被键盘盖住，只留输入行自身间距贴住上沿。
              padding: EdgeInsets.fromLTRB(
                AiChatPage.horizontalPadding,
                6,
                AiChatPage.horizontalPadding,
                keyboardOpen ? 10 : 10 + ChatPage.dockReservedHeight,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
