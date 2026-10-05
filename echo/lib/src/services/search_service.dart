import 'dart:async';

import 'package:flutter/material.dart';

import '../navigation/nav_destination.dart';

// ====================================================================
//  数据模型
// ====================================================================

/// 一条搜索结果。
///
/// - [title]：主标题；
/// - [subtitle]：副标题/来源分类（如「页面」「联系人」），可为 null；
/// - [icon]：结果图标；
/// - [onSelect]：点击结果时执行（导航、打开文件等）。
class SearchResult {
  const SearchResult({
    required this.title,
    required this.onSelect,
    this.subtitle,
    this.icon,
  });

  /// 结果主标题。
  final String title;

  /// 副标题 / 来源分类。
  final String? subtitle;

  /// 结果图标。
  final IconData? icon;

  /// 点击结果时的行为。
  final VoidCallback onSelect;
}

// ====================================================================
//  搜索数据源接口
// ====================================================================

/// 搜索数据源的统一接口。
///
/// 每一类可搜索内容（页面、联系人、聊天记录、文件……）实现一个
/// provider 注册到 [SearchService]，搜索时各 provider 并行提供结果。
///
/// 接入新数据源的步骤：
/// 1. 实现本接口；
/// 2. 在创建 SearchService 时加入 providers 列表。
/// 无需改动搜索界面。
abstract class SearchProvider {
  /// 数据源标识（调试与结果分类用）。
  String get id;

  /// 根据关键词返回本数据源的匹配结果。
  ///
  /// 本地数据同步返回即可；需要网络/数据库时可在实现内做异步，
  /// 届时由 SearchService 统一 await（当前版本保持同步以简化调用）。
  List<SearchResult> search(String query);
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

// ====================================================================
//  搜索历史接口
// ====================================================================

/// 最近搜索历史的存储接口。
///
/// UI 只依赖本抽象，当前实现为内存版 [InMemorySearchHistoryStore]；
/// 后续需要持久化时新写一个实现（如基于 shared_preferences 或数据库）
/// 替换即可，界面与 SearchService 无需改动。
abstract class SearchHistoryStore {
  /// 历史条目（最近的在前）。
  List<String> get items;

  /// 新增一条历史（已存在则提到最前）。
  Future<void> add(String query);

  /// 删除一条历史。
  Future<void> remove(String query);
}

/// 内存版历史存储：进程重启后清空，仅供开发阶段。
class InMemorySearchHistoryStore implements SearchHistoryStore {
  // 私有字段无法直接使用公开命名参数的初始化形式（this._xx），
  // 故在此显式忽略 prefer_initializing_formals。
  // ignore: prefer_initializing_formals
  InMemorySearchHistoryStore({int maxItems = 10}) : _maxItems = maxItems;

  /// 最多保留的历史条数。
  final int _maxItems;
  final List<String> _items = [];

  @override
  List<String> get items => List.unmodifiable(_items);

  @override
  Future<void> add(String query) async {
    final text = query.trim();
    if (text.isEmpty) return;
    _items.remove(text);
    _items.insert(0, text);
    if (_items.length > _maxItems) {
      _items.removeRange(_maxItems, _items.length);
    }
  }

  @override
  Future<void> remove(String query) async {
    _items.remove(query);
  }
}

// ====================================================================
//  搜索服务（聚合入口）
// ====================================================================

/// 搜索服务：聚合全部 [SearchProvider]，并持有历史存储。
///
/// 界面层只与本类打交道，不关心数据来自哪些数据源。
class SearchService {
  SearchService({
    required this.providers,
    required this.history,
  });

  /// 已注册的全部数据源。
  final List<SearchProvider> providers;

  /// 历史存储。
  final SearchHistoryStore history;

  /// 跨全部数据源执行搜索，按 provider 注册顺序汇总结果。
  List<SearchResult> searchAll(String query) {
    if (query.trim().isEmpty) return const [];
    return providers
        .expand((provider) => provider.search(query))
        .toList(growable: false);
  }
}
