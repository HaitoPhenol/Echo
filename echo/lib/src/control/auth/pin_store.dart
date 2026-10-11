import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

/// PIN 凭据记录：只存盐与慢速哈希（设计 §5.3），不落明文、
/// 不进日志、不进审计。
class PinRecord {
  const PinRecord({
    required this.iterations,
    required this.salt,
    required this.hash,
    this.algo = pinStoreAlgo,
  });

  static const String pinStoreAlgo = 'PBKDF2-HMAC-SHA256';

  final String algo;
  final int iterations;
  final Uint8List salt;
  final Uint8List hash;

  Map<String, Object?> toJson() => {
        'v': 1,
        'algo': algo,
        'iterations': iterations,
        'salt': base64.encode(salt),
        'hash': base64.encode(hash),
      };

  factory PinRecord.fromJson(Map<String, Object?> json) {
    if (json['v'] != 1 || json['algo'] != pinStoreAlgo) {
      throw const FormatException('不支持的 PIN 存储格式');
    }
    return PinRecord(
      iterations: json['iterations']! as int,
      salt: Uint8List.fromList(base64.decode(json['salt']! as String)),
      hash: Uint8List.fromList(base64.decode(json['hash']! as String)),
    );
  }
}

/// 鉴权层对 PIN 存储的最小依赖（便于 AuthManager 用假实现测试）。
abstract class PinVerifier {
  /// 是否已设置 PIN。
  Future<bool> isPinSet();

  /// 校验 PIN；错误/未设置均返回 false，不抛异常。
  Future<bool> verifyPin(String pin);
}

/// PIN 存储：`<应用文档目录>/echo_control/pin.json`，tmp+rename 原子写。
///
/// KDF = PBKDF2-HMAC-SHA256，12 万次迭代、16 字节随机盐、32 字节输出；
/// 参数写进文件，后续升级迭代次数时按记录中的值校验旧 PIN、再以新值
/// 重写。随机源默认 [Random.secure]，测试可注入固定随机。
class PinStore implements PinVerifier {
  PinStore({
    required this.directory,
    Random? random,
    this.iterations = _defaultIterations,
  }) : _random = random ?? Random.secure();

  /// PIN 规则（用户裁定，设计 §5.3）：4–32 位字母数字。
  static const int minLength = 4;
  static const int maxLength = 32;
  static const int saltBytes = 16;
  static const int keyBytes = 32;
  static const int _defaultIterations = 120000;

  static final RegExp _charset = RegExp(r'^[A-Za-z0-9]+$');

  final Directory directory;
  final Random _random;
  final int iterations;

  PinRecord? _record;
  bool _loaded = false;

  File get _file => File('${directory.path}/pin.json');

  /// 校验 PIN 形态；合法返回 null，否则返回中文原因。
  static String? validate(String pin) {
    if (pin.length < minLength || pin.length > maxLength) {
      return 'PIN 必须为 $minLength–$maxLength 位';
    }
    if (!_charset.hasMatch(pin)) {
      return 'PIN 只能包含字母与数字（A–Z a–z 0–9）';
    }
    return null;
  }

  Future<void> _ensureLoaded() async {
    if (_loaded) return;
    _loaded = true;
    if (!await _file.exists()) return;
    final raw = await _file.readAsString();
    _record = PinRecord.fromJson(
      jsonDecode(raw) as Map<String, Object?>,
    );
  }

  @override
  Future<bool> isPinSet() async {
    await _ensureLoaded();
    return _record != null;
  }

  @override
  Future<bool> verifyPin(String pin) async {
    await _ensureLoaded();
    final record = _record;
    if (record == null) return false;
    final candidate = _derive(pin, record.salt, record.iterations);
    return _constantTimeEquals(candidate, record.hash);
  }

  /// 首次初始化（无旧 PIN；调用方负责通道/构建限制与审计）。
  Future<void> initialize({
    required String newPin,
    required String confirmPin,
  }) async {
    await _ensureLoaded();
    if (_record != null) {
      throw StateError('PIN 已设置，初始化只能执行一次');
    }
    _validatePair(newPin, confirmPin);
    await _persist(_newRecord(newPin));
  }

  /// 改 PIN：校验旧 PIN + 新 PIN 二次确认一致。
  Future<void> change({
    required String oldPin,
    required String newPin,
    required String confirmPin,
  }) async {
    await _ensureLoaded();
    if (_record == null) {
      throw StateError('尚未设置 PIN，不能走改 PIN 流程');
    }
    if (!await verifyPin(oldPin)) {
      throw ArgumentError('旧 PIN 不正确');
    }
    _validatePair(newPin, confirmPin);
    await _persist(_newRecord(newPin));
  }

  void _validatePair(String newPin, String confirmPin) {
    final reason = validate(newPin);
    if (reason != null) throw ArgumentError(reason);
    if (newPin != confirmPin) {
      throw ArgumentError('两次输入的新 PIN 不一致');
    }
  }

  PinRecord _newRecord(String pin) {
    final salt = Uint8List(saltBytes);
    for (var i = 0; i < saltBytes; i++) {
      salt[i] = _random.nextInt(256);
    }
    return PinRecord(
      iterations: iterations,
      salt: salt,
      hash: _derive(pin, salt, iterations),
    );
  }

  Future<void> _persist(PinRecord record) async {
    await directory.create(recursive: true);
    final tmp = File('${_file.path}.tmp');
    await tmp.writeAsString(
      const JsonEncoder.withIndent('  ').convert(record.toJson()),
      flush: true,
    );
    await tmp.rename(_file.path); // POSIX 原子替换
    _record = record;
  }

  /// PBKDF2-HMAC-SHA256（RFC 8018）：crypto 只提供 HMAC 原语，
  /// 迭代循环在此实现，参数固定、便于审计与测试。
  static Uint8List _derive(String password, Uint8List salt, int rounds) {
    final mac = Hmac(sha256, utf8.encode(password));
    // HMAC-SHA256 输出长度即派生块长度（32 字节）。
    final hLen = mac.convert(const [0]).bytes.length;
    final blockCount = (keyBytes / hLen).ceil();
    final output = BytesBuilder();

    for (var block = 1; block <= blockCount; block++) {
      final u1Input = BytesBuilder()
        ..add(salt)
        ..add([(block >> 24) & 0xff, (block >> 16) & 0xff,
               (block >> 8) & 0xff, block & 0xff]);
      var u = mac.convert(u1Input.toBytes()).bytes as Uint8List;
      // T_1 = U_1；随后与 U_2..U_c 逐字节异或。
      final t = Uint8List.fromList(u);
      for (var i = 1; i < rounds; i++) {
        u = mac.convert(u).bytes as Uint8List;
        for (var j = 0; j < t.length; j++) {
          t[j] ^= u[j];
        }
      }
      output.add(t);
    }
    return Uint8List.sublistView(output.toBytes(), 0, keyBytes);
  }

  /// 定长比较，避免计时旁路（虽然 adb 为物理控制台，保持基本卫生）。
  static bool _constantTimeEquals(Uint8List a, Uint8List b) {
    if (a.length != b.length) return false;
    var diff = 0;
    for (var i = 0; i < a.length; i++) {
      diff |= a[i] ^ b[i];
    }
    return diff == 0;
  }
}
