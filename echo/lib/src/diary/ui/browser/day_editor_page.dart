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
import '../../../theme/app_colors.dart';
import '../diary_composer_scope.dart';
import '../widgets/diary_mood_picker.dart';
import '../widgets/diary_shell.dart';

/// 单日编辑器页。
///
/// 职责编排：加载统一走 composer.ensureDay（命中草稿直接打开，无则
/// 模板成稿并落盘，补记过去空日同样进入即成稿）；dirty → 1.5s 防抖
/// upsert（M5 崩溃恢复口径，硬杀最多损失 1.5s）；进后台 / 页面 pop
/// 时立即 flush。data 块的 ↻ 刷新经 composer.fetchSnapshot +
/// 控制器 replaceDataSnapshot。
class DayEditorPage extends StatefulWidget {
  const DayEditorPage({
    super.key,
    required this.year,
    required this.month,
    required this.day,
    this.unsupportedBlockTypes = const [],
  });

  final int year;
  final int month;
  final int day;

  /// 回读含子集外块类型时传入（M5 导入链路使用；M2 恒空），
  /// 页面顶部出只读提示横幅。参数先就位，避免未来改构造签名。
  final List<String> unsupportedBlockTypes;

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
    // 先探一次：区分「新开/补记」（自动聚焦首个可写空段）与翻旧稿。
    final existedBefore = await repository.findDay(_date);
    final document = await composer.ensureDay(_date, repository);
    _controller.attach(document);
    // 导出只读态不提供 ↻ data 刷新（块组件自身也按 locked 隐藏入口，
    // 这里不挂回调，双保险且语义干净）。
    if (!document.locked) {
      _controller.dataRefresher = (state) async {
        final snapshot = await composer.fetchSnapshot(_date);
        _controller.replaceDataSnapshot(
          blockId: state.block.id,
          text: snapshot.text,
          customPatch: snapshot.customPatch,
        );
      };
    }
    _controller.dirty.addListener(_onDirtyChanged);
    _document = document;
    if (mounted) setState(() => _loaded = true);

    // 新成稿：聚焦第一个「可写空段」（跳过标题与 readonly data 块）。
    if (existedBefore == null) {
      BlockState? target;
      for (final state in _controller.blocks) {
        final block = state.block;
        if (!block.readonly &&
            block.kind == DiaryBlockKind.paragraph &&
            block.text.trim().isEmpty) {
          target = state;
          break;
        }
      }
      if (target != null) {
        final focus = target.focusNode;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted && focus.context != null) focus.requestFocus();
        });
      }
    }
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
    await DiaryRepositoryScope.of(context).upsertDraft(document);
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
                  if (_loaded)
                    DiaryMoodChip(controller: _controller, onPick: _pickMood),
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
                    Expanded(child: BlockEditorView()),
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

/// 右上角保存状态：编辑中 / 已保存时间 / 只读。
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
    final String label;
    final Color color;
    if (readOnly) {
      label = '只读';
      color = AppColors.textMuted;
    } else if (!loaded) {
      label = '';
      color = AppColors.textMuted;
    } else if (dirty) {
      label = '编辑中';
      color = AppColors.accentBlue;
    } else if (savedAt != null) {
      final hh = savedAt!.hour.toString().padLeft(2, '0');
      final mm = savedAt!.minute.toString().padLeft(2, '0');
      label = '已保存 $hh:$mm';
      color = AppColors.textMuted;
    } else {
      label = '草稿';
      color = AppColors.textMuted;
    }

    return Text(
      label,
      style: TextStyle(fontSize: 11, letterSpacing: 1.5, color: color),
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
