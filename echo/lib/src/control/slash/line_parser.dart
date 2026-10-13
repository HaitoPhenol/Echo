/// slash 指令台行解析（纯 Dart，无 Widget 依赖）。
///
/// 职责只有「词法 + 形状」：把一行 `/ns verb --k v` 翻译成总线需要的
/// `(cmd, args, confirmed, stay, helpIntent)`。**类型转换、必填/未知
/// 参数、鉴权全部在总线（[ControlBus]）一处裁决**，解析器不复制清单
/// 校验规则——唯一例外是「布尔参数是否吞掉下一个 token」需要预知
/// 参数形状，该信息从同一份 [CommandSpec.params] 派生（绝不硬编码
/// 布尔名单；adb 脚本的 BOOL_FLAGS 名单是历史负债，不照搬）。
///
/// 取值参数统一以 [String] 入参 Map：总线 `_convert` 按清单把
/// "123"/"true"/"2026-10-13" 转成目标类型，因此 `--text 123` 这类
/// 字符串正文不会被误猜成数字。
library;

import '../protocol/command_spec.dart';

/// 解析期（词法/形状层）用法错误：引号未闭合、裸位置参数、参数缺值、
/// 命令名残缺等。类型错误/未知参数/缺必填不在此层——它们能形成合法
/// 调用，交给总线回 USAGE 信封，保证跨通道错误形状一致。
class SlashUsageException implements Exception {
  SlashUsageException(this.message);
  final String message;

  @override
  String toString() => 'USAGE: $message';
}

/// 一次行解析的结果。
class ParsedInvocation {
  const ParsedInvocation({
    required this.cmd,
    required this.args,
    required this.confirmed,
    required this.stay,
    required this.helpIntent,
  });

  /// 规范全名 `ns.verb`。
  final String cmd;

  /// 参数包：值为 [String] 或 [bool]；键已 camelize（kebab→camel）。
  final Map<String, Object?> args;

  /// `--confirm`：3 级破坏性命令的显式确认。
  final bool confirmed;

  /// `--stay`：可视命令执行后不收起指令台（G2 UI 消费，总线忽略）。
  final bool stay;

  /// 尾随 `?` / 命令名尾 `?` / `--help`：出 man 而非执行。
  final bool helpIntent;
}

/// 命令全名 → 清单规格；未知命令返回 null（解析照常完成，由总线回
/// UNKNOWN_COMMAND）。
typedef SlashSpecLookup = CommandSpec? Function(String cmd);

/// 解析一行 slash 输入。
///
/// 支持的命令形态（手册 §1.1，两种等价）：
/// - `/diary list --month 2026-10`（空格分 ns/verb，可带前导 `/`）
/// - `diary.list --month=2026-10`（点号形态，与 adb 同名）
///
/// 参数：`--k v`、`--k=v`、布尔开关 `--flag`、`--flag=true|false`；
/// 单/双引号包裹的值内可含空格、`--` 与真实换行；不做 shell 转义。
ParsedInvocation parseLine(String line, {required SlashSpecLookup lookup}) {
  final tokens = tokenize(line);
  if (tokens.isEmpty) {
    throw SlashUsageException('空命令行');
  }

  var helpIntent = false;

  // ---- 命令名：点号形态 或 ns + 空格 + verb --------------------------
  var head = tokens.first;
  if (head.startsWith('/')) head = head.substring(1);
  if (head.endsWith('?')) {
    head = head.substring(0, head.length - 1);
    helpIntent = true;
  }
  if (head.isEmpty) {
    throw SlashUsageException('缺少命令名（形如 ns.verb）');
  }

  String cmd;
  var argTokens = tokens.sublist(1);
  if (head.contains('.')) {
    // 只切第一个点：动词表含 clock.set / set-pin / mark-read。
    final dot = head.indexOf('.');
    final ns = head.substring(0, dot);
    final verb = head.substring(dot + 1);
    if (ns.isEmpty || verb.isEmpty) {
      throw SlashUsageException('命令名应为 ns.verb：$head');
    }
    cmd = '$ns.$verb';
  } else {
    // 空格形态：第二个 token 是动词。
    if (argTokens.isEmpty) {
      throw SlashUsageException('缺少动词：$head（形如 /$head verb）');
    }
    var verb = argTokens.first;
    if (verb.endsWith('?')) {
      verb = verb.substring(0, verb.length - 1);
      helpIntent = true;
    }
    if (verb.isEmpty || verb.startsWith('--')) {
      throw SlashUsageException('缺少动词：$head');
    }
    cmd = '$head.$verb';
    argTokens = argTokens.sublist(1);
  }

  // ---- 参数 -----------------------------------------------------------
  final spec = lookup(cmd);
  final boolNames = <String>{
    if (spec != null)
      for (final p in spec.params)
        if (p.type == ArgType.boolean) p.name,
    // 全局布尔开关（format/timeout 取值，不在此列；stay 由 Core
    // 直读不进 args；confirm 提升为 confirmed）。
    'confirm',
    'stay',
    'help',
  };

  final args = <String, Object?>{};
  var confirmed = false;
  var stay = false;

  Never usage(String msg) => throw SlashUsageException(msg);

  for (var i = 0; i < argTokens.length; i++) {
    final token = argTokens[i];

    // 独立尾随问号（未被前一个取值参数吃掉时）= help。
    if (token == '?') {
      helpIntent = true;
      continue;
    }
    if (!token.startsWith('--')) {
      usage('参数必须以 -- 开头：$token（不接受位置参数）');
    }
    var raw = token.substring(2);
    if (raw.isEmpty) {
      usage('参数名不能为空（单独的 --）');
    }

    // 形态一：--name=value。
    String? inlineValue;
    final eq = raw.indexOf('=');
    if (eq >= 0) {
      inlineValue = raw.substring(eq + 1);
      raw = raw.substring(0, eq);
      if (inlineValue.isEmpty) {
        usage('--$raw 缺少值（= 后为空）');
      }
    }

    final name = camelize(raw);
    String? nextToken() => i + 1 < argTokens.length ? argTokens[i + 1] : null;

    switch (name) {
      case 'help':
        // --help / --help=anything：统一出 man，值忽略。
        helpIntent = true;
        if (inlineValue != null) {
          // 已在 = 处切完，无需跳 token。
        }
        continue;
      case 'confirm':
        if (inlineValue != null) {
          usage('--confirm 是纯开关，不接受取值（需要确认直接加 --confirm）');
        }
        confirmed = true;
        continue;
      case 'stay':
        if (inlineValue != null) {
          usage('--stay 是纯开关，不接受取值');
        }
        stay = true;
        continue;
    }

    if (inlineValue != null) {
      if (boolNames.contains(name)) {
        final v = inlineValue;
        if (v != 'true' && v != 'false') {
          usage('--$raw 是布尔开关，只接受 true/false，收到：$v');
        }
        args[name] = v == 'true';
      } else {
        args[name] = inlineValue;
      }
      continue;
    }

    // 形态二：--name [下一 token]。
    if (boolNames.contains(name)) {
      // 与 adb 脚本同口径：下一个 token 恰为 true/false 按显式值吃掉，
      // 否则纯开关置真（绝不误吃后续参数）。
      final next = nextToken();
      if (next == 'true' || next == 'false') {
        args[name] = next == 'true';
        i++;
      } else {
        args[name] = true;
      }
    } else {
      final next = nextToken();
      if (next == '?') {
        // 未加引号的独立 `?` 一律按尾随 help 处理（手册 §1.1），优先级
        // 高于取值：当前参数缺值也不报错——helpIntent 下不执行命令。
        // 需要字面问号请与其他字符组合或经多行输入区提交。
        continue;
      }
      if (next == null || next.startsWith('--')) {
        usage('--$raw 缺少值（用法：--$raw <值>）');
      }
      args[name] = next;
      i++;
    }
  }

  return ParsedInvocation(
    cmd: cmd,
    args: args,
    confirmed: confirmed,
    stay: stay,
    helpIntent: helpIntent,
  );
}

/// 极简 tokenizer：单/双引号包裹的内容按字面拼接（引号本身去除），
/// 引号内空格、`--`、真实换行均为值的一部分；不支持反斜杠转义与
/// shell 变量展开。引号可在 token 中部开合（`ab"c d"ef` → `abc def`）。
///
/// 行尾仍处于引号态 → [SlashUsageException]（引号未闭合）。
List<String> tokenize(String line) {
  final tokens = <String>[];
  final buf = StringBuffer();
  var hasContent = false; // 当前 token 是否已有任何字符（含引号内空串）。
  String? quote; // 当前引号态：" 或 '。

  void flush() {
    if (hasContent) {
      tokens.add(buf.toString());
      buf.clear();
      hasContent = false;
    }
  }

  for (var i = 0; i < line.length; i++) {
    final ch = line[i];
    if (quote != null) {
      if (ch == quote) {
        quote = null;
        hasContent = true; // `""` 也是一个空串 token 的内容。
      } else {
        buf.write(ch);
      }
      continue;
    }
    switch (ch) {
      case '"':
      case "'":
        quote = ch;
        hasContent = true;
      case ' ' || '\t' || '\n' || '\r':
        flush();
      default:
        buf.write(ch);
        hasContent = true;
    }
  }
  if (quote != null) {
    throw SlashUsageException('引号未闭合（缺少 $quote）');
  }
  flush();
  return tokens;
}

/// CLI kebab-case → 清单 camelCase，与 scripts/echo-cmd 的 camelize
/// 逐字同口径（唯一转换点同源语义）：无连字符原样；`dry-run→dryRun`；
/// 空段忽略（`a-→a`）。
String camelize(String key) {
  if (!key.contains('-')) return key;
  final parts = key.split('-');
  final buf = StringBuffer(parts.first);
  for (var i = 1; i < parts.length; i++) {
    final p = parts[i];
    if (p.isNotEmpty) {
      buf.write(p[0].toUpperCase() + p.substring(1));
    }
  }
  return buf.toString();
}

/// camelCase → CLI kebab-case（补全候选拼 `--keep-seeds` 用）：
/// `keepSeeds→keep-seeds`、`newPin→new-pin`。
String kebabOf(String name) {
  if (!name.contains(RegExp('[A-Z]'))) return name;
  final buf = StringBuffer();
  for (var i = 0; i < name.length; i++) {
    final ch = name[i];
    if (ch == ch.toUpperCase() && ch != ch.toLowerCase()) {
      if (buf.isNotEmpty) buf.write('-');
      buf.write(ch.toLowerCase());
    } else {
      buf.write(ch);
    }
  }
  return buf.toString();
}
