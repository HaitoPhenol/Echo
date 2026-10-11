/// 导航目的地的纯数据配置（不依赖任何 widget）。
///
/// ECP 控制层运行在 widget 树之外（adb 广播 / 未来 slash、MCP），
/// 不能 import 带 [NavDestination.pageBuilder] 的 UI 配置，故页名与
/// 顺序在此声明为唯一来源；[nav_destination.dart] 的 UI 配置从此读取，
/// `nav.page` / `nav.goto` 命令也从此解析，杜绝两处各写一份页名。
const List<({String id, String label})> kNavDestinationSpecs = [
  (id: 'console', label: '终端'),
  (id: 'chat', label: '聊天'),
  (id: 'notes', label: '笔记'),
  (id: 'me', label: '主页'),
];
