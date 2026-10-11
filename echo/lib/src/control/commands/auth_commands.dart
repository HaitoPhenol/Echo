import '../auth/audit_log.dart';
import '../auth/auth_session.dart';
import '../auth/pin_store.dart';
import '../protocol/command_spec.dart';
import '../protocol/control_error.dart';

/// `auth` 命名空间：PIN 状态查询、解锁/上锁与 PIN 初始化/改 PIN
/// （手册 §3）。
///
/// 安全要点（与设计 §5、§7 一致）：
/// - PIN 只存在 `--pin` 参数里，通道层负责 stdin 采集；
///   审计在总线参数脱敏名单内，PIN 永不落日志；
/// - `auth.set-pin` 的首次初始化只允许 debug 包经 adb 发起；
/// - 改 PIN 必须处于当次前台 3 级会话（总线保证解锁与确认语义，
///   本命令额外要求旧 PIN）；二次输入 PIN 充当该命令的显式确认。
List<CommandSpec> buildAuthCommands() => [
      CommandSpec(
        namespace: 'auth',
        verb: 'status',
        summary: '查询 PIN 是否已设、当前通道级别与会话有效性',
        kind: CommandKind.read,
        level: ControlLevel.guest,
        handler: (ctx) async {
          final manager = ctx.requireService<AuthManager>('鉴权会话');
          return manager.status(ctx.channel);
        },
      ),
      CommandSpec(
        namespace: 'auth',
        verb: 'unlock',
        summary: '用 PIN 解锁当前通道至 3 级（会话仅当次前台有效）',
        kind: CommandKind.write,
        level: ControlLevel.guest,
        params: [
          ParamSpec('pin',
              type: ArgType.string, required: true, summary: 'PIN（stdin）'),
        ],
        handler: (ctx) async {
          final manager = ctx.requireService<AuthManager>('鉴权会话');
          final error =
              await manager.requestUnlock(ctx.channel, ctx.arg<String>('pin'));
          if (error != null) throw error;
          return {'unlocked': true, 'level': ControlLevel.admin.value};
        },
      ),
      CommandSpec(
        namespace: 'auth',
        verb: 'lock',
        summary: '立即销毁当前通道会话，级别回到通道起始值',
        kind: CommandKind.write,
        level: ControlLevel.guest,
        handler: (ctx) async {
          final manager = ctx.requireService<AuthManager>('鉴权会话');
          manager.lock(ctx.channel);
          return {
            'unlocked': false,
            'level': ctx.channel.startLevel.value,
          };
        },
      ),
      authSetPin,
    ];

/// `auth.set-pin`：首次初始化（debug + adb）或改 PIN（已解锁 + 旧 PIN）。
///
/// 级别标 3 但豁免总线的 `--confirm`：新 PIN 必须二次输入一致，
/// 这本身就是显式确认，避免交互上连问两遍。
final CommandSpec authSetPin = CommandSpec(
  namespace: 'auth',
  verb: 'set-pin',
  summary: '首次初始化或修改 PIN（只存加盐哈希，不收明文）',
  kind: CommandKind.write,
  level: ControlLevel.admin,
  idempotent: true,
  confirmRequired: false,
  params: [
    ParamSpec('newPin',
        type: ArgType.string, required: true, summary: '新 PIN，4..32 位'),
    ParamSpec('newPinConfirm',
        type: ArgType.string, required: true, summary: '新 PIN 再输一遍'),
    ParamSpec('oldPin',
        type: ArgType.string, summary: '改 PIN 时必填（首次初始化免）'),
  ],
  handler: (ctx) async {
    final pins = ctx.requireService<PinStore>('PIN 存储');
    final manager = ctx.requireService<AuthManager>('鉴权会话');
    final audit = ctx.requireService<AuditLog>('审计流水');
    final newPin = ctx.arg<String>('newPin');
    final newPinConfirm = ctx.arg<String>('newPinConfirm');
    final oldPin = ctx.optionalArg<String>('oldPin');

    final pinSet = await pins.isPinSet();
    if (!pinSet) {
      // 首装铁律：release 包没有初始化入口；非 adb 通道（未来 slash
      // 面板化后）也不允许命令行首装。
      if (ctx.bus.buildMode != ControlBuildMode.debug ||
          ctx.channel != ControlChannel.adb) {
        throw const ControlException(
          ControlErrorCode.authDenied,
          'PIN 首次初始化只允许 debug 包经 adb 执行',
          elevate: 'settings.pin',
        );
      }
      await pins.initialize(newPin: newPin, confirmPin: newPinConfirm);
      audit.record(AuditEntry(
        time: DateTime.now(),
        channel: ctx.channel.wire,
        cmd: 'auth.pin-init',
        // 审计只记动作不记内容：PIN 规则校验信息已在错误返回里。
        paramSummary: const {'mode': 'init'},
        ok: true,
      ));
      return {'pinSet': true, 'changed': false};
    }

    // 改 PIN：总线已校验 3 级（解锁会话）；旧 PIN 强制给。
    if (!manager.isUnlocked(ctx.channel)) {
      throw const ControlException(
        ControlErrorCode.authRequired,
        '改 PIN 前必须先 auth.unlock',
        need: 3, // ControlLevel.admin（const 上下文不能取枚举字段）
        elevate: 'auth.unlock',
      );
    }
    if (oldPin == null || oldPin.isEmpty) {
      throw const ControlException(
        ControlErrorCode.usage,
        '改 PIN 必须提供 --old-pin',
      );
    }
    await pins.change(
      oldPin: oldPin,
      newPin: newPin,
      confirmPin: newPinConfirm,
    );
    audit.record(AuditEntry(
      time: DateTime.now(),
      channel: ctx.channel.wire,
      cmd: 'auth.pin-change',
      paramSummary: const {'mode': 'change'},
      ok: true,
    ));
    return {'pinSet': true, 'changed': true};
  },
);
