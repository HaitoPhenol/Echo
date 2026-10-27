import 'package:echo/src/ai/ai_config.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('resolveChatCompletionsUrl', () {
    test('在 baseUrl 后追加标准路径', () {
      expect(
        resolveChatCompletionsUrl('https://api.openai.com/v1'),
        'https://api.openai.com/v1/chat/completions',
      );
      expect(
        resolveChatCompletionsUrl('https://api.example.com/v1/'),
        'https://api.example.com/v1/chat/completions',
      );
    });

    test('已填完整路径时不重复追加', () {
      expect(
        resolveChatCompletionsUrl(
          'https://api.example.com/v1/chat/completions',
        ),
        'https://api.example.com/v1/chat/completions',
      );
      expect(
        resolveChatCompletionsUrl(
          'https://api.example.com/v1/chat/completions/',
        ),
        'https://api.example.com/v1/chat/completions',
      );
    });
  });

  group('maskApiKey', () {
    test('空值与短 Key 不泄露字符', () {
      expect(maskApiKey(''), '未设置');
      expect(maskApiKey('   '), '未设置');
      expect(maskApiKey('ab'), '••••');
      expect(maskApiKey('abcd'), '••••');
    });

    test('长 Key 仅保留末四位', () {
      expect(maskApiKey('sk-1234567890abcd'), '••••••abcd');
    });
  });

  group('AiModelProfile', () {
    test('展示名空时回落到模型名', () {
      const profile = AiModelProfile(
        id: 'p1',
        name: '   ',
        baseUrl: 'https://api.example.com/v1',
        apiKey: 'sk-1',
        model: 'gpt-4o-mini',
      );
      expect(profile.displayName, 'gpt-4o-mini');
    });

    test('推理强度与数值字段可完整往返', () {
      const profile = AiModelProfile(
        id: 'p1',
        name: '主力',
        baseUrl: 'https://api.example.com/v1',
        apiKey: 'sk-12345678',
        model: 'gpt-4o-mini',
        reasoningEffort: AiReasoningEffort.high,
        temperature: 0.3,
        maxTokens: 2048,
        timeoutSeconds: 30,
      );

      final restored = AiModelProfile.fromJson(profile.toJson());
      expect(restored.id, 'p1');
      expect(restored.name, '主力');
      expect(restored.reasoningEffort, AiReasoningEffort.high);
      expect(restored.temperature, 0.3);
      expect(restored.maxTokens, 2048);
      expect(restored.timeoutSeconds, 30);
      expect(restored.apiKey, 'sk-12345678');
    });

    test('缺字段与非法数值回落到默认值', () {
      final restored = AiModelProfile.fromJson(const {
        'baseUrl': 'https://api.example.com/v1',
        'model': 'm',
        'temperature': 9,
        'maxTokens': 'bad',
      });
      expect(restored.id, isNotEmpty);
      expect(restored.reasoningEffort, AiReasoningEffort.unspecified);
      expect(restored.temperature, 2);
      expect(restored.maxTokens, 1024);
      expect(restored.timeoutSeconds, 60);
    });
  });

  group('AiConfig', () {
    test('默认项 id 失效时回落为 null', () {
      final config = AiConfig.fromJson({
        'activeProfileId': 'missing',
        'profiles': [
          {
            'id': 'p1',
            'baseUrl': 'https://api.example.com/v1',
            'model': 'm',
          },
        ],
      });
      expect(config.profiles, hasLength(1));
      expect(config.activeProfileId, isNull);
      expect(config.activeProfile, isNull);
    });

    test('默认项存在时可解析', () {
      final config = AiConfig.fromJson({
        'activeProfileId': 'p1',
        'profiles': [
          {
            'id': 'p1',
            'name': '主力',
            'baseUrl': 'https://api.example.com/v1',
            'model': 'm',
          },
        ],
      });
      expect(config.activeProfile?.name, '主力');
    });
  });
}
