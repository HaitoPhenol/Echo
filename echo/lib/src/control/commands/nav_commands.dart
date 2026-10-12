import '../../navigation/nav_destination_specs.dart';
import '../../navigation/nav_physics.dart';
import '../protocol/command_spec.dart';
import '../protocol/control_error.dart';

/// `nav` 命名空间：当前页查询与编程式翻页（手册 §4）。
///
/// 同路原则：`nav.goto` 只调横滑手势同一个 [NavPhysicsController.snapTo]，
/// 带动画落位，不另造「控制专用跳转」。
List<CommandSpec> buildNavCommands() => [
  CommandSpec(
    namespace: 'nav',
    verb: 'page',
    summary: '当前导航页（下标 + 稳定页名）',
    kind: CommandKind.read,
    level: ControlLevel.guest,
    handler: (ctx) async {
      final nav = ctx.requireService<NavPhysicsController>('导航控制器');
      final index = nav.activePage;
      return {'index': index, 'name': navPageName(index)};
    },
  ),
  CommandSpec(
    namespace: 'nav',
    verb: 'goto',
    summary: '带动画翻到指定页（与横滑手势同路径）',
    kind: CommandKind.write,
    level: ControlLevel.user,
    params: [
      ParamSpec(
        'page',
        type: ArgType.string,
        required: true,
        summary: '稳定页名 console/chat/notes/me 或下标 0..3',
      ),
    ],
    handler: (ctx) async {
      final nav = ctx.requireService<NavPhysicsController>('导航控制器');
      final from = nav.activePage;
      final raw = ctx.arg<String>('page');
      final target = resolveNavPageIndex(raw, nav.pageCount);
      if (target == null) {
        throw ControlException(
          ControlErrorCode.usage,
          '未知页：$raw（可用：${kNavDestinationSpecs.map((s) => s.id).join('/')}'
          ' 或 0..${nav.pageCount - 1}）',
        );
      }
      if (target != nav.activePage) {
        nav.snapTo(target);
      }
      return {
        'from': {'index': from, 'name': navPageName(from)},
        'to': {'index': target, 'name': navPageName(target)},
        // 防抖未落盘的提示由日记 bootstrap 接线后填充；
        // P1 恒为空数组，保留键位以冻结契约。
        'warnings': <String>[],
      };
    },
  ),
];
