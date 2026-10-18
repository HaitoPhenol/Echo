import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/material.dart';

import 'nav_destination_specs.dart';

import '../diary/data/diary_repository.dart';
import '../diary/ui/diary_page.dart';
import '../pages/chat_page.dart';
import '../pages/debug_badge_controls.dart';
import '../pages/template_page.dart';
import '../services/search_service.dart';

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

/// 在导航目的地中搜索的数据源（当前唯一已接入的数据源）。
///
/// 让「搜索页面」形成真实闭环：输入页面名 → 得到结果 →
/// 点击结果直接跳转到对应页面。
class NavDestinationSearchProvider implements SearchProvider {
  NavDestinationSearchProvider({
    required this.destinations,
    required this.onDestinationSelected,
  });

  /// 全部导航目的地。
  final List<NavDestination> destinations;

  /// 选中某目的地时回调，参数为其在导航中的序号。
  final ValueChanged<int> onDestinationSelected;

  @override
  String get id => 'destinations';

  @override
  List<SearchResult> search(String query) {
    final keyword = query.trim();
    if (keyword.isEmpty) return const [];

    return [
      for (var i = 0; i < destinations.length; i++)
        if (destinations[i].label.contains(keyword))
          SearchResult(
            title: destinations[i].label,
            subtitle: '页面',
            icon: destinations[i].icon,
            onSelect: () => onDestinationSelected(i),
          ),
    ];
  }
}

/// 构建默认导航配置（当前 4 个页面，顺序即导航轨道顺序）。
///
/// 聊天页已替换为真实页面 [ChatPage]（无标题栏的会话列表骨架）；
/// 其余三页暂时仍是只显示标题的 [TemplatePage]，后续逐个替换。
///
/// 新增页面的标准做法：在本列表末尾（或合适位置）增加一个
/// [NavDestination]，导航线、滚筒、搜索会自动纳入，无需改动其他代码。
List<NavDestination> buildDefaultDestinations({
  /// 测试注入缝：注入后笔记页跳过生产持久仓储开库（widget 测试的
  /// fake-async 区无法完成真实文件 I/O）；生产环境传 null。
  DiaryRepository? diaryRepository,

  /// 导航屏持有的日记页 State key：把手竖单「今日日记」快捷入口据此调用
  /// [DiaryPageState.openTodayEditor]。
  GlobalKey<DiaryPageState>? diaryPageKey,
}) {
  /// (id, 标题) 列表：唯一来源在 [kNavDestinationSpecs]（控制层共用）。
  const specs = kNavDestinationSpecs;

  return [
    for (final spec in specs)
      NavDestination(
        id: spec.id,
        label: spec.label,
        icon: null, // TODO: 各页面定型后在此填入图标
        // 聊天页已进入真实页面开发（无标题栏的会话列表骨架）。
        // 笔记页 M2 起承载日记模块：年→月→日层级 + 块编辑器。
        pageBuilder: (_) => switch (spec.id) {
          'chat' => const ChatPage(),
          // 生产环境（无测试注入仓储）开屏预进今日日记编辑页：app 一启动
          // 日记页就在轨道上离屏 bootstrap，先把今日编辑页压进内层栈，
          // 用户横滑到笔记页即见今日日记，无需再点 年→月→日。
          // 测试注入仓储时关闭，保持从年列表开始的既有断言基线。
          'notes' => DiaryPage(
            key: diaryPageKey,
            repository: diaryRepository,
            preEnterToday: diaryRepository == null,
          ),
          // 仅终端页挂锚点调试面板（新消息/异常模拟与处理，验收用，
          // 正式功能接入后移除）；主页暂不做功能，footer 为 null。
          // kDebugMode 守卫：debug 构建可见，release/profile 构建 footer 为
          // null，调试组件随树摇移除，不会进入发布包。
          _ => TemplatePage(
            title: spec.label,
            // 机能风模板页分区小标题（编号与轨道顺序一致）。
            secCode: switch (spec.id) {
              'console' => 'SEC.01',
              'notes' => 'SEC.03',
              'me' => 'SEC.04',
              _ => null,
            },
            secName: switch (spec.id) {
              'console' => 'CONSOLE',
              'notes' => 'NOTES',
              'me' => 'ME',
              _ => null,
            },
            footer: kDebugMode && spec.id == 'console'
                ? ConsoleBadgeControls(consolePageId: spec.id)
                : null,
          ),
        },
      ),
  ];
}
