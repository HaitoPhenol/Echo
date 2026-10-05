import 'package:flutter/material.dart';

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

/// 构建默认导航配置。
///
/// 名称顺序沿用原型（聊天/通讯录/…/文件），但页面本体暂时
/// 全部是只显示数字的 [TemplatePage]，后续逐个替换为真实页面。
///
/// 新增页面的标准做法：在本列表末尾（或合适位置）增加一个
/// [NavDestination]，导航线、滚筒、搜索会自动纳入，无需改动其他代码。
List<NavDestination> buildDefaultDestinations() {
  const labels = [
    '聊天',
    '通讯录',
    '动态',
    '收藏',
    '设置',
    '相机',
    '游戏',
    '钱包',
    '音乐',
    '文件',
  ];

  return [
    for (var i = 0; i < labels.length; i++)
      NavDestination(
        id: 'page-${i + 1}',
        label: labels[i],
        icon: null, // TODO: 各页面定型后在此填入图标
        pageBuilder: (_) => TemplatePage(index: i),
      ),
  ];
}
