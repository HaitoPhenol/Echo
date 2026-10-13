import 'package:flutter_test/flutter_test.dart';

import 'package:echo/src/control/protocol/control_error.dart';
import 'package:echo/src/control/slash/line_parser.dart';

import '../control_test_harness.dart';

/// slash 行解析重点单测：解析器只做词法/形状，类型/必填/未知参数/
/// 鉴权全部留给总线——这里只钉解析产物，不钉类型转换。
void main() {
  late ControlHarness h;
  setUp(() async {
    h = await ControlHarness.create();
    addTearDown(h.dispose);
  });

  ParsedInvocation parse(String line) => parseLine(line, lookup: h.bus.specOf);

  group('命令名形态', () {
    test('点号形态 ns.verb', () {
      final r = parse('diary.list --month 2026-10');
      expect(r.cmd, 'diary.list');
      expect(r.args, {'month': '2026-10'});
    });

    test('空格形态 /ns verb（前导斜杠可有可无）', () {
      expect(parse('/diary list').cmd, 'diary.list');
      expect(parse('diary list').cmd, 'diary.list');
    });

    test('动词含点/连字符：sys.clock.set / auth.set-pin', () {
      final r = parse('/sys clock.set --time 2026-10-13T10:00');
      expect(r.cmd, 'sys.clock.set');
      expect(r.args, {'time': '2026-10-13T10:00'});
      expect(parse('auth.set-pin').cmd, 'auth.set-pin');
    });

    test('残缺命令名 → SlashUsageException', () {
      for (final bad in [
        '',
        '   ',
        '/',
        'diary',
        '/diary',
        'diary.',
        '.',
        'diary --month x',
        '/diary --month x',
      ]) {
        expect(
          () => parse(bad),
          throwsA(isA<SlashUsageException>()),
          reason: '「$bad」应解析失败',
        );
      }
    });
  });

  group('参数词法', () {
    test('--k=v 与 --k v 等价；值一律 String（数字不猜类型）', () {
      final a = parse('diary.list --month=2026-10 --limit=5');
      final b = parse('diary.list --month 2026-10 --limit 5');
      expect(a.args, {'month': '2026-10', 'limit': '5'});
      expect(b.args, {'month': '2026-10', 'limit': '5'});
      expect(a.args['limit'], isA<String>());
    });

    test('布尔参数从清单派生：开关 / 显式值 / 不吃后续 flag', () {
      // diary.reset 的 keepSeeds 是 boolean（清单驱动，非硬编码名单）。
      expect(parse('diary.reset --keep-seeds').args, {'keepSeeds': true});
      expect(parse('diary.reset --keep-seeds=true').args, {'keepSeeds': true});
      expect(parse('diary.reset --keep-seeds=false').args, {
        'keepSeeds': false,
      });
      // 下一个 token 恰为 true/false 按显式值吃掉。
      expect(parse('diary.reset --keep-seeds true').args, {'keepSeeds': true});
      // 布尔后紧跟另一个 flag：绝不误吃（未知 flag 缺值由解析层拒，
      // 两种失败都不会把 flag 名变成 keepSeeds 的值）。
      expect(
        () => parse('diary.reset --keep-seeds --bogus'),
        throwsA(isA<SlashUsageException>()),
      );
      // 未知 flag 带值时照词法吞掉交总线 USAGE，keepSeeds 仍为 bool。
      final two = parse('diary.reset --keep-seeds --bogus x');
      expect(two.args['keepSeeds'], isTrue);
      expect(two.args['bogus'], 'x');
    });

    test('布尔参数收到非法内联值 → 解析期拒绝', () {
      expect(
        () => parse('diary.reset --keep-seeds=maybe'),
        throwsA(
          isA<SlashUsageException>().having(
            (e) => e.message,
            'message',
            contains('true/false'),
          ),
        ),
      );
    });

    test('取值参数缺值（行尾/后接 flag）→ 拒绝', () {
      expect(
        () => parse('diary.list --month'),
        throwsA(isA<SlashUsageException>()),
      );
      expect(
        () => parse('diary.list --month --limit 5'),
        throwsA(isA<SlashUsageException>()),
      );
      expect(
        () => parse('diary.list --month='),
        throwsA(isA<SlashUsageException>()),
      );
    });

    test('kebab→camel 与 echo-cmd camelize 同口径', () {
      final r = parse(
        'auth.set-pin --new-pin ab1 --new-pin-confirm ab1 --old-pin x9',
      );
      expect(r.args.keys, ['newPin', 'newPinConfirm', 'oldPin']);
      expect(r.args['newPin'], 'ab1');
    });

    test('未知参数不提前裁决：照词法组 Map，交总线 USAGE', () {
      final r = parse('diary.list --bogus value --limit 3');
      expect(r.args, {'bogus': 'value', 'limit': '3'});
    });

    test('未知命令也能解析（总线回 UNKNOWN_COMMAND）', () {
      final r = parse('ghost.verb --x y');
      expect(r.cmd, 'ghost.verb');
      expect(r.args, {'x': 'y'});
    });

    test('裸位置参数 / 单独 -- → 拒绝', () {
      expect(
        () => parse('diary.list 2026-10'),
        throwsA(isA<SlashUsageException>()),
      );
      expect(
        () => parse('diary.list -- --month 2026-10'),
        throwsA(isA<SlashUsageException>()),
      );
    });

    test('--confirm / --stay 提升为标志；--confirm=x 拒绝', () {
      final r = parse('diary.prune --confirm --stay --before 2026-10-01');
      expect(r.confirmed, isTrue);
      expect(r.stay, isTrue);
      expect(r.args, {'before': '2026-10-01'});
      expect(
        () => parse('diary.prune --confirm=true'),
        throwsA(isA<SlashUsageException>()),
      );
    });
  });

  group('引号（极简自有语法）', () {
    test('双/单引号保留空格；引号内 -- 是值的一部分', () {
      final r = parse('chat.send --id x --text "hello --world ok"');
      expect(r.args['text'], 'hello --world ok');
      final s = parse("chat.send --id x --text 'a b  c'");
      expect(s.args['text'], 'a b  c');
    });

    test('引号内真实换行保留（行内粘贴多行）', () {
      final r = parse('chat.send --id x --text "第一行\n第二行"');
      expect(r.args['text'], '第一行\n第二行');
    });

    test('引号可在 token 中部开合（ab"c d"ef → abcd ef 拼接）', () {
      final r = parse('chat.send --id ab"c d"ef');
      expect(r.args['id'], 'abc def');
    });

    test('引号未闭合 → SlashUsageException', () {
      expect(
        () => parse('chat.send --text "abc'),
        throwsA(isA<SlashUsageException>()),
      );
      expect(
        () => parse("chat.send --text 'abc"),
        throwsA(isA<SlashUsageException>()),
      );
    });

    test('空引号是空串值（空正文交总线 USAGE，解析层放行）', () {
      final r = parse('chat.send --id x --text ""');
      expect(r.args['text'], '');
    });
  });

  group('help 语义（尾随 ? / --help）', () {
    test('三种形态都置 helpIntent', () {
      expect(parse('diary.list?').helpIntent, isTrue);
      expect(parse('/diary list ?').helpIntent, isTrue);
      expect(parse('diary list --help').helpIntent, isTrue);
      expect(parse('diary.list --help').helpIntent, isTrue);
    });

    test('正常命令不触发；独立 ? 优先于取值（参数缺值也不报错）', () {
      expect(parse('diary.list --limit 3').helpIntent, isFalse);
      // 未加引号的独立 ? 永远是尾随 help：text 不收值，命令也不执行。
      final r = parse('chat.send --id x --text ?');
      expect(r.helpIntent, isTrue);
      expect(r.args.containsKey('text'), isFalse);
    });

    test('带参数的尾随问号：参数保留', () {
      final r = parse('diary.list --month 2026-10 ?');
      expect(r.helpIntent, isTrue);
      expect(r.cmd, 'diary.list');
      expect(r.args, {'month': '2026-10'});
    });
  });

  test('SlashUsageException 是 FormatException 风格的自持异常', () {
    final e = SlashUsageException('演示');
    expect(e.toString(), 'USAGE: 演示');
    expect(ControlErrorCode.usage.wire, 'USAGE');
  });
}
