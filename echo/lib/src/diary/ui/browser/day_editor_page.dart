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
import '../../template/diary_template.dart';
import '../../../theme/app_colors.dart';
import '../widgets/diary_shell.dart';

/// 单日编辑器页。
///
/// 职责编排：findDay 为空时按 [BlankDiaryTemplate] 建空文档（首次
/// 输入才落盘）；dirty → 5s 防抖 upsert；进后台 / 页面 pop 时立即
/// flush。块结构与输入全部在 [BlockEditorController] 内。
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
  static const Duration _saveDebounce = Duration(seconds: 5);

  final SyIdGenerator _ids = SyIdGenerator();
  late final BlockEditorController _controller = BlockEditorController(
    idGenerator: _ids,
  );
  late final DateTime _date = DateTime(widget.year, widget.month, widget.day);

  DiaryDocument? _document;
  bool _loaded = false;
  bool _loadStarted = false;
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
    final existing = await repository.findDay(_date);
    final document =
        existing ?? const BlankDiaryTemplate().instantiate(_date, _ids);
    _controller.attach(document);
    _controller.dirty.addListener(_onDirtyChanged);
    _document = document;
    if (mounted) setState(() => _loaded = true);

    // 新建空文档：自动聚焦首块，点进日期即可输入（不立即落盘）。
    if (existing == null && _controller.blocks.isNotEmpty) {
      final first = _controller.blocks.first;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && first.focusNode.context != null) {
          first.focusNode.requestFocus();
        }
      });
    }
  }

  void _onDirtyChanged() {
    if (!_controller.dirty.value || _readOnly) return;
    _saveTimer?.cancel();
    _saveTimer = Timer(_saveDebounce, _flushSave);
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
        trailing: Row(
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
