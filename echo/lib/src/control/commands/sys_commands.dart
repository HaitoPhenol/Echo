import 'dart:async';
import 'dart:io' show pid;

import '../../diary/data/diary_clock.dart';
import '../../diary/data/diary_repository.dart';
import '../../navigation/nav_destination_specs.dart';
import '../../navigation/nav_physics.dart';
import '../auth/audit_log.dart';
import '../auth/auth_session.dart';
import '../control_app_state.dart';
import '../control_registry.dart';
import '../jobs/job_store.dart';
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
      ParamSpec(
        'command',
        type: ArgType.string,
        summary: '限定单条命令的全名，如 diary.list',
      ),
    ],
    handler: (ctx) async {
      final only = ctx.optionalArg<String>('command');
      if (only != null) {
        final spec = ctx.bus.visibleSpecs
            .where((s) => s.name == only)
            .cast<CommandSpec?>()
            .firstWhere((_) => true, orElse: () => null);
        if (spec == null) {
          throw ControlException(ControlErrorCode.notFound, '没有这条命令：$only');
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
      ParamSpec(
        'limit',
        type: ArgType.integer,
        defaults: 50,
        summary: '条数，1..200',
      ),
    ],
    handler: (ctx) async {
      final audit = ctx.requireService<AuditLog>('审计流水');
      final limit = ctx.arg<int>('limit').clamp(1, 200);
      return {
        'entries': audit.list(limit: limit).map((e) => e.toJson()).toList(),
      };
    },
  ),
  jobGet,
  sysClockSet,
  sysDelay,
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
    ParamSpec(
      'time',
      type: ArgType.dateTime,
      summary: '覆盖到的本地时间 YYYY-MM-DDTHH:mm',
    ),
    ParamSpec(
      'reset',
      type: ArgType.boolean,
      defaults: false,
      summary: '恢复真实墙钟',
    ),
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

/// `sys.job.get`（P4，全构建）：异步作业轮询，E4 根治通道。
///
/// owner(1) 读命令：adb/slash 起始即 user(2) 直放；mcp 起始 guest(0)
/// 且只读铁律下永不解锁，故在鉴权门即被拒（连隔离层都到不了）。
final CommandSpec jobGet = CommandSpec(
  namespace: 'sys',
  verb: 'job.get',
  summary: '查询异步作业状态/终态信封（adb slow 命令轮询用）',
  kind: CommandKind.read,
  level: ControlLevel.owner,
  params: [
    ParamSpec(
      'id',
      type: ArgType.string,
      required: true,
      summary: '作业 id（异步首包 jobId）',
    ),
  ],
  handler: (ctx) async {
    final jobs = ctx.requireService<ControlJobStore>('异步作业表');
    final auth = ctx.requireService<AuthManager>('鉴权会话');
    final id = ctx.arg<String>('id');

    // 跨通道隔离：他通道/不存在/已淘汰统一翻 NOT_FOUND，不向调用方
    // 区分「不存在」与「无权跨通道看」。
    final job = jobs.lookup(id: id, channel: ctx.channel);
    if (job == null) {
      throw ControlException(ControlErrorCode.notFound, '作业不存在或已淘汰：$id');
    }

    // 取结果前按作业原命令在**当前**通道重新裁决：后台执行期间会话
    // 被切后台/息屏焚尽时，未重新解锁取不回（AUTH_REQUIRED）；
    // confirmed 沿用起作业时的显式确认，轮询不重复要 --confirm。
    // 作业保留——重解后可再取。
    final denied = auth.check(job.spec, ctx.channel, confirmed: job.confirmed);
    if (denied != null) throw denied;

    final envelope = job.envelope;
    if (envelope == null) {
      return {'status': 'running', 'jobId': job.id, 'cmd': job.spec.name};
    }
    // 内层信封即原命令的最终信封（result/error/ms/nonce 原样）。
    return {'status': 'done', 'envelope': envelope.toJson()};
  },
);

/// `sys.delay`（debug-only，P4）：纯验证用挂起，专走 slow(60s)/
/// 异步作业路径，在真机上复现「命令耗时超过接收器 9s 预算」。
/// guest 级、只读类、无任何业务副作用；release 物理不注册。
final CommandSpec sysDelay = CommandSpec(
  namespace: 'sys',
  verb: 'delay',
  summary: '【仅 debug·验证用】挂起若干毫秒，走 slow/异步作业路径',
  kind: CommandKind.read,
  level: ControlLevel.guest,
  debugOnly: true,
  slow: true,
  params: [
    ParamSpec(
      'ms',
      type: ArgType.integer,
      defaults: 5000,
      summary: '挂起毫秒数，0..30000（默认 5000）',
    ),
  ],
  handler: (ctx) async {
    final ms = ctx.arg<int>('ms');
    if (ms < 0 || ms > 30000) {
      throw const ControlException(
        ControlErrorCode.usage,
        '--ms 允许范围 0..30000',
      );
    }
    await Future<void>.delayed(Duration(milliseconds: ms));
    return {'sleptMs': ms};
  },
);

/// 导航下标 → 稳定页名（配置与 UI 同源：[kNavDestinationSpecs]）。
String _navName(int index) {
  // 越界（理论上不会）给 unknown 而不是崩。
  return index >= 0 && index < kNavDestinationSpecs.length
      ? kNavDestinationSpecs[index].id
      : 'unknown';
}
