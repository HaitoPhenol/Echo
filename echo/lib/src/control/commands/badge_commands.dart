import '../../navigation/nav_destination_specs.dart';
import '../../services/nav_badge_service.dart';
import '../protocol/command_spec.dart';
import '../protocol/control_error.dart';

/// `badge` 命名空间：导航锚点状态查询与上报（手册 §8，P2）。
///
/// 全部命令直接调 [NavBadgeService] 公共接口，不复制状态机：
/// 通知态可被 view 清除、异常态必须显式 resolve 的规则由服务层保有。
/// `--page` 解析与 nav 域同源（[resolveNavPageIndex]）。
List<CommandSpec> buildBadgeCommands() => [
  badgeStatus,
  _badgeWrite(
    verb: 'notify',
    summary: '上报通知态（锚点变绿呼吸）',
    apply: (s, p) => s.postNotification(p),
  ),
  _badgeWrite(
    verb: 'exception',
    summary: '上报异常态（锚点变红闪烁）',
    apply: (s, p) => s.reportException(p),
  ),
  _badgeWrite(
    verb: 'view',
    summary: '页面被查看（通知态恢复，异常态不变）',
    apply: (s, p) => s.markViewed(p),
  ),
  _badgeWrite(
    verb: 'resolve',
    summary: '异常处理完成（异常态恢复）',
    apply: (s, p) => s.resolveException(p),
  ),
];

/// `badge.status`：四个导航页的锚点级别一览。
final CommandSpec badgeStatus = CommandSpec(
  namespace: 'badge',
  verb: 'status',
  summary: '各导航页锚点级别一览',
  kind: CommandKind.read,
  level: ControlLevel.owner,
  handler: (ctx) async {
    final badges = ctx.requireService<NavBadgeService>('导航锚点服务');
    return {
      'items': [
        for (var i = 0; i < kNavDestinationSpecs.length; i++)
          {
            'index': i,
            'name': navPageName(i),
            'level': badges.levelOf(kNavDestinationSpecs[i].id).name,
          },
      ],
    };
  },
);

/// 四个 badge 写命令共用同一骨架：解析页 → 调服务接口 → 回读操作后
/// 级别（view/resolve 对不适用的状态是幂等空操作，回读值让调用方
/// 直接断言实际结果）。
CommandSpec _badgeWrite({
  required String verb,
  required String summary,
  required void Function(NavBadgeService service, String destinationId) apply,
}) => CommandSpec(
  namespace: 'badge',
  verb: verb,
  summary: summary,
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
    final badges = ctx.requireService<NavBadgeService>('导航锚点服务');
    final raw = ctx.arg<String>('page');
    final page = resolveNavPageIndex(raw, kNavDestinationSpecs.length);
    if (page == null) {
      throw ControlException(
        ControlErrorCode.usage,
        '未知页：$raw（可用：'
        '${kNavDestinationSpecs.map((s) => s.id).join('/')}）',
      );
    }
    // 入参仍接受稳定页名或下标；服务层按稳定 id 索引。
    final destinationId = kNavDestinationSpecs[page].id;
    apply(badges, destinationId);
    return {
      'page': {'index': page, 'name': navPageName(page)},
      'level': badges.levelOf(destinationId).name,
    };
  },
);
