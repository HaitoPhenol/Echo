/// AI 模型接入配置的数据模型（纯数据，无 I/O）。
///
/// 协议口径：OpenAI 兼容的 `POST {baseUrl}/chat/completions`
/// （baseUrl 通常以 `/v1` 结尾）。首版只支持纯聊天，不接本地模型。
library;

/// 推理强度（映射到 OpenAI 兼容请求的 `reasoning_effort`）。
enum AiReasoningEffort {
  /// 不显式下发，使用服务端默认。
  unspecified(''),
  low('low'),
  medium('medium'),
  high('high');

  const AiReasoningEffort(this.wireValue);

  /// 写入请求体的字面值；[unspecified] 为空串，表示不下发。
  final String wireValue;

  /// 下拉选择器展示名。
  String get label => switch (this) {
    AiReasoningEffort.unspecified => '不设置',
    AiReasoningEffort.low => '低',
    AiReasoningEffort.medium => '中',
    AiReasoningEffort.high => '高',
  };

  static AiReasoningEffort fromWire(String? value) {
    for (final effort in AiReasoningEffort.values) {
      if (effort != AiReasoningEffort.unspecified &&
          effort.wireValue == value) {
        return effort;
      }
    }
    return AiReasoningEffort.unspecified;
  }
}

/// 端点解析：把用户填写的 baseUrl 归一为 chat/completions 完整地址。
///
/// 允许直接填完整地址（已以 `/chat/completions` 结尾）；
/// 其余情况去掉尾部斜杠后追加路径。
String resolveChatCompletionsUrl(String baseUrl) {
  var base = baseUrl.trim();
  while (base.endsWith('/')) {
    base = base.substring(0, base.length - 1);
  }
  if (base.endsWith('/chat/completions')) return base;
  return '$base/chat/completions';
}

/// API Key 展示掩码：只保留末 4 位。
///
/// 明文 Key 只落在应用私有目录的配置文件里，界面任何位置都只显示
/// 掩码；空值展示为「未设置」。
String maskApiKey(String apiKey) {
  final key = apiKey.trim();
  if (key.isEmpty) return '未设置';
  if (key.length <= 4) return '••••';
  return '••••••${key.substring(key.length - 4)}';
}

/// 一条模型接入配置。
class AiModelProfile {
  const AiModelProfile({
    required this.id,
    required this.name,
    required this.baseUrl,
    required this.apiKey,
    required this.model,
    this.reasoningEffort = AiReasoningEffort.unspecified,
    this.temperature = 0.7,
    this.maxTokens = 1024,
    this.timeoutSeconds = 60,
  });

  /// 本地唯一标识（时间戳生成，仅用于列表/默认项引用）。
  final String id;

  /// 展示名称（用户自定义，空则回落到模型名）。
  final String name;

  /// OpenAI 兼容服务地址（如 `https://api.openai.com/v1`）。
  final String baseUrl;

  /// API Key（明文仅存于应用私有文件，界面掩码展示）。
  final String apiKey;

  /// 模型名（如 `gpt-4o-mini`）。
  final String model;

  /// 推理强度。
  final AiReasoningEffort reasoningEffort;

  /// 采样温度。
  final double temperature;

  /// 单次回复最大 token 数。
  final int maxTokens;

  /// 请求超时（秒）。
  final int timeoutSeconds;

  /// 界面展示用的 Key 掩码。
  String get maskedApiKey => maskApiKey(apiKey);

  /// 卡片标题：未填名称时回落到模型名。
  String get displayName => name.trim().isEmpty ? model : name.trim();

  /// 连接测试所需的最小校验：地址与模型名非空。
  bool get isReady => baseUrl.trim().isNotEmpty && model.trim().isNotEmpty;

  AiModelProfile copyWith({
    String? name,
    String? baseUrl,
    String? apiKey,
    String? model,
    AiReasoningEffort? reasoningEffort,
    double? temperature,
    int? maxTokens,
    int? timeoutSeconds,
  }) {
    return AiModelProfile(
      id: id,
      name: name ?? this.name,
      baseUrl: baseUrl ?? this.baseUrl,
      apiKey: apiKey ?? this.apiKey,
      model: model ?? this.model,
      reasoningEffort: reasoningEffort ?? this.reasoningEffort,
      temperature: temperature ?? this.temperature,
      maxTokens: maxTokens ?? this.maxTokens,
      timeoutSeconds: timeoutSeconds ?? this.timeoutSeconds,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'baseUrl': baseUrl,
    'apiKey': apiKey,
    'model': model,
    'reasoningEffort': reasoningEffort.wireValue,
    'temperature': temperature,
    'maxTokens': maxTokens,
    'timeoutSeconds': timeoutSeconds,
  };

  /// 容错解析：缺字段/类型不对时回落到默认值，避免单个坏字段让
  /// 整份配置无法读取。
  factory AiModelProfile.fromJson(Map<String, dynamic> json) {
    final id = _string(json['id']);
    return AiModelProfile(
      id: id.isEmpty ? generateAiProfileId() : id,
      name: _string(json['name']),
      baseUrl: _string(json['baseUrl']),
      apiKey: _string(json['apiKey']),
      model: _string(json['model']),
      reasoningEffort: AiReasoningEffort.fromWire(
        _string(json['reasoningEffort']),
      ),
      temperature: _double(json['temperature'], 0.7).clamp(0, 2).toDouble(),
      maxTokens: _int(json['maxTokens'], 1024),
      timeoutSeconds: _int(json['timeoutSeconds'], 60),
    );
  }
}

/// 整份 AI 配置（模型列表 + 默认项）。
class AiConfig {
  const AiConfig({this.profiles = const [], this.activeProfileId});

  final List<AiModelProfile> profiles;

  /// 默认（当前使用）配置的 id；为空表示未选。
  final String? activeProfileId;

  /// 当前默认配置；id 失效时回落为 null。
  AiModelProfile? get activeProfile {
    final id = activeProfileId;
    if (id == null) return null;
    for (final profile in profiles) {
      if (profile.id == id) return profile;
    }
    return null;
  }

  AiConfig copyWith({
    List<AiModelProfile>? profiles,
    String? activeProfileId,
  }) {
    return AiConfig(
      profiles: profiles ?? this.profiles,
      activeProfileId: activeProfileId ?? this.activeProfileId,
    );
  }

  Map<String, dynamic> toJson() => {
    'version': 1,
    'activeProfileId': activeProfileId,
    'profiles': [for (final p in profiles) p.toJson()],
  };

  factory AiConfig.fromJson(Map<String, dynamic> json) {
    final rawProfiles = json['profiles'];
    final profiles = <AiModelProfile>[];
    if (rawProfiles is List) {
      for (final item in rawProfiles) {
        if (item is Map) {
          profiles.add(AiModelProfile.fromJson(Map<String, dynamic>.from(item)));
        }
      }
    }
    final active = json['activeProfileId'];
    final hasActive =
        active is String && profiles.any((profile) => profile.id == active);
    return AiConfig(
      profiles: List.unmodifiable(profiles),
      activeProfileId: hasActive ? active : null,
    );
  }
}

/// 生成新配置 id（本地唯一即可）。
String generateAiProfileId() =>
    'p${DateTime.now().microsecondsSinceEpoch}';

String _string(Object? value) => value is String ? value : '';

double _double(Object? value, double fallback) =>
    value is num ? value.toDouble() : fallback;

int _int(Object? value, int fallback) => value is num ? value.toInt() : fallback;
