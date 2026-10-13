/// slash 指令态的 UI 交互编排（G2）。
///
/// 本类仍是「无 Widget」的状态机（只依赖 flutter/foundation 与
/// `control/slash/` 核心），Widget 层（SlashCommandLayer）只负责渲染
/// 与把手势/键事件翻译成方法调用。搜索栏是第一个宿主，未来终端页
/// 可换皮复用。
///
/// 编排内容（设计 §5/§7）：
/// - 指令态激活（首字符 `/`）、补全文本与候选键盘选择、↑↓ 历史召回；
/// - 3 级 UX 闭环：destructive 确认卡前置 → AUTH_REQUIRED → PIN
///   面板（首装两输 / 已设解锁）→ 原命令自动重放；
/// - `nav.goto` 成功收起（--stay 例外）；
/// - 多行正文展开（参数契约不变，走 core.submitMultiline）。
///
/// 文本写回：本类不直接持有 TextEditingController（那是 Widget 层
/// 对象），需要改输入框时经 [onEditText] 回发 [TextEditingValue]，
/// 宿主负责写回；纯 Dart 测试用录制回调即可断言。
library;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show TextEditingValue, TextSelection;

import '../auth/auth_session.dart';
import '../control_bus.dart';
import '../protocol/command_spec.dart';
import '../slash/completion.dart';
import '../slash/console_core.dart';
import '../slash/line_parser.dart';
import '../slash/result_view.dart';

/// PIN 面板所处阶段。
enum PinSheetMode {
  /// 未弹出。
  hidden,

  /// 首装第一遍：输入新 PIN。
  firstInstall,

  /// 首装第二遍：再输一遍确认。
  firstInstallConfirm,

  /// 已设 PIN：解锁。
  unlock,
}

/// PIN 面板不可变状态（错误文案/忙等随阶段一起换）。
@immutable
class PinSheetState {
  const PinSheetState({
    this.mode = PinSheetMode.hidden,
    this.error,
    this.busy = false,
  });

  final PinSheetMode mode;

  /// 可直接呈现的错误（两次不一致 / USAGE 文案 / AUTH_DENIED /
  /// 冷却剩余）；无错误为 null。
  final String? error;
  final bool busy;

  bool get visible => mode != PinSheetMode.hidden;

  PinSheetState copyWith({
    PinSheetMode? mode,
    Object? error = _sentinel,
    bool? busy,
  }) => PinSheetState(
    mode: mode ?? this.mode,
    error: identical(error, _sentinel) ? this.error : error as String?,
    busy: busy ?? this.busy,
  );

  static const Object _sentinel = Object();
}

/// destructive 确认卡挂起的一次提交。
@immutable
class PendingConfirm {
  const PendingConfirm({
    required this.line,
    required this.cmd,
    required this.summary,
  });

  /// 用户原始行（确认执行时追加 ` --confirm` 重投）。
  final String line;
  final String cmd;

  /// 命令摘要（spec.summary）：确认卡回显的「影响范围」描述，
  /// 不另造数据源。
  final String summary;
}

/// 多行输入展开态：head 是除正文外的已成形行，param 是接收全文的
/// string 参数（camelCase）。
@immutable
class MultilineDraft {
  const MultilineDraft({required this.head, required this.param});

  final String head;
  final String param;
}

class SlashConsoleController extends ChangeNotifier {
  SlashConsoleController({
    required ControlBus bus,
    required this.auth,
    this.onEditText,
    this.onRequestClose,
  }) : _bus = bus,
       core = ControlConsoleCore(bus: bus),
       _engine = CompletionEngine(bus.visibleSpecs) {
    core.addListener(_onCoreChanged);
    auth.addListener(_onAuthChanged);
  }

  final ControlBus _bus;

  /// 鉴权管理器（监听会话焚尽/解锁；编排 set-pin/unlock 也经其总线）。
  final AuthManager auth;

  /// 结果核心（信封流/历史/超时态全部复用，UI 不另存）。
  final ControlConsoleCore core;
  final CompletionEngine _engine;

  /// 申请改写输入框（补全插入/历史召回/Esc 清空）。
  final ValueChanged<TextEditingValue>? onEditText;

  /// 请求宿主收起指令台（nav.goto 成功路径）。
  final VoidCallback? onRequestClose;

  // ---- 指令态 / 补全 -----------------------------------------------------

  bool _active = false;
  bool get active => _active;

  /// 指令台是否应在搜索框失焦时保活。
  ///
  /// 触屏 IME 点「完成」提交后会主动 hide 键盘、TextField 随即失焦；
  /// 宿主的 150ms 失焦定时器在此返回 true 时不得收起面板，否则刚挂上的
  /// 确认卡/PIN 面板/重放/结果流会被 hostClosed 清空（G4-BUG-1）。
  ///
  /// 保活条件：指令态激活中，或存在挂起交互（确认卡/PIN/多行），或
  /// 本面板会话已产出结果条目。[hostClosed]/[exitSlash] 代表显式退出，
  /// 退出后普通搜索态失焦仍自动关闭；再输 `/` 激活时闸门重新打开。
  bool get retainsOnUnfocus =>
      _active ||
      _confirm != null ||
      _pin.visible ||
      multiline != null ||
      (!_sessionEnded && core.entries.isNotEmpty);

  /// 本面板会话是否已被显式退出（scrim/返回/导航收起/Esc）。
  bool _sessionEnded = false;

  CompletionResult _completion = CompletionResult.empty;
  CompletionResult get completion => _completion;

  /// 候选键盘高亮（-1 = 未选择，点选路径不依赖它）。
  int _candidateIndex = -1;
  int get candidateIndex => _candidateIndex;

  /// 输入框文本变化（每次按键/粘贴）。宿主在 onChanged 调用。
  void bind(String text) {
    _editingText = text;
    final wasActive = _active;
    // 单独一个 `/` 也算激活：立刻给命名空间候选，输完再退也自然。
    _active = text.startsWith('/');
    if (_active) {
      // 新一轮指令态：失焦保活闸门重新打开（上轮显式退出后 results
      // 仍保留在核心，再输 `/` 时可见）。
      _sessionEnded = false;
    }
    if (!_active) {
      _completion = CompletionResult.empty;
      _candidateIndex = -1;
      core.resetRecall();
      if (wasActive) notifyListeners();
      return;
    }
    _completion = _engine.complete(text);
    _candidateIndex = _completion.candidates.isEmpty ? -1 : 0; // 首候选默认高亮，回车即补
    notifyListeners();
  }

  bool get _candidatesOpen =>
      _completion.segment != CompletionSegment.none &&
      _completion.candidates.isNotEmpty;

  /// 候选条上移；返回是否消费（无候选展开时不消费，交 ↑ 召回）。
  bool selectPrevious() {
    if (!_candidatesOpen) return false;
    final n = _completion.candidates.length;
    _candidateIndex = (_candidateIndex - 1 + n) % n;
    notifyListeners();
    return true;
  }

  /// 候选条下移。
  bool selectNext() {
    if (!_candidatesOpen) return false;
    final n = _completion.candidates.length;
    _candidateIndex = (_candidateIndex + 1) % n;
    notifyListeners();
    return true;
  }

  /// 应用高亮候选并写回输入框；无高亮返回 false。
  bool applySelected() {
    if (!_candidatesOpen ||
        _candidateIndex < 0 ||
        _candidateIndex >= _completion.candidates.length) {
      return false;
    }
    applyCandidate(_completion.candidates[_candidateIndex]);
    return true;
  }

  /// 点选候选：从 replaceStart 起替换为 insert，光标置尾。
  void applyCandidate(CompletionCandidate candidate) {
    final next =
        _editingText.substring(0, _completion.replaceStart) + candidate.insert;
    // _writeText 已更新编辑缓存，bind 重算下一段候选（如补全命令名
    // 后立刻进入参数段）。
    _writeText(next);
    bind(next);
  }

  /// 最近一次 bind 的完整文本（补全替换用；召回等路径不依赖宿主回传）。
  String _editingText = '';

  /// Esc：清空输入、退回搜索语义（结果流保留，再输 `/` 仍可见）。
  void exitSlash() {
    // Esc 属显式退出：失焦保活闸门随之关闭，退回普通搜索语义后
    // 失焦仍按 150ms 自动收起（结果条目本身保留在核心）。
    _sessionEnded = true;
    _writeText('');
    bind('');
  }

  // ---- 提交 / 确认卡 -----------------------------------------------------

  PendingConfirm? _confirm;
  PendingConfirm? get confirmPending => _confirm;

  /// 多行展开态（null = 收起）。
  MultilineDraft? multiline;
  bool get multilineOpen => multiline != null;

  /// 当前输入是否可展开多行正文（命令带 auditRedact 的 string 参数）。
  bool get canOpenMultiline => multilineParamFor(_editingText) != null;

  /// 宿主主动收起搜索面板（点 scrim / 外部退出）：复位确认卡/多行/
  /// PIN 面板与指令态，避免下次打开残留挂起交互。
  void hostClosed() {
    _sessionEnded = true;
    _confirm = null;
    multiline = null;
    _editingText = '';
    if (_pin.visible) {
      _pin = const PinSheetState();
      _firstPin = null;
      _pendingReplay = null;
    }
    bind('');
  }

  /// 当前命令是否可展开多行正文：存在 auditRedact 的 string 参数
  ///（chat.send --text）。无命令/非指令态返回 null。
  String? multilineParamFor(String text) {
    final spec = _specOfText(text);
    if (spec == null) return null;
    for (final p in spec.params) {
      if (p.type == ArgType.string && p.auditRedact) return p.name;
    }
    return null;
  }

  CommandSpec? _specOfText(String text) {
    try {
      final inv = parseLine(text, lookup: _bus.specOf);
      return _bus.specOf(inv.cmd);
    } on SlashUsageException {
      return null;
    }
  }

  /// 提交一行（宿主 onSubmitted）。词法错误/help/未知命令直接交
  /// 核心；destructive 未确认先挂确认卡。
  Future<void> submit(String text) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return;
    // 宿主直接提交（onSubmitted 路径）即使漏了 bind 也按文本激活，
    // 不静默吞命令。
    if (!_active) {
      if (!trimmed.startsWith('/')) return;
      bind(text);
    }

    final ParsedInvocation inv;
    try {
      inv = parseLine(text, lookup: _bus.specOf);
    } on SlashUsageException {
      await core.submitLine(text); // 合成 USAGE 信封，不预判
      return;
    }

    final spec = _bus.specOf(inv.cmd);
    if (!inv.helpIntent &&
        spec != null &&
        spec.requiresConfirm &&
        !inv.confirmed) {
      _confirm = PendingConfirm(
        line: trimmed,
        cmd: spec.name,
        summary: spec.summary,
      );
      notifyListeners();
      return;
    }
    await core.submitLine(text);
  }

  /// 确认卡「执行」：追加 --confirm 走词法正规路径（历史只一条，
  /// 解锁后重放也不再撞 CONFIRM_REQUIRED）。
  Future<void> confirmRun() async {
    final pending = _confirm;
    if (pending == null) return;
    _confirm = null;
    notifyListeners();
    await core.submitLine('${pending.line} --confirm');
  }

  /// 确认卡取消：不执行（结果流不添条）。
  void cancelConfirm() {
    _confirm = null;
    notifyListeners();
  }

  // ---- PIN 面板 ---------------------------------------------------------

  PinSheetState _pin = const PinSheetState();
  PinSheetState get pinSheet => _pin;

  /// 等待解锁/首装完成后重放的原行（可能已含 --confirm）。
  String? _pendingReplay;

  /// 首装第一遍暂存（只在内存；切后台焚会话时清空）。
  String? _firstPin;

  Future<void> _openPin(String replayLine) async {
    _pendingReplay = replayLine;
    _firstPin = null;
    final pinSet = await auth.pins.isPinSet();
    _pin = PinSheetState(
      mode: pinSet ? PinSheetMode.unlock : PinSheetMode.firstInstall,
    );
    notifyListeners();
  }

  void cancelPin() {
    _pin = const PinSheetState();
    _firstPin = null;
    _pendingReplay = null;
    notifyListeners();
  }

  /// PIN 键盘提交（面板内「确定」/回车）。
  Future<void> submitPin(String pin) async {
    if (!_pin.visible || _pin.busy) return;
    if (pin.isEmpty) {
      _pin = _pin.copyWith(error: '请输入 PIN');
      notifyListeners();
      return;
    }

    switch (_pin.mode) {
      case PinSheetMode.firstInstall:
        // 第一遍只暂存；格式合规交 set-pin 单轨裁决（第二遍提交时
        // 若不合规，总线 USAGE 文案原样呈现）。
        _firstPin = pin;
        _pin = const PinSheetState(mode: PinSheetMode.firstInstallConfirm);
        notifyListeners();
        return;
      case PinSheetMode.firstInstallConfirm:
        if (pin != _firstPin) {
          _firstPin = null;
          _pin = const PinSheetState(
            mode: PinSheetMode.firstInstall,
            error: '两次输入不一致，请重新设置',
          );
          notifyListeners();
          return;
        }
        _pin = const PinSheetState(
          mode: PinSheetMode.firstInstallConfirm,
          error: null,
          busy: true,
        );
        notifyListeners();
        final setEnv = await _bus.execute(
          channel: ControlChannel.slash,
          cmd: 'auth.set-pin',
          rawArgs: {'newPin': _firstPin, 'newPinConfirm': pin},
        );
        if (!setEnv.ok) {
          _firstPin = null;
          _pin = PinSheetState(
            mode: PinSheetMode.firstInstall,
            error: setEnv.error!.message,
          );
          notifyListeners();
          return;
        }
        final unlockEnv = await _bus.execute(
          channel: ControlChannel.slash,
          cmd: 'auth.unlock',
          rawArgs: {'pin': pin},
        );
        if (!unlockEnv.ok) {
          // 理论不可达（刚首装即可验）；留错停在面板，不吞异常路径。
          _pin = PinSheetState(
            mode: PinSheetMode.firstInstall,
            error: unlockEnv.error!.message,
          );
          notifyListeners();
          return;
        }
        await _finishPinAndReplay();
      case PinSheetMode.unlock:
        _pin = const PinSheetState(mode: PinSheetMode.unlock, busy: true);
        notifyListeners();
        final env = await _bus.execute(
          channel: ControlChannel.slash,
          cmd: 'auth.unlock',
          rawArgs: {'pin': pin},
        );
        if (!env.ok) {
          _pin = PinSheetState(
            mode: PinSheetMode.unlock,
            error: env.error!.message,
          );
          notifyListeners();
          return;
        }
        await _finishPinAndReplay();
      case PinSheetMode.hidden:
        return;
    }
  }

  Future<void> _finishPinAndReplay() async {
    final replay = _pendingReplay;
    _pin = const PinSheetState();
    _firstPin = null;
    _pendingReplay = null;
    notifyListeners();
    // 重放走核心（预判已无意义：pending 行要么自带 --confirm，
    // 要么本不需要确认），结果照常进信封流。
    if (replay != null) await core.submitLine(replay);
  }

  /// 会话被前后台事件焚尽：面板若开着，清掉首装第一遍暂存并回到
  /// 阶段入口（已解锁不可能在面板里；busy 期间不动，编排自有收尾）。
  void _onAuthChanged() {
    if (!_pin.visible || _pin.busy) return;
    if (auth.isUnlocked(ControlChannel.slash)) return;
    _firstPin = null;
    _pin = _pin.copyWith(
      mode: _pin.mode == PinSheetMode.unlock
          ? PinSheetMode.unlock
          : PinSheetMode.firstInstall,
      error: null,
    );
    notifyListeners();
  }

  // ---- 核心信封流监听 ---------------------------------------------------

  int _lastHandledEntryId = 0;

  void _onCoreChanged() {
    final entries = core.entries;
    if (entries.isEmpty) return;
    final e = entries.last;
    if (e.id <= _lastHandledEntryId) return;
    if (e.status == ConsoleEntryStatus.running) {
      notifyListeners();
      return;
    }
    _lastHandledEntryId = e.id;

    final view = e.view;
    if (view is ErrorView) {
      switch (view.code) {
        case 'AUTH_REQUIRED':
          // 不 await：面板状态经 notify 刷新；submitPin 内部续跑。
          _openPin(e.line);
          return;
        case 'CONFIRM_REQUIRED':
          // 预判漏网（如外部直接投核心）的兜底：补挂确认卡。
          if (_confirm == null) {
            final spec = _bus.specOf(e.cmd);
            _confirm = PendingConfirm(
              line: e.line,
              cmd: e.cmd,
              summary: spec?.summary ?? '',
            );
          }
          notifyListeners();
          return;
      }
    }

    // nav.goto 成功默认收起；--stay/失败/help 查询不收起。
    if (e.ok && e.cmd == 'nav.goto' && !e.stay && !e.helpIntent) {
      onRequestClose?.call();
    }
    notifyListeners();
  }

  // ---- 多行 -------------------------------------------------------------

  /// 展开多行正文输入（当前命令的 auditRedact string 参数唯一）。
  void openMultiline() {
    final text = _editingText;
    final param = multilineParamFor(text);
    if (param == null) return;
    multiline = MultilineDraft(head: text.trim(), param: param);
    notifyListeners();
  }

  void closeMultiline() {
    multiline = null;
    notifyListeners();
  }

  /// 多行区提交：全文交核心注入（换行保留、互斥校验在核心）。
  Future<void> submitMultilineText(String text) async {
    final draft = multiline;
    if (draft == null) return;
    multiline = null;
    notifyListeners();
    await core.submitMultiline(
      head: draft.head,
      param: draft.param,
      text: text,
    );
    // 提交后正文区清空（head 留在输入行，历史已脱敏）。
    _writeText(draft.head);
    bind(draft.head);
  }

  // ---- 键盘：↑↓ 历史召回 ------------------------------------------------

  /// ArrowUp：候选展开时选候选，否则召回更旧历史。返回是否消费。
  bool handleUp() {
    if (selectPrevious()) return true;
    final older = core.recallOlder();
    if (older == null) return true; // 已在最旧端：吞键，光标不乱跑
    _writeText(older);
    bind(older);
    return true;
  }

  /// ArrowDown：候选展开时选候选，否则召回更新历史（越过最新端清空）。
  bool handleDown() {
    if (selectNext()) return true;
    final newer = core.recallNewer();
    if (newer == null) return true;
    _writeText(newer);
    bind(newer);
    return true;
  }

  /// Enter：候选展开且应用高亮候选后文本确有变化时补全（不提交）；
  /// 命令已敲全（应用候选只会补出一个尾随空格）或应用后无变化时
  /// 不消费，放行给 TextField 的 onSubmitted 正常提交。
  ///
  /// 即「敲全命令回车 = 提交」（/sys.ping、/sys ping），
  /// 「输前缀回车 = 补全」（/sys.pi → /sys.ping ）。
  bool handleEnter() {
    if (!_candidatesOpen ||
        _candidateIndex < 0 ||
        _candidateIndex >= _completion.candidates.length) {
      return false;
    }
    final candidate = _completion.candidates[_candidateIndex];
    final next =
        _editingText.substring(0, _completion.replaceStart) + candidate.insert;
    // 候选 insert 固定尾随一个空格：忽略该尾随空格后文本相同，说明
    // 当前 token 已精确等于高亮命令全名，Enter 必须放行提交。
    if (next == _editingText || next.trimRight() == _editingText.trimRight()) {
      return false;
    }
    applyCandidate(candidate);
    return true;
  }

  // ---- 文本写回 ---------------------------------------------------------

  void _writeText(String text) {
    _editingText = text;
    onEditText?.call(
      TextEditingValue(
        text: text,
        selection: TextSelection.collapsed(offset: text.length),
      ),
    );
  }

  /// 宿主把文本变化转进来（= [bind]，语义化名供 onChanged 直连）。
  void onInputChanged(String text) => bind(text);

  @override
  void dispose() {
    core.removeListener(_onCoreChanged);
    auth.removeListener(_onAuthChanged);
    core.dispose();
    super.dispose();
  }
}
