import 'dart:async';

import 'package:flutter/material.dart';

import '../../data/diary_repository.dart';
import '../../editor/block_editor_controller.dart';
import '../../editor/block_editor_view.dart';
import '../../editor/editor_history_buttons.dart';
import '../../editor/editor_scope.dart';
import '../../sy/diary_model.dart';
import '../../sy/sy_id.dart';
import '../../sy/sy_serializer.dart';
import '../../template/diary_composer.dart';
import '../../../theme/app_colors.dart';
import '../diary_composer_scope.dart';
import '../widgets/diary_capsule_row.dart';
import '../widgets/diary_mood_picker.dart';
import '../widgets/diary_shell.dart';

/// 单日编辑器页。
///
/// 职责编排：加载统一走 composer.ensureDay（命中草稿直接打开，无则
/// 模板成稿并落盘，补记过去空日同样进入即成稿）；dirty → 1.5s 防抖
/// upsert（M5 崩溃恢复口径，硬杀最多损失 1.5s）；进后台 / 页面 pop
/// 时立即 flush。自动数据与心情走文档根 custom-*，由滚动区首项的
/// [DiaryCapsuleRow] 呈现与刷新（2026-10-18 模板重设）。
class DayEditorPage extends StatefulWidget {
  const DayEditorPage({
    super.key,
    required this.year,
    required this.month,
    required this.day,
    this.unsupportedBlockTypes = const [],
    this.autoFocus = true,
  });

  final int year;
  final int month;
  final int day;

  /// 回读含子集外块类型时传入（M5 导入链路使用；M2 恒空），
  /// 页面顶部出只读提示横幅。参数先就位，避免未来改构造签名。
  final List<String> unsupportedBlockTypes;

  /// 载入完成后是否把光标落到最新段正文行（[requestFocus] 会主动
  /// 请求 IME、弹出软键盘）。
  ///
  /// 冷启动时笔记页在导航轨道上**离屏**预进今日编辑页（见
  /// [DiaryPage.preEnterToday]），若此处照常跳焦，App 会在用户还停在
  /// 首页时就凭空唤醒输入法。故预进路线传 false；用户主动进入
  /// （年→月→日、今日日记快捷、补记、ECP 跳转）保持 true，沿用
  /// 「进编辑页光标即落在正文行」的既有行为。
  final bool autoFocus;

  @override
  State<DayEditorPage> createState() => _DayEditorPageState();
}

class _DayEditorPageState extends State<DayEditorPage>
    with WidgetsBindingObserver {
  static const Duration _saveDebounce = Duration(milliseconds: 1500);

  final SyIdGenerator _ids = SyIdGenerator();
  late final BlockEditorController _controller = BlockEditorController(
    idGenerator: _ids,
  );
  late final DateTime _date = DateTime(widget.year, widget.month, widget.day);

  DiaryDocument? _document;
  bool _loaded = false;
  bool _loadStarted = false;

  /// 成稿编排器（`_load` 时存下，供胶囊行点按刷新复用）。
  DiaryComposer? _composer;

  /// 胶囊行取数中：期间数据胶囊不可重复点按。
  bool _refreshing = false;

  /// 该日已归档（正文已从本机清理）：不挂编辑器，仅渲染占位页。
  bool _archived = false;

  Timer? _saveTimer;
  DateTime? _savedAt;

  bool get _readOnly => _document?.locked ?? false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // InheritedWidget（仓储 scope）不能在 initState 中读取。
    if (!_loadStarted) {
      _loadStarted = true;
      _load();
    }
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  Future<void> _load() async {
    final repository = DiaryRepositoryScope.of(context);
    final composer = DiaryComposerScope.of(context).composer;
    // 归档终态：findDay 返回 null 且 composer 防复活会抛错，
    // 必须先用 stateOfDay 识别，不挂编辑器、渲染占位页。
    final state = await repository.stateOfDay(_date);
    if (state == DiaryDocState.archived) {
      if (mounted) {
        setState(() {
          _archived = true;
          _loaded = true;
        });
      }
      return;
    }
    // 成稿：命中草稿直接打开，无则模板成稿并落盘。
    final document = await composer.ensureDay(_date, repository);
    // 进入编辑页自动确保「当前段」时间戳（距上次 ≥30 分钟才新建）；
    // ensureDay 本身不生成时间戳，生成动作收口在此入口（plan 决策 14）。
    final stampAdded = composer.ensureStamp(document);
    _controller.attach(document);
    _composer = composer;
    _controller.dirty.addListener(_onDirtyChanged);
    _document = document;
    if (mounted) setState(() => _loaded = true);

    if (stampAdded) {
      // 即时落盘，但走「空段时间戳不写文件」清洗：待启用的空时间戳只存在
      // 于 UI，不进 .sy（2026-10-19 用户裁定）；旧稿补建概述段等真实改动
      // 仍即时落盘，不等 1.5s 防抖。随后（用户主动进入时）光标落到该
      // 时间戳块的下一行；离屏预进（[DayEditorPage.autoFocus] 为 false）
      // 不跳焦，避免冷启动凭空弹出软键盘。
      await repository.upsertDraft(
        composer.prunedForPersist(_controller.snapshotDocument()),
      );
      if (widget.autoFocus) _focusAfterLastStamp();
    }
  }

  /// 把焦点落到**最后一个**时间戳块的下一块（新段的正文行）。
  void _focusAfterLastStamp() {
    final blocks = _controller.blocks;
    var lastStamp = -1;
    for (var i = 0; i < blocks.length; i++) {
      if (blocks[i].block.isStamp) lastStamp = i;
    }
    if (lastStamp < 0 || lastStamp + 1 >= blocks.length) return;
    final target = blocks[lastStamp + 1].focusNode;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && target.context != null) target.requestFocus();
    });
  }

  void _onDirtyChanged() {
    if (!_controller.dirty.value || _readOnly) return;
    _saveTimer?.cancel();
    _saveTimer = Timer(_saveDebounce, _flushSave);
  }

  /// 心情选择：写 custom-mood 后立即落盘（离散动作，不赌 1.5s 防抖）。
  Future<void> _pickMood() async {
    final selection = await showDiaryMoodPicker(
      context,
      current: _controller.documentCustom[kDiaryMoodKey],
    );
    if (selection == null || !mounted) return;
    _controller.setDocumentCustom(kDiaryMoodKey, selection.mood);
    await _flushSave();
  }

  /// 数据胶囊点按刷新：重拉三源写文档根 custom-* 后立即落盘。
  ///
  /// 取数中或只读态直接返回（同一时刻只允许一次刷新，避免并发写）；
  /// 与成稿（[DiaryComposer.fetchCustomPatch]）共用同一取数入口，口径一致。
  Future<void> _refreshData() async {
    final composer = _composer;
    if (composer == null || _refreshing || _readOnly) return;
    setState(() => _refreshing = true);
    try {
      final patch = await composer.fetchCustomPatch(_date);
      if (!mounted) return;
      _controller.applyCustomPatch(patch);
      await _flushSave();
    } finally {
      if (mounted) setState(() => _refreshing = false);
    }
  }

  /// exported → archived：二次确认后删本机正文、仅留索引并退出本页。
  Future<void> _confirmArchive() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: AppColors.overlaySurface,
        title: const Text('归档这篇日记？'),
        content: const Text(
          '将删除本机正文，仅保留索引。\n'
          '请确认已在思源中完成导入；归档后本机不可再打开。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            style: TextButton.styleFrom(foregroundColor: AppColors.anchorRed),
            child: const Text('归档'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    try {
      await DiaryRepositoryScope.of(context).archiveDay(_date);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.maybeOf(context)
          ?.showSnackBar(SnackBar(content: Text('归档失败：$error')));
      return;
    }
    if (mounted) Navigator.of(context).maybePop();
  }

  Future<void> _flushSave() async {
    _saveTimer?.cancel();
    _saveTimer = null;
    if (!_controller.dirty.value || _readOnly) return;
    final document = _controller.snapshotDocument();
    // 待启用的空段时间戳不写文件（只在 UI 显示）；有内容的段时间戳正常落盘。
    await DiaryRepositoryScope.of(context).upsertDraft(
      _composer?.prunedForPersist(document) ?? document,
    );
    _controller.markClean();
    if (mounted) setState(() => _savedAt = DateTime.now());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // 进后台/切走立即落盘，不赌防抖计时。
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden ||
        state == AppLifecycleState.inactive) {
      _flushSave();
    }
  }

  @override
  Widget build(BuildContext context) {
    final title = SySerializer.dayTitle(_date);
    return PopScope(
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) _flushSave();
      },
      child: DiaryShell(
        kicker: 'DIARY // ${widget.year}.${widget.month}.${widget.day}',
        title: title,
        onBack: () => Navigator.of(context).maybePop(),
        trailing: _archived
            ? null
            : Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  EditorHistoryButtons(controller: _controller),
                  const SizedBox(width: 10),
                  ValueListenableBuilder<bool>(
                    valueListenable: _controller.dirty,
                    builder: (context, dirty, _) => _SaveChip(
                      loaded: _loaded,
                      dirty: _loaded && dirty,
                      savedAt: _savedAt,
                      readOnly: _readOnly,
                    ),
                  ),
                  // 仅 exported 只读态提供「归档」动作（draft 不可归档）。
                  if (_loaded && _readOnly)
                    TextButton.icon(
                      onPressed: _confirmArchive,
                      icon: const Icon(Icons.archive_outlined, size: 15),
                      label: const Text('归档'),
                      style: TextButton.styleFrom(
                        foregroundColor: AppColors.pageLabel,
                        textStyle: const TextStyle(
                          fontSize: 11,
                          letterSpacing: 1.2,
                        ),
                        visualDensity: VisualDensity.compact,
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        minimumSize: const Size(0, 28),
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                    ),
                ],
              ),
        child: !_loaded
            ? const Center(
                child: Padding(
                  padding: EdgeInsets.all(16),
                  child: SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                ),
              )
            : _archived
            ? const _ArchivedPlaceholder()
            : BlockEditorScope(
                controller: _controller,
                child: Column(
                  children: [
                    if (widget.unsupportedBlockTypes.isNotEmpty)
                      const _NoticeBanner(text: '含暂不支持的块，已只读展示'),
                    if (_readOnly) const _NoticeBanner(text: '已导出 · 只读'),
                    Expanded(
                      child: BlockEditorView(
                        // 2026-10-18 紧凑化：去掉列表顶部内边距，正文区上沿
                        // 随标题下留白一并上移（底部保留 8dp 收尾间隔）。
                        contentPadding: const EdgeInsets.only(bottom: 8),
                        header: DiaryCapsuleRow(
                          controller: _controller,
                          refreshing: _refreshing,
                          onRefreshData: _readOnly ? null : _refreshData,
                          onPickMood: _readOnly ? null : _pickMood,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
      ),
    );
  }

  @override
  void dispose() {
    _saveTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    _controller.dirty.removeListener(_onDirtyChanged);
    _controller.dispose();
    super.dispose();
  }
}

/// 右上角保存状态：固定 16×16 图标位——灰圈=草稿、转圈=编辑中、
/// 绿圈打钩=已保存（tooltip 带保存时刻）。宽度不随状态变化，
/// 同一行的心情/撤销/重做按钮不会被挤得左右移动。
/// 只读态是静态文本，不参与编辑期状态轮换，无动态位移。
class _SaveChip extends StatelessWidget {
  const _SaveChip({
    required this.loaded,
    required this.dirty,
    required this.savedAt,
    required this.readOnly,
  });

  final bool loaded;
  final bool dirty;
  final DateTime? savedAt;
  final bool readOnly;

  @override
  Widget build(BuildContext context) {
    if (readOnly) {
      return Text(
        '只读',
        style: TextStyle(
          fontSize: 11,
          letterSpacing: 1.5,
          color: AppColors.textMuted,
        ),
      );
    }
    if (!loaded) {
      return const SizedBox(width: 16, height: 16);
    }
    if (dirty) {
      return const SizedBox(
        width: 16,
        height: 16,
        child: Center(
          child: SizedBox(
            width: 14,
            height: 14,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: AppColors.accentBlue,
            ),
          ),
        ),
      );
    }
    if (savedAt != null) {
      final hh = savedAt!.hour.toString().padLeft(2, '0');
      final mm = savedAt!.minute.toString().padLeft(2, '0');
      return Tooltip(
        message: '已保存 $hh:$mm',
        child: Icon(Icons.check_circle, size: 16, color: AppColors.anchorGreen),
      );
    }
    return Icon(
      Icons.radio_button_unchecked,
      size: 16,
      color: AppColors.textMuted,
    );
  }
}

/// 顶部提示横幅（暂不支持块 / 只读锁定）。
class _NoticeBanner extends StatelessWidget {
  const _NoticeBanner({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      decoration: BoxDecoration(
        color: AppColors.tone1,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.tone2),
      ),
      child: Text(
        text,
        style: const TextStyle(
          fontSize: 12,
          color: AppColors.pageLabel,
          letterSpacing: 0.5,
        ),
      ),
    );
  }
}

/// 已归档日期的占位页：正文已从本机清理，仅留索引，不可再打开编辑。
class _ArchivedPlaceholder extends StatelessWidget {
  const _ArchivedPlaceholder();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.inventory_2_outlined,
              size: 34,
              color: AppColors.mechInkDim,
            ),
            const SizedBox(height: 14),
            const Text(
              '已归档',
              style: TextStyle(
                fontSize: 15,
                letterSpacing: 4,
                color: AppColors.pageLabel,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              '正文已从本机清理，仅保留日期索引',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 12,
                height: 1.6,
                color: AppColors.mechInkDim.withValues(alpha: 0.8),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
