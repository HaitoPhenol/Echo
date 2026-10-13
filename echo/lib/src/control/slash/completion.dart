/// slash 三段式补全引擎（纯 Dart）：命名空间 → 动词 → 参数。
///
/// 数据源只有一个——当前构建风味的 `bus.visibleSpecs`：release 下
/// debug-only 命令在注册侧已物理跳过，本引擎**不做二次黑白名单**
/// （设计 §7：补全天然不可见）。
library;

import '../protocol/command_spec.dart';
import 'line_parser.dart';

/// 补全所处的段落（UI 可据此分组/变色）。
enum CompletionSegment {
  /// 正在输命名空间（`/d`、`` 空）。
  namespace,

  /// 正在输动词（`diary.l`、`/diary li`）。
  verb,

  /// 命令已确定，正在补参数（`diary.list --mo`）。
  param,

  /// 无可建议项（如未知命令上输参数）。
  none,
}

/// 一条补全候选。
class CompletionCandidate {
  const CompletionCandidate({
    required this.insert,
    required this.label,
    this.detail = '',
    this.hint = '',
  });

  /// 选中后插入的文本（已含尾随标点：ns 段为 `ns.`、verb 段为
  /// `verb `、布尔参数为 `--flag `）。
  final String insert;

  /// 列表主文案（ns 名 / 动词 / 参数名）。
  final String label;

  /// 说明文字（命令 summary / 参数 summary）。
  final String detail;

  /// 类型/级别提示（如 `级3 写`、`integer*`、`boolean`）。
  final String hint;
}

/// 一次补全计算结果。
class CompletionResult {
  const CompletionResult({
    required this.segment,
    required this.replaceStart,
    required this.candidates,
  });

  final CompletionSegment segment;

  /// 输入框中应被 [CompletionCandidate.insert] 替换的区间起点
  /// （相对原始输入的字符索引，含前导 `/`；终点为输入全文末尾）。
  final int replaceStart;

  final List<CompletionCandidate> candidates;

  /// 无建议的空结果。
  static const empty = CompletionResult(
    segment: CompletionSegment.none,
    replaceStart: 0,
    candidates: [],
  );
}

/// 无状态补全引擎：构造时绑定当前风味的可见清单快照。
class CompletionEngine {
  CompletionEngine(this.specs);

  final List<CommandSpec> specs;

  /// 计算 [text]（输入框全文，可能含前导 `/`）的补全。
  CompletionResult complete(String text) {
    final hasSlash = text.startsWith('/');
    final body = hasSlash ? text.substring(1) : text;

    // 最后一个空白的位置：replaceStart 指向其后第一字符；
    // 含前导 `/` 时整体偏移 1。
    final lastWs = RegExp(r'[\s]')
        .allMatches(body)
        .map((m) => m.end)
        .fold(-1, (prev, end) => end > prev ? end : prev);
    final baseOffset = hasSlash ? 1 : 0;
    final replaceStart = lastWs < 0 ? baseOffset : baseOffset + lastWs;
    final tail = lastWs < 0 ? body : body.substring(lastWs);

    // 段一：还没有任何空白——可能在输 ns 或 ns.verbPrefix。
    if (lastWs < 0) {
      if (tail.contains('.')) {
        final dot = tail.indexOf('.');
        return _verbs(
          nsPrefix: tail.substring(0, dot),
          verbPrefix: tail.substring(dot + 1),
          replaceStart: replaceStart,
          // 点号形态从 body 起点整段替换，insert 必须自带 ns 前缀。
          dotForm: true,
        );
      }
      return _namespaces(tail, replaceStart: replaceStart);
    }

    // 已有空白：第一个 token 可能是点号形态全名（`chat.send --…`），
    // 也可能是空格形态的 ns（`/chat send …`）。
    final parts = body.split(RegExp(r'\s+'));
    // body 以空白结尾时 split 末元素为 ''（正开始写新 token）。
    final first = parts.isEmpty ? '' : parts.first;

    CommandSpec? spec;

    if (first.contains('.')) {
      // 点号形态：命令已在第一个 token 敲全（或敲错）。
      spec = specs
          .where((s) => s.name == first)
          .cast<CommandSpec?>()
          .firstWhere((_) => true, orElse: () => null);
    } else {
      // 空格形态：找第一个非 flag token 作 verbToken。
      final ns = first;
      final matchingNs = specs.where((s) => s.namespace == ns).toList();
      if (matchingNs.isEmpty) return CompletionResult.empty;

      String? verbToken;
      for (var i = 1; i < parts.length; i++) {
        final p = parts[i];
        if (p.startsWith('--')) break;
        if (p.isNotEmpty) {
          verbToken = p;
          break;
        }
      }
      spec = verbToken == null
          ? null
          : matchingNs
                .where((s) => s.verb == verbToken)
                .cast<CommandSpec?>()
                .firstWhere((_) => true, orElse: () => null);

      // verb 尚未精确确定 → 动词段（用正在输的前缀过滤）；
      // 已经在输 `--` 但命令没敲全：无可建议项。
      if (spec == null) {
        if (tail.startsWith('--')) return CompletionResult.empty;
        return _verbs(
          nsPrefix: ns,
          verbPrefix: verbToken ?? tail,
          replaceStart: replaceStart,
        );
      }

      // 动词已敲全但光标仍停在动词 token 内（`/sys ping`，无尾随
      // 空白、其后也没有其他 token）：留在动词段给唯一精确候选，
      // 控制器据此让 Enter 放行提交；补一个空格后即进参数段。
      if (verbToken != null && tail == verbToken) {
        return _verbs(
          nsPrefix: ns,
          verbPrefix: verbToken,
          replaceStart: replaceStart,
        );
      }
    }

    if (spec == null) return CompletionResult.empty;

    // 段三：参数补全。已出现参数只从「最后一个 token 之前」的文本提取
    // ——正在输入的 `--li` 是候选前缀，不能把 limit 误判成已出现。
    final settled = lastWs < 0 ? '' : body.substring(0, lastWs);
    final present = <String>{
      for (final m in RegExp(r'--([\w-]+)').allMatches(settled))
        camelize(m.group(1)!),
    };
    return _paramsFor(spec, present, tail, replaceStart: replaceStart);
  }

  CompletionResult _namespaces(String prefix, {required int replaceStart}) {
    final seen = <String>{};
    final candidates = <CompletionCandidate>[];
    for (final spec in specs) {
      if (!spec.namespace.startsWith(prefix)) continue;
      if (!seen.add(spec.namespace)) continue;
      final count = specs.where((s) => s.namespace == spec.namespace).length;
      candidates.add(
        CompletionCandidate(
          insert: '${spec.namespace}.',
          label: spec.namespace,
          detail: '$count 条命令',
        ),
      );
    }
    return CompletionResult(
      segment: CompletionSegment.namespace,
      replaceStart: replaceStart,
      candidates: candidates,
    );
  }

  CompletionResult _verbs({
    required String nsPrefix,
    required String verbPrefix,
    required int replaceStart,
    // 点号形态（/sys.pi）：replaceStart 指向 body 起点，insert 须为
    // `ns.verb `，否则会吞掉命名空间（/sys.pi 选 ping 曾变成 /ping）。
    // 动词自身可能含点（sys 命名空间下的 clock.set）。空格形态
    // （/sys pi）只替换动词 token，insert 仍为 `verb `。
    bool dotForm = false,
  }) {
    // ns 必须精确：输 `diary.l` 不能把别的 ns 拉进来（调用方保证
    // nsPrefix 非空——空前缀场景在 complete() 已归到命名空间段）。
    final candidates = [
      for (final spec in specs)
        if (spec.namespace == nsPrefix && spec.verb.startsWith(verbPrefix))
          CompletionCandidate(
            insert: dotForm
                ? '${spec.namespace}.${spec.verb} '
                : '${spec.verb} ',
            label: spec.verb,
            detail: spec.summary,
            hint: '级${spec.level.value} · ${spec.kind.wire}',
          ),
    ];
    return CompletionResult(
      segment: CompletionSegment.verb,
      replaceStart: replaceStart,
      candidates: candidates,
    );
  }

  CompletionResult _paramsFor(
    CommandSpec spec,
    Set<String> present,
    String tail, {
    required int replaceStart,
  }) {
    final prefix = tail.startsWith('--') ? camelize(tail.substring(2)) : '';

    String cli(ParamSpec p) => kebabOf(p.name);

    final paramCandidates = [
      for (final p in spec.params)
        if (!present.contains(p.name) && p.name.startsWith(prefix))
          CompletionCandidate(
            // 布尔与取值参数同形：都补 `--name `，布尔不吃值由提交时
            // 的词法层决定（面板不预塞 true/false）。
            insert: '--${cli(p)} ',
            label: '--${cli(p)}',
            detail: p.summary,
            hint: '${p.type.wire}${p.required ? '*' : ''}',
          ),
    ];
    // required 优先（保持声明顺序，stable sort）。
    paramCandidates.sort(
      (a, b) =>
          _requiredRank(spec, b.label).compareTo(_requiredRank(spec, a.label)),
    );

    // 全局候选：空前缀全列；正在输前缀时同样按前缀过滤
    //（`--li` 不拉入 --stay）。
    bool globalAllowed(String name) =>
        !present.contains(name) && name.startsWith(prefix);
    final globals = <CompletionCandidate>[
      // 破坏性 3 级才提示 --confirm（chat.send/set-pin 不需要）。
      if (spec.requiresConfirm && globalAllowed('confirm'))
        const CompletionCandidate(
          insert: '--confirm ',
          label: '--confirm',
          detail: '3 级破坏性命令的显式确认',
        ),
      if (globalAllowed('stay'))
        const CompletionCandidate(
          insert: '--stay ',
          label: '--stay',
          detail: '执行后不收起指令台',
        ),
      if (globalAllowed('format'))
        const CompletionCandidate(
          insert: '--format ',
          label: '--format',
          detail: 'json / text / table',
        ),
      if (globalAllowed('timeout'))
        const CompletionCandidate(
          insert: '--timeout ',
          label: '--timeout',
          detail: '覆盖超时（秒，最长 60）',
        ),
    ];

    return CompletionResult(
      segment: CompletionSegment.param,
      replaceStart: replaceStart,
      candidates: [...paramCandidates, ...globals],
    );
  }

  /// 全局/参数混排排序辅助：required 参数排前。
  int _requiredRank(CommandSpec spec, String label) {
    final name = camelize(label.substring(2));
    final param = spec.params
        .where((p) => p.name == name)
        .cast<ParamSpec?>()
        .firstWhere((_) => true, orElse: () => null);
    return param?.required ?? false ? 1 : 0;
  }
}
