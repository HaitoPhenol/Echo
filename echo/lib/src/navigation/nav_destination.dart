import 'package:flutter/material.dart';

import '../services/search_service.dart';

/// 页面构造器抽象：导航配置只描述「如何构建页面」，具体页面实现
/// 由装配根（`app/app_services.dart`）绑定。
typedef NavPageBuilder = Widget Function(BuildContext context);

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

  /// 页面本体构建器（装配根绑定具体页面）。
  final NavPageBuilder pageBuilder;
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
