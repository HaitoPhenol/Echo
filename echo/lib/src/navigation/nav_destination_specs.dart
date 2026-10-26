/// 导航目的地的纯数据配置（不依赖任何 widget）。
///
/// ECP 控制层运行在 widget 树之外（adb 广播 / 未来 slash、MCP），
/// 不能 import 带 [NavDestination.pageBuilder] 的 UI 配置，故页名与
/// 顺序在此声明为唯一来源；[nav_destination.dart] 的 UI 配置从此读取，
/// `nav.page` / `nav.goto` 命令也从此解析，杜绝两处各写一份页名。
const List<({String id, String label})> kNavDestinationSpecs = [
  (id: 'me', label: '主页'),
  (id: 'chat', label: '聊天'),
  (id: 'notes', label: '笔记'),
  (id: 'console', label: '终端'),
];

/// 解析 `--page` 入参为页下标：先匹配稳定 id，再尝试 0..pageCount-1
/// 下标；都不匹配返回 null（调用方据此抛 USAGE）。
///
/// nav 与 badge 两个命名空间共用同一解析，杜绝两份页名漂移。
int? resolveNavPageIndex(String raw, int pageCount) {
  final byId = kNavDestinationSpecs
      .indexWhere((s) => s.id == raw)
      .clamp(-1, pageCount - 1);
  if (byId >= 0) return byId;
  final asIndex = int.tryParse(raw);
  if (asIndex != null && asIndex >= 0 && asIndex < pageCount) return asIndex;
  return null;
}

/// 页下标 → 稳定页名；越界返回 `unknown`（nav.page 容错用）。
String navPageName(int index) =>
    index >= 0 && index < kNavDestinationSpecs.length
    ? kNavDestinationSpecs[index].id
    : 'unknown';
