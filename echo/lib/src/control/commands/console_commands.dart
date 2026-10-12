import '../../services/console_stats_service.dart';
import '../protocol/command_spec.dart';
import 'control_json.dart';

/// `console` 命名空间：机能风读数条快照与立即刷新（手册 §7，P2）。
///
/// 同路原则：`console.refresh`、5 秒定时器与 UI 读数条共用同一个
/// [ConsoleStatsService.refresh]；`console.snapshot` 只读最近一次
/// 快照，不另打通道。
List<CommandSpec> buildConsoleCommands() => [consoleSnapshot, consoleRefresh];

/// `console.snapshot`：最近一次读数（不触发通道调用）。
final CommandSpec consoleSnapshot = CommandSpec(
  namespace: 'console',
  verb: 'snapshot',
  summary: '读数条当前快照（型号/温度/功耗）',
  kind: CommandKind.read,
  level: ControlLevel.owner,
  handler: (ctx) async {
    final stats = ctx.requireService<ConsoleStatsService>('读数服务');
    return consoleSnapshotJson(stats.snapshot);
  },
);

/// `console.refresh`：立即刷新并返回刷新后的快照。
final CommandSpec consoleRefresh = CommandSpec(
  namespace: 'console',
  verb: 'refresh',
  summary: '立即拉取一次设备读数并返回新快照',
  kind: CommandKind.write,
  level: ControlLevel.user,
  handler: (ctx) async {
    final stats = ctx.requireService<ConsoleStatsService>('读数服务');
    final snapshot = await stats.refresh();
    return consoleSnapshotJson(snapshot);
  },
);
