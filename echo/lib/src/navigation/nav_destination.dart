import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/material.dart';

import '../pages/chat_page.dart';
import '../pages/debug_badge_controls.dart';
import '../pages/template_page.dart';

/// 一个导航目的地（即胶囊导航线上可到达的一页）。
///
/// 页面的所有信息集中在本类中描述，导航屏、滚筒指示器、搜索服务
/// 都从同一份配置读取，避免各处分别硬编码：
/// - [id]：程序内稳定标识，代码逻辑引用页面时永远用它，不依赖序号；
/// - [label]：页面名称，用于页名标签与搜索结果；
/// - [icon]：滚筒页标与搜索结果图标。模板阶段为 null，
///   滚筒暂以数字序号代替，填入图标后自动切换为图标；
/// - [pageBuilder]：页面本体的构建器，实现按需构建。
class NavDestination {
  const NavDestination({
    required this.id,
    required this.label,
    required this.pageBuilder,
    this.icon,
  });

  /// 程序内稳定 id（如 'chat'），不随页面顺序变化。
  final String id;

  /// 页面显示名称（如「聊天」）。
  final String label;

  /// 页面图标。null 时滚筒显示数字序号（模板阶段）。
  final IconData? icon;

  /// 页面本体构建器。
  final WidgetBuilder pageBuilder;
}

/// 构建默认导航配置（当前 4 个页面，顺序即导航轨道顺序）。
///
/// 聊天页已替换为真实页面 [ChatPage]（无标题栏的会话列表骨架）；
/// 其余三页暂时仍是只显示标题的 [TemplatePage]，后续逐个替换。
///
/// 新增页面的标准做法：在本列表末尾（或合适位置）增加一个
/// [NavDestination]，导航线、滚筒、搜索会自动纳入，无需改动其他代码。
List<NavDestination> buildDefaultDestinations() {
  /// (id, 标题) 列表。
  const specs = <(String, String)>[
    ('console', '控制台'),
    ('chat', '聊天'),
    ('notes', '日志'),
    ('me', '我'),
  ];

  return [
    for (final (id, label) in specs)
      NavDestination(
        id: id,
        label: label,
        icon: null, // TODO: 各页面定型后在此填入图标
        // 聊天页已进入真实页面开发（无标题栏的会话列表骨架）。
        pageBuilder: (_) => switch (id) {
          'chat' => const ChatPage(),
          // 控制台/日志页挂测试按钮（锚点通知验收用，正式功能接入后移除）。
          // kDebugMode 守卫：debug 构建可见，release/profile 构建 footer 为
          // null，调试组件随树摇移除，不会进入发布包。
          _ => TemplatePage(
            title: label,
            // 机能风模板页分区小标题（编号与轨道顺序一致）。
            secCode: switch (id) {
              'console' => 'SEC.01',
              'notes' => 'SEC.03',
              'me' => 'SEC.04',
              _ => null,
            },
            secName: switch (id) {
              'console' => 'CONSOLE',
              'notes' => 'LOGS',
              'me' => 'ME',
              _ => null,
            },
            footer: kDebugMode
                ? switch (id) {
                    'console' => const ConsoleBadgeControls(),
                    'notes' => const LogBadgeControls(),
                    _ => null,
                  }
                : null,
          ),
        },
      ),
  ];
}
