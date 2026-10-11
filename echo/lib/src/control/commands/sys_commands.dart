import 'dart:io' show pid;

import '../../diary/data/diary_clock.dart';
import '../../diary/data/diary_repository.dart';
import '../../navigation/nav_destination_specs.dart';
import '../../navigation/nav_physics.dart';
import '../auth/audit_log.dart';
import '../control_app_state.dart';
import '../control_registry.dart';
import '../protocol/command_spec.dart';
import '../protocol/control_error.dart';
import 'control_json.dart';

/// `sys` 命名空间：链路自检、清单帮助、设备版本、App 现场、
/// 审计流水与（debug）日记日时钟拨钟（手册 §2）。
///
/// 全部为读命令，除 [sysClockSet]——后者 debug-only 且只覆盖
/// [DiaryClock] 的进程内注入值，不触碰系统时间。
List<CommandSpec> buildSysCommands() => [
      CommandSpec(
        namespace: 'sys',
        verb: 'ping',
        summary: '链路自检：返回存活、当前时间与进程 pid',
        kind: CommandKind.read,
        level: ControlLevel.guest,
        handler: (_) async => {
          'alive': true,
          // 这里是墙钟时间：ping 语义就是「设备现在几点」，不走日记时钟。
          'time': isoDateTime(DateTime.now()),
          'pid': pid,
        },
      ),
      CommandSpec(
        namespace: 'sys',
        verb: 'help',
        summary: '列出当前通道可见命令，或用 --command 看单条完整说明',
        kind: CommandKind.read,
        level: ControlLevel.guest,
        params: [
          ParamSpec('command',
              type: ArgType.string,
              summary: '限定单条命令的全名，如 diary.list'),
        ],
        handler: (ctx) async {
          final only = ctx.optionalArg<String>('command');
          if (only != null) {
            final spec = ctx.bus.visibleSpecs
                .where((s) => s.name == only)
                .cast<CommandSpec?>()
                .firstWhere((_) => true, orElse: () => null);
            if (spec == null) {
              throw ControlException(
                ControlErrorCode.notFound,
                '没有这条命令：$only',
              );
            }
            return spec.toHelp(detailed: true);
          }
          return {
            'commands': ctx.bus.visibleSpecs
                .map((s) => s.toHelp())
                .toList(growable: false),
          };
        },
      ),
      CommandSpec(
        namespace: 'sys',
        verb: 'info',
        summary: '版本/构建风味/设备信息（不含任何用户数据）',
        kind: CommandKind.read,
        level: ControlLevel.guest,
        handler: (ctx) async {
          final result = <String, Object?>{
            // flavor 以实际运行的总线构建模式为准（release 包里
            // debug-only 命令物理不存在）。
            'flavor': ctx.bus.buildMode.name,
            'channel': ctx.channel.wire,
          };
          final deviceInfo = ctx.service<ControlDeviceInfo>();
          if (deviceInfo != null) {
            result.addAll(await deviceInfo.fetchSnapshot());
          }
          return result;
        },
      ),
      CommandSpec(
        namespace: 'sys',
        verb: 'status',
        summary: 'App 前后台状态、当前导航页、日记仓储就绪概况',
        kind: CommandKind.read,
        level: ControlLevel.owner,
        handler: (ctx) async {
          final appState = ctx.service<ControlAppState>();
          final nav = ctx.service<NavPhysicsController>();
          final repo = ctx.service<DiaryRepository>();
          final paths = ctx.service<ControlPaths>();
          final clock = ctx.service<DiaryClock>();

          final result = <String, Object?>{
            'lifecycle': appState?.lifecycle ?? 'unknown',
            'services': <String, Object?>{
              'nav': nav != null,
              'diary': repo != null && clock != null,
            },
          };

          if (nav != null) {
            result['nav'] = {
              'index': nav.activePage,
              // 页名从纯数据配置解析（与 UI 同源，不 import widget）。
              'page': _navName(nav.activePage),
            };
          }

          if (repo != null && clock != null) {
            // 篇数统计跨全部年份逐月求和；数据量小且 status 是低频命令。
            var docCount = 0;
            for (final year in await repo.availableYears()) {
              for (final month in await repo.monthsOfYear(year)) {
                docCount += (await repo.daysOfMonth(year, month)).length;
              }
            }
            result['diary'] = {
              'ready': true,
              'path': paths?.diaryRoot?.path,
              'docCount': docCount,
              'diaryDate': isoDate(clock.today()),
            };
          } else {
            result['diary'] = {'ready': false};
          }
          return result;
        },
      ),
      CommandSpec(
        namespace: 'sys',
        verb: 'audit',
        summary: '审计流水（倒序），绝不含 PIN 与正文全文',
        kind: CommandKind.read,
        level: ControlLevel.owner,
        params: [
          ParamSpec('limit',
              type: ArgType.integer, defaults: 50, summary: '条数，1..200'),
        ],
        handler: (ctx) async {
          final audit = ctx.requireService<AuditLog>('审计流水');
          final limit = ctx.arg<int>('limit').clamp(1, 200);
          return {
            'entries': audit.list(limit: limit).map((e) => e.toJson()).toList(),
          };
        },
      ),
      sysClockSet,
    ];

/// `sys.clock.set`（debug-only）：拨日记日时钟，用于真机日界验证。
final CommandSpec sysClockSet = CommandSpec(
  namespace: 'sys',
  verb: 'clock.set',
  summary: '【仅 debug】覆盖日记日时钟（不触碰系统时间），冷启动恢复',
  kind: CommandKind.write,
  level: ControlLevel.user,
  debugOnly: true,
  idempotent: true,
  params: [
    ParamSpec('time',
        type: ArgType.dateTime, summary: '覆盖到的本地时间 YYYY-MM-DDTHH:mm'),
    ParamSpec('reset',
        type: ArgType.boolean, defaults: false, summary: '恢复真实墙钟'),
  ],
  handler: (ctx) async {
    final clock = ctx.requireService<DiaryClock>('日记日时钟');
    final reset = ctx.arg<bool>('reset');
    final time = ctx.optionalArg<DateTime>('time');
    if (reset == (time != null)) {
      // 二选一且必填其一：两者同给/同缺都是用法错，避免静默拨错钟。
      throw const ControlException(
        ControlErrorCode.usage,
        '必须且只能给一个：--time <iso> 或 --reset',
      );
    }

    final before = clock.now();
    if (reset) {
      clock.clearOverride();
    } else {
      clock.overrideTo(time!);
    }
    final after = clock.now();
    return {
      'before': isoDateTime(before),
      'after': isoDateTime(after),
      'diaryDate': isoDate(clock.today()),
    };
  },
);

/// 导航下标 → 稳定页名（配置与 UI 同源：[kNavDestinationSpecs]）。
String _navName(int index) {
  // 越界（理论上不会）给 unknown 而不是崩。
  return index >= 0 && index < kNavDestinationSpecs.length
      ? kNavDestinationSpecs[index].id
      : 'unknown';
}
