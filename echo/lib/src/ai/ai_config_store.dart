import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import 'ai_config.dart';

/// AI 配置的持久化存储（应用私有目录 JSON 文件）。
///
/// 安全边界：
/// - 文件落在应用私有目录（非用户可浏览的 Documents），不参与日记
///   导出，也不写日志；
/// - 界面只展示 [maskApiKey] 掩码，明文仅在发请求时读取。
///
/// 写入采用「临时文件 + rename」的原子替换，并在内部串行化，
/// 避免连续保存时后一次覆盖前一次的结果。
class AiConfigStore extends ChangeNotifier {
  AiConfigStore({this.directory, AiConfig? initialConfig})
    : _config = initialConfig ?? const AiConfig();

  /// 配置文件文件名。
  static const String fileName = 'ai_config.json';

  /// 测试注入的目录；生产为 null（走 path_provider 的私有目录）。
  final Directory? directory;

  AiConfig _config;
  bool _disposed = false;
  bool _loaded = false;
  Future<void> _writeChain = Future<void>.value();

  /// 内存态被修改的次数；用于避免 `load()` 的迟到结果覆盖
  /// 载入期间用户刚做的修改。
  int _revision = 0;

  /// 是否已完成首次读取（读取失败也视为完成，配置为空）。
  bool get isLoaded => _loaded;

  List<AiModelProfile> get profiles => _config.profiles;

  String? get activeProfileId => _config.activeProfileId;

  AiModelProfile? get activeProfile => _config.activeProfile;

  /// 从私有目录读取配置；文件不存在或损坏时保持空配置。
  Future<void> load() async {
    final revisionAtStart = _revision;
    AiConfig loaded = const AiConfig();
    try {
      final file = await _configFile();
      if (await file.exists()) {
        final raw = await file.readAsString();
        final decoded = jsonDecode(raw);
        if (decoded is Map) {
          loaded = AiConfig.fromJson(Map<String, dynamic>.from(decoded));
        }
      }
    } catch (_) {
      // 损坏/不可读的配置不阻塞启动：保留空配置，等待用户重新填写。
    }
    // 载入期间若有新写入，内存态更新，丢弃迟到的文件快照。
    if (_revision == revisionAtStart) {
      _config = loaded;
    }
    _loaded = true;
    _notify();
  }

  /// 新增或更新一条配置；没有默认项时自动把该条设为默认。
  Future<void> upsert(AiModelProfile profile) {
    final next = [
      for (final existing in _config.profiles)
        if (existing.id != profile.id) existing,
      profile,
    ];
    final activeId = _config.activeProfileId;
    _config = AiConfig(
      profiles: List.unmodifiable(next),
      activeProfileId:
          (activeId != null && next.any((p) => p.id == activeId))
          ? activeId
          : profile.id,
    );
    _revision++;
    _notify();
    return _persist();
  }

  /// 删除一条配置；若删除的是默认项，则默认项清空。
  Future<void> remove(String id) {
    final next = _config.profiles.where((p) => p.id != id).toList();
    _config = AiConfig(
      profiles: List.unmodifiable(next),
      activeProfileId: _config.activeProfileId == id
          ? null
          : _config.activeProfileId,
    );
    _revision++;
    _notify();
    return _persist();
  }

  /// 设置默认配置；传 null 清空。id 不存在时忽略。
  Future<void> setActive(String? id) {
    if (id != null && !_config.profiles.any((p) => p.id == id)) {
      return Future<void>.value();
    }
    _config = AiConfig(
      profiles: _config.profiles,
      activeProfileId: id,
    );
    _revision++;
    _notify();
    return _persist();
  }

  Future<File> _configFile() async {
    final dir = directory ?? await getApplicationSupportDirectory();
    await dir.create(recursive: true);
    return File('${dir.path}/$fileName');
  }

  /// 串行落盘：临时文件写满后再原子替换目标文件。
  Future<void> _persist() {
    final snapshot = jsonEncode(_config.toJson());
    _writeChain = _writeChain.then((_) async {
      // 已排队的写入照常完成：dispose 只停止通知，不取消落盘，
      // 避免刚保存的配置在退出时丢失。
      try {
        final file = await _configFile();
        final tmp = File('${file.path}.tmp');
        await tmp.writeAsString(snapshot, flush: true);
        await tmp.rename(file.path);
      } catch (_) {
        // 落盘失败不抛给 UI：内存态已更新，下次保存会重试。
      }
    });
    return _writeChain;
  }

  void _notify() {
    if (_disposed) return;
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
