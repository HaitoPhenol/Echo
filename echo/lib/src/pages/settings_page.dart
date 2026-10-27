import 'package:flutter/material.dart';

import '../ai/ai_api_client.dart';
import '../ai/ai_config.dart';
import '../ai/ai_config_store.dart';
import '../control/bootstrap.dart';
import '../control/mcp/mcp_server.dart';
import '../control/protocol/command_spec.dart';
import '../theme/app_colors.dart';
import '../theme/mechanical_style.dart';

/// 设置页：模型 API 配置、连通性测试与 MCP 现状说明。
///
/// 入口在智能导航屏的侧边抽屉（见 `SideDrawer.onOpenSettings`），
/// 以普通路由压栈打开。
class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key, required this.store, this.apiClient});

  /// AI 配置存储（由装配根创建并持有）。
  final AiConfigStore store;

  /// 测试注入的 API 客户端；生产为 null（使用真实 HttpClient）。
  final AiApiClient? apiClient;

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  late final AiApiClient _apiClient = widget.apiClient ?? AiApiClient();

  /// 正在测试的配置 id。
  String? _testingId;

  /// 最近一次测试结果（按配置 id）。
  final Map<String, AiConnectivityResult> _results = {};

  @override
  void initState() {
    super.initState();
    widget.store.addListener(_handleStoreChanged);
  }

  @override
  void dispose() {
    widget.store.removeListener(_handleStoreChanged);
    super.dispose();
  }

  void _handleStoreChanged() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Column(
          children: [
            _buildHeader(context),
            const Divider(height: 1, color: AppColors.tone1),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 20, 16, 32),
                children: [
                  _SettingsSectionHeader(
                    code: 'AI',
                    title: '模型 API',
                    subtitle: 'OpenAI 兼容 · /chat/completions',
                  ),
                  const SizedBox(height: 12),
                  if (widget.store.profiles.isEmpty)
                    _buildEmptyProfiles()
                  else
                    for (final profile in widget.store.profiles) ...[
                      _buildProfileCard(profile),
                      const SizedBox(height: 10),
                    ],
                  const SizedBox(height: 4),
                  _buildAddProfileButton(),
                  const SizedBox(height: 28),
                  _SettingsSectionHeader(
                    code: 'MCP',
                    title: '工具接入',
                    subtitle: '只读控制面 · 现状说明',
                  ),
                  const SizedBox(height: 12),
                  _buildMcpSection(),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ================================================================
  //  页头
  // ================================================================

  Widget _buildHeader(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 8, 16, 12),
      child: Row(
        children: [
          IconButton(
            onPressed: () => Navigator.of(context).maybePop(),
            icon: const Icon(Icons.arrow_back_ios_new, size: 18),
            color: AppColors.textMuted,
            tooltip: '返回',
          ),
          const SizedBox(width: 4),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text.rich(
                  TextSpan(
                    children: [
                      const TextSpan(text: 'SEC.05 '),
                      const TextSpan(
                        style: TextStyle(color: AppColors.mechInkDim),
                        text: '// ',
                      ),
                      const TextSpan(text: 'SETTINGS'),
                    ],
                  ),
                  style: const TextStyle(
                    fontFamily: 'monospace',
                    fontSize: MechanicalStyle.kickerFontSize,
                    fontWeight: FontWeight.w700,
                    letterSpacing: MechanicalStyle.kickerLetterSpacing,
                    color: AppColors.mechInk,
                  ),
                ),
                const SizedBox(height: 6),
                const Text(
                  '设置',
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 2,
                    color: AppColors.textPrimary,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ================================================================
  //  模型 API
  // ================================================================

  Widget _buildEmptyProfiles() {
    return _SettingsCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: const [
          Text(
            '尚未配置模型',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: AppColors.textPrimary,
            ),
          ),
          SizedBox(height: 6),
          Text(
            '先添加一条 OpenAI 兼容的模型接入配置（Base URL、API Key、模型名），'
            '之后 AI 对话框将使用默认配置发起请求。',
            style: TextStyle(
              fontSize: 12,
              height: 1.5,
              color: AppColors.textMuted,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildProfileCard(AiModelProfile profile) {
    final isActive = widget.store.activeProfileId == profile.id;
    final testing = _testingId == profile.id;
    final result = _results[profile.id];

    return _SettingsCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  profile.displayName,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textPrimary,
                  ),
                ),
              ),
              if (isActive) const _Tag(text: '默认', color: AppColors.accentBlue),
            ],
          ),
          const SizedBox(height: 10),
          _InfoRow(label: 'BASE URL', value: profile.baseUrl),
          _InfoRow(label: 'MODEL', value: profile.model),
          _InfoRow(label: 'API KEY', value: profile.maskedApiKey),
          _InfoRow(label: '推理强度', value: profile.reasoningEffort.label),
          const SizedBox(height: 10),
          Wrap(
            spacing: 4,
            runSpacing: 4,
            children: [
              TextButton(
                onPressed: testing ? null : () => _testProfile(profile),
                child: Text(testing ? '测试中…' : '测试连接'),
              ),
              if (!isActive)
                TextButton(
                  onPressed: () => widget.store.setActive(profile.id),
                  child: const Text('设为默认'),
                ),
              TextButton(
                onPressed: () => _editProfile(profile),
                child: const Text('编辑'),
              ),
              TextButton(
                onPressed: () => _confirmDelete(profile),
                style: TextButton.styleFrom(
                  foregroundColor: AppColors.anchorRed,
                ),
                child: const Text('删除'),
              ),
            ],
          ),
          if (result != null) ...[
            const SizedBox(height: 4),
            Text(
              result.message,
              style: TextStyle(
                fontFamily: 'monospace',
                fontSize: 11.5,
                height: 1.4,
                color: result.ok ? AppColors.anchorGreen : AppColors.anchorRed,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildAddProfileButton() {
    return SizedBox(
      height: 44,
      child: OutlinedButton.icon(
        onPressed: () => _editProfile(null),
        icon: const Icon(Icons.add, size: 18),
        label: const Text('新增模型配置'),
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.textPrimary,
          side: const BorderSide(color: AppColors.tone1),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      ),
    );
  }

  Future<void> _testProfile(AiModelProfile profile) async {
    setState(() {
      _testingId = profile.id;
      _results.remove(profile.id);
    });
    AiConnectivityResult result;
    try {
      result = await _apiClient.testConnection(profile);
    } catch (error) {
      // 兜底未分类异常，避免按钮永久停在「测试中…」。
      result = AiConnectivityResult.failure('连接失败：$error');
    }
    if (!mounted) return;
    setState(() {
      _testingId = null;
      _results[profile.id] = result;
    });
  }

  Future<void> _editProfile(AiModelProfile? profile) async {
    final saved = await Navigator.of(context).push<AiModelProfile>(
      MaterialPageRoute(builder: (_) => AiProfileEditorPage(profile: profile)),
    );
    if (saved == null) return;
    await widget.store.upsert(saved);
  }

  Future<void> _confirmDelete(AiModelProfile profile) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: AppColors.overlaySurface,
        title: const Text(
          '删除配置',
          style: TextStyle(color: AppColors.textPrimary, fontSize: 16),
        ),
        content: Text(
          '确定删除「${profile.displayName}」吗？该操作不可撤销。',
          style: const TextStyle(
            color: AppColors.textMuted,
            fontSize: 13,
            height: 1.5,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            style: TextButton.styleFrom(foregroundColor: AppColors.anchorRed),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await widget.store.remove(profile.id);
    }
  }

  // ================================================================
  //  MCP
  // ================================================================

  Widget _buildMcpSection() {
    final bootstrap = ControlBootstrap.instance;
    final isMounted = bootstrap?.mcpMounted ?? false;
    final specs = bootstrap == null
        ? const <CommandSpec>[]
        : McpServer(bus: bootstrap.bus).exposedSpecs;

    return _SettingsCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  isMounted ? 'MCP 已挂载' : 'MCP 未挂载',
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textPrimary,
                  ),
                ),
              ),
              _Tag(
                text: isMounted ? 'ACTIVE' : 'OFF',
                color: isMounted ? AppColors.anchorGreen : AppColors.textMuted,
              ),
            ],
          ),
          const SizedBox(height: 10),
          const Text(
            'MCP 通过 JSON-RPC 把只读控制能力暴露给外部工具。'
            '当前仅在 debug 构建、且启动参数带 --mcp 时挂载；'
            'release 构建物理不创建，移动端也不监听 stdio。'
            '本页只展示现状，不提供运行时开关。',
            style: TextStyle(
              fontSize: 12,
              height: 1.6,
              color: AppColors.textMuted,
            ),
          ),
          const SizedBox(height: 12),
          if (bootstrap == null)
            const Text(
              '控制面未初始化，无法读取工具清单。',
              style: TextStyle(fontSize: 12, color: AppColors.textMuted),
            )
          else if (!isMounted)
            const Text(
              'MCP 挂载后在此列出可用的只读工具。',
              style: TextStyle(fontSize: 12, color: AppColors.textMuted),
            )
          else ...[
            Text(
              '工具 · ${specs.length}',
              style: const TextStyle(
                fontFamily: 'monospace',
                fontSize: 11,
                letterSpacing: 0.6,
                color: AppColors.pageLabel,
              ),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final spec in specs)
                  _ToolChip(name: spec.name, summary: spec.summary),
              ],
            ),
          ],
          const SizedBox(height: 10),
          const Text(
            '唯一写例外：auth.unlock（解锁只读会话）。'
            '其余工具均为只读，且权限上限为 owner。',
            style: TextStyle(
              fontSize: 11.5,
              height: 1.5,
              color: AppColors.mechInkDim,
            ),
          ),
        ],
      ),
    );
  }
}

/// 模型配置编辑页：新增或修改一条 OpenAI 兼容配置。
class AiProfileEditorPage extends StatefulWidget {
  const AiProfileEditorPage({super.key, this.profile});

  /// 待编辑配置；null 表示新增。
  final AiModelProfile? profile;

  @override
  State<AiProfileEditorPage> createState() => _AiProfileEditorPageState();
}

class _AiProfileEditorPageState extends State<AiProfileEditorPage> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  final ScrollController _scrollController = ScrollController();

  late final TextEditingController _nameController;
  late final TextEditingController _baseUrlController;
  late final TextEditingController _apiKeyController;
  late final TextEditingController _modelController;
  late final TextEditingController _temperatureController;
  late final TextEditingController _maxTokensController;
  late final TextEditingController _timeoutController;

  late AiReasoningEffort _reasoningEffort;

  @override
  void initState() {
    super.initState();
    final profile = widget.profile;
    _nameController = TextEditingController(text: profile?.name ?? '');
    _baseUrlController = TextEditingController(text: profile?.baseUrl ?? '');
    _apiKeyController = TextEditingController();
    _modelController = TextEditingController(text: profile?.model ?? '');
    _temperatureController = TextEditingController(
      text: (profile?.temperature ?? 0.7).toString(),
    );
    _maxTokensController = TextEditingController(
      text: '${profile?.maxTokens ?? 1024}',
    );
    _timeoutController = TextEditingController(
      text: '${profile?.timeoutSeconds ?? 60}',
    );
    _reasoningEffort =
        profile?.reasoningEffort ?? AiReasoningEffort.unspecified;
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _nameController.dispose();
    _baseUrlController.dispose();
    _apiKeyController.dispose();
    _modelController.dispose();
    _temperatureController.dispose();
    _maxTokensController.dispose();
    _timeoutController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Form(
          key: _formKey,
          child: Column(
            children: [
              _buildHeader(context),
              const Divider(height: 1, color: AppColors.tone1),
              Expanded(
                // 用 SingleChildScrollView 全量构建表单，确保滚动区外的
                // 字段也注册进 Form，保存时能一并校验。
                child: SingleChildScrollView(
                  controller: _scrollController,
                  padding: const EdgeInsets.fromLTRB(16, 20, 16, 32),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _SettingsField(
                        label: '名称',
                        hint: '例如：主力模型（可留空）',
                        controller: _nameController,
                        textInputAction: TextInputAction.next,
                      ),
                      _SettingsField(
                        label: 'Base URL',
                        hint: 'https://api.openai.com/v1',
                        controller: _baseUrlController,
                        keyboardType: TextInputType.url,
                        textInputAction: TextInputAction.next,
                        validator: (value) {
                          final url = (value ?? '').trim();
                          if (url.isEmpty) return '请填写 Base URL';
                          if (!url.startsWith('http://') &&
                              !url.startsWith('https://')) {
                            return '需以 http:// 或 https:// 开头';
                          }
                          return null;
                        },
                      ),
                      Padding(
                        padding: const EdgeInsets.only(bottom: 14),
                        child: TextFormField(
                          controller: _apiKeyController,
                          obscureText: true,
                          autocorrect: false,
                          enableSuggestions: false,
                          decoration: _decoration(
                            label: 'API Key',
                            // 已保存的 Key 不回填明文，界面上只给末 4 位提示。
                            hint:
                              widget.profile == null ||
                                  widget.profile!.apiKey.trim().isEmpty
                              ? 'sk-…（仅保存在应用私有目录）'
                              : '已保存 ${widget.profile!.maskedApiKey}，留空则保持不变',
                          ),
                        ),
                      ),
                      _SettingsField(
                        label: '模型名',
                        hint: 'gpt-4o-mini',
                        controller: _modelController,
                        textInputAction: TextInputAction.next,
                        validator: (value) =>
                            (value ?? '').trim().isEmpty ? '请填写模型名' : null,
                      ),
                      _buildReasoningEffortSelector(),
                      const SizedBox(height: 14),
                      _SettingsField(
                        label: '温度',
                        hint: '0 ~ 2',
                        controller: _temperatureController,
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        validator: _validateTemperature,
                      ),
                      _SettingsField(
                        label: '最大 Token',
                        hint: '正整数',
                        controller: _maxTokensController,
                        keyboardType: TextInputType.number,
                        validator: (value) {
                          final parsed = int.tryParse((value ?? '').trim());
                          if (parsed == null || parsed <= 0) {
                            return '需为正整数';
                          }
                          if (parsed > 32768) return '不超过 32768';
                          return null;
                        },
                      ),
                      _SettingsField(
                        label: '超时（秒）',
                        hint: '5 ~ 600',
                        controller: _timeoutController,
                        keyboardType: TextInputType.number,
                        validator: (value) {
                          final parsed = int.tryParse((value ?? '').trim());
                          if (parsed == null || parsed < 5 || parsed > 600) {
                            return '需在 5 ~ 600 之间';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 8),
                      SizedBox(
                        height: 48,
                        child: FilledButton(
                          onPressed: _save,
                          style: FilledButton.styleFrom(
                            backgroundColor: AppColors.accentBlue,
                            foregroundColor: AppColors.inverse,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                          ),
                          child: const Text(
                            '保存',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 2,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 8, 16, 12),
      child: Row(
        children: [
          IconButton(
            onPressed: () => Navigator.of(context).maybePop(),
            icon: const Icon(Icons.arrow_back_ios_new, size: 18),
            color: AppColors.textMuted,
            tooltip: '返回',
          ),
          const SizedBox(width: 4),
          Text(
            widget.profile == null ? '新增模型配置' : '编辑模型配置',
            style: const TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w600,
              color: AppColors.textPrimary,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildReasoningEffortSelector() {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '推理强度',
            style: TextStyle(
              fontFamily: 'monospace',
              fontSize: 10.5,
              letterSpacing: 1,
              color: AppColors.pageLabel,
            ),
          ),
          const SizedBox(height: 6),
          Container(
            height: 48,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(
              color: AppColors.overlaySurface,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.tone1),
            ),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<AiReasoningEffort>(
                value: _reasoningEffort,
                isExpanded: true,
                dropdownColor: AppColors.overlaySurface,
                icon: const Icon(
                  Icons.expand_more,
                  size: 18,
                  color: AppColors.textMuted,
                ),
                style: const TextStyle(
                  fontSize: 14,
                  color: AppColors.textPrimary,
                ),
                items: [
                  for (final effort in AiReasoningEffort.values)
                    DropdownMenuItem(value: effort, child: Text(effort.label)),
                ],
                onChanged: (value) {
                  if (value != null) {
                    setState(() => _reasoningEffort = value);
                  }
                },
              ),
            ),
          ),
          const SizedBox(height: 6),
          const Text(
            '仅在服务端支持 reasoning_effort 时生效。',
            style: TextStyle(fontSize: 11, color: AppColors.mechInkDim),
          ),
        ],
      ),
    );
  }

  String? _validateTemperature(String? value) {
    final parsed = double.tryParse((value ?? '').trim());
    if (parsed == null || !parsed.isFinite) return '需为数字';
    if (parsed < 0 || parsed > 2) return '需在 0 ~ 2 之间';
    return null;
  }

  void _save() {
    if (!(_formKey.currentState?.validate() ?? false)) {
      // 校验失败时回到表单顶部，保证错误提示在视口内可见。
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          0,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
        );
      }
      return;
    }
    final typedApiKey = _apiKeyController.text.trim();
    final profile = AiModelProfile(
      id: widget.profile?.id ?? generateAiProfileId(),
      name: _nameController.text.trim(),
      baseUrl: _baseUrlController.text.trim(),
      // 编辑时留空表示沿用已保存的 Key（明文不回填、不展示）。
      apiKey: typedApiKey.isEmpty && widget.profile != null
          ? widget.profile!.apiKey
          : typedApiKey,
      model: _modelController.text.trim(),
      reasoningEffort: _reasoningEffort,
      temperature: double.parse(_temperatureController.text.trim()),
      maxTokens: int.parse(_maxTokensController.text.trim()),
      timeoutSeconds: int.parse(_timeoutController.text.trim()),
    );
    Navigator.of(context).pop(profile);
  }
}

// ================================================================
//  共用小部件
// ================================================================

class _SettingsCard extends StatelessWidget {
  const _SettingsCard({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.overlaySurface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.tone1),
      ),
      child: child,
    );
  }
}

class _SettingsSectionHeader extends StatelessWidget {
  const _SettingsSectionHeader({
    required this.code,
    required this.title,
    required this.subtitle,
  });

  final String code;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text.rich(
          TextSpan(
            children: [
              TextSpan(text: '$code '),
              const TextSpan(
                style: TextStyle(color: AppColors.mechInkDim),
                text: '// ',
              ),
              TextSpan(text: title),
            ],
          ),
          style: const TextStyle(
            fontFamily: 'monospace',
            fontSize: 11,
            fontWeight: FontWeight.w700,
            letterSpacing: 1.2,
            color: AppColors.mechInk,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          subtitle,
          style: const TextStyle(fontSize: 11.5, color: AppColors.mechInkDim),
        ),
      ],
    );
  }
}

class _SettingsField extends StatelessWidget {
  const _SettingsField({
    required this.label,
    required this.hint,
    required this.controller,
    this.keyboardType,
    this.textInputAction,
    this.validator,
  });

  final String label;
  final String hint;
  final TextEditingController controller;
  final TextInputType? keyboardType;
  final TextInputAction? textInputAction;
  final String? Function(String?)? validator;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: TextFormField(
        controller: controller,
        keyboardType: keyboardType,
        textInputAction: textInputAction,
        validator: validator,
        autocorrect: false,
        decoration: _decoration(label: label, hint: hint),
      ),
    );
  }
}

InputDecoration _decoration({required String label, required String hint}) {
  return InputDecoration(
    labelText: label,
    hintText: hint,
    labelStyle: const TextStyle(
      fontFamily: 'monospace',
      fontSize: 11,
      letterSpacing: 0.6,
      color: AppColors.pageLabel,
    ),
    hintStyle: const TextStyle(fontSize: 13, color: AppColors.mechInkDim),
    filled: true,
    fillColor: AppColors.overlaySurface,
    alignLabelWithHint: true,
    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: const BorderSide(color: AppColors.tone1),
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: const BorderSide(color: AppColors.accentBlue),
    ),
    errorBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: const BorderSide(color: AppColors.anchorRed),
    ),
    focusedErrorBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: const BorderSide(color: AppColors.anchorRed),
    ),
  );
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 84,
            child: Text(
              label,
              style: const TextStyle(
                fontFamily: 'monospace',
                fontSize: 10.5,
                letterSpacing: 0.8,
                color: AppColors.mechInkDim,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(
                fontFamily: 'monospace',
                fontSize: 12,
                height: 1.4,
                color: AppColors.textMuted,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Tag extends StatelessWidget {
  const _Tag({required this.text, required this.color});

  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.5)),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontFamily: 'monospace',
          fontSize: 10,
          letterSpacing: 0.8,
          color: color,
        ),
      ),
    );
  }
}

class _ToolChip extends StatelessWidget {
  const _ToolChip({required this.name, required this.summary});

  final String name;
  final String summary;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: summary,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: AppColors.background,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: AppColors.tone1),
        ),
        child: Text(
          name,
          style: const TextStyle(
            fontFamily: 'monospace',
            fontSize: 11,
            color: AppColors.textMuted,
          ),
        ),
      ),
    );
  }
}
