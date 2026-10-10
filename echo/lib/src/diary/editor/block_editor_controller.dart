import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../sy/diary_model.dart';
import '../sy/sy_id.dart';
import '../sy/sy_serializer.dart';
import 'block_commands.dart';

/// 一个块在编辑期的运行时状态：M1 不可变-ish 模型 [DiaryBlock]
/// （字段可写）+ 每块各自的文本控制器与焦点节点。
///
/// 块结构以模型为准；[controller] 只服务输入与光标，任何程序化
/// 改写都必须经过 [BlockEditorController.applyValue]，避免监听回环。
class BlockState {
  BlockState(this.block)
      : controller = TextEditingController(text: block.text),
        focusNode = FocusNode(debugLabel: 'diary-block-${block.id}');

  DiaryBlock block;
  final TextEditingController controller;
  final FocusNode focusNode;

  /// 监听器已知的上一次值，用于 diff 出本次插入/删除区间。
  TextEditingValue lastValue = TextEditingValue.empty;

  /// true 期间控制器监听只同步模型、不做结构操作（程序化赋值）。
  bool suppress = false;

  String get text => block.text;

  void dispose() {
    controller.dispose();
    focusNode.dispose();
  }
}

/// 块编辑器控制器：块结构操作的唯一入口。
///
/// 不依赖任何存储概念（仓储/文件），可纯单测；自动保存由编辑页
/// 监听 [dirty] 编排。结构命令（转标题/底色）M2 已实现，M3 挂 UI。
class BlockEditorController extends ChangeNotifier {
  BlockEditorController({
    required SyIdGenerator idGenerator,
    int maxHistory = 50,
    SySerializer? serializer,
    DateTime Function()? now,
  })  : _ids = idGenerator,
        // ignore: prefer_initializing_formals
        _maxHistory = maxHistory,
        _serializer = serializer ?? const SySerializer(),
        _now = now ?? DateTime.now;

  final SyIdGenerator _ids;
  final int _maxHistory;
  final SySerializer _serializer;
  final DateTime Function() _now;

  DiaryDocument? _doc;
  final List<BlockState> _states = [];

  final List<String> _undoStack = [];
  final List<String> _redoStack = [];

  final ValueNotifier<bool> _dirty = ValueNotifier<bool>(false);

  /// 有未落盘改动（编辑页据此做防抖保存）。
  ValueListenable<bool> get dirty => _dirty;

  /// 保存完成后清脏（编辑页调用）。
  void markClean() => _dirty.value = false;

  /// 当前选中块（块标点击）；null 无选中。
  String? selectedBlockId;

  /// 文档是否整体锁定（导出后只读）。
  bool get locked => _doc?.locked ?? false;

  /// 块状态有序视图（ListView 用）。
  List<BlockState> get blocks => List<BlockState>.unmodifiable(_states);

  BlockState? blockById(String id) {
    for (final s in _states) {
      if (s.block.id == id) return s;
    }
    return null;
  }

  // ================================================================
  //  挂载 / 卸载
  // ================================================================

  /// 载入文档并为每个块建立运行时状态。
  void attach(DiaryDocument document) {
    if (_states.isNotEmpty) detach();
    _doc = document;
    // 至少保留一个块（空文档打开即可输入）。
    if (document.blocks.isEmpty) {
      document.blocks.add(DiaryBlock(id: _ids.next()));
    }
    _undoStack.clear();
    _redoStack.clear();
    _dirty.value = false;
    for (final block in document.blocks) {
      final state = BlockState(block)
        ..lastValue = TextEditingValue(
          text: block.text,
          selection: const TextSelection.collapsed(offset: 0),
        );
      state.controller.addListener(() => _onBlockText(state));
      _states.add(state);
    }
  }

  /// 文本/结构回灌文档并返回（焦点/控制器随之释放）。
  DiaryDocument detach() {
    final doc = _doc!;
    _syncDocBlocks();
    for (final state in _states) {
      state.dispose();
    }
    _states.clear();
    _doc = null;
    return doc;
  }

  /// 以运行时块状态为准重建文档块列表（新建/删除/合并后调用）。
  void _syncDocBlocks() {
    _doc!.blocks.clear();
    for (final state in _states) {
      state.block.text = state.controller.text;
      _doc!.blocks.add(state.block);
    }
  }

  /// 不落盘地回灌当前内容并返回文档（编辑页防抖保存用，控制器保持挂载）。
  DiaryDocument snapshotDocument() {
    _syncDocBlocks();
    return _doc!;
  }

  // ================================================================
  //  文本变更主通道（IME delta，兼容各类软键盘）
  // ================================================================

  void _onBlockText(BlockState state) {
    final newValue = state.controller.value;
    final oldValue = state.lastValue;
    state.lastValue = newValue;
    if (state.suppress) return;
    if (locked || state.block.readonly) return;
    if (identical(newValue, oldValue)) return;

    final oldText = oldValue.text;
    final newText = newValue.text;
    if (newText == oldText) return;

    // 拼音等组词进行中：只同步文本，绝不拆块（Enter 此时只负责上屏）。
    if (newValue.composing.isValid) {
      state.block.text = newText;
      _markDirty();
      return;
    }

    // diff 出公共前缀/后缀，得到净插入片段与被替换区间。
    final maxCommon = math.min(oldText.length, newText.length);
    var prefix = 0;
    while (prefix < maxCommon && oldText[prefix] == newText[prefix]) {
      prefix++;
    }
    var suffix = 0;
    while (suffix < maxCommon - prefix &&
        oldText[oldText.length - 1 - suffix] ==
            newText[newText.length - 1 - suffix]) {
      suffix++;
    }
    final oldEnd = oldText.length - suffix;
    final inserted = newText.substring(prefix, newText.length - suffix);

    if (!inserted.contains('\n')) {
      state.block.text = newText;
      _markDirty();
      return;
    }

    // 插入片段含换行（软键盘回车 / 粘贴多行）：拆成多个段落块。
    _splitByInsertion(
      state: state,
      prefix: prefix,
      oldTail: oldText.substring(oldEnd),
      parts: inserted.split('\n'),
      caretOffset: newValue.selection.isValid
          ? newValue.selection.baseOffset
          : newText.length,
    );
  }

  void _splitByInsertion({
    required BlockState state,
    required int prefix,
    required String oldTail,
    required List<String> parts,
    required int caretOffset,
  }) {
    final index = _states.indexOf(state);
    // 快照保留当前块的模型旧文本（此刻控制器已是回车后的新值）。
    _pushSnapshot(editingState: state);

    final original = state.block.text;
    final texts = <String>[
      original.substring(0, prefix) + parts.first,
      for (var i = 1; i < parts.length - 1; i++) parts[i],
      parts.last + oldTail,
    ];

    // 前半留在原块（ID/kind/底色不变），其余为新建段落。
    applyValue(
      state,
      texts.first,
      TextSelection.collapsed(offset: texts.first.length),
    );

    final newStates = <BlockState>[];
    for (var i = 1; i < texts.length; i++) {
      final block = DiaryBlock(
        id: _ids.next(),
        kind: DiaryBlockKind.paragraph,
        text: texts[i],
        updatedAt: _now(),
      );
      final newState = BlockState(block)
        ..lastValue = TextEditingValue(text: block.text);
      newState.controller.addListener(() => _onBlockText(newState));
      newStates.add(newState);
    }
    _states.insertAll(index + 1, newStates);
    _syncDocBlocks();

    // 依据新坐标把光标落到对应块（处理在段中回车/粘贴中段的情况）。
    final maxOffset =
        texts.fold<int>(0, (n, t) => n + t.length + 1) - 1;
    var remaining = caretOffset.clamp(0, maxOffset);
    var focusTarget = newStates.isEmpty ? state : newStates.last;
    var focusOffset = 0;
    var consumed = 0;
    final all = [state, ...newStates];
    for (var i = 0; i < all.length; i++) {
      final len = all[i].controller.text.length;
      if (remaining <= consumed + len) {
        focusTarget = all[i];
        focusOffset = remaining - consumed;
        break;
      }
      consumed += len + 1; // 块文本 + 一个被消费的换行
      if (i == all.length - 1) {
        focusTarget = all[i];
        focusOffset = len;
      }
    }
    _markDirty();
    notifyListeners();
    _postFocus(focusTarget, focusOffset);
  }

  // ================================================================
  //  按键通道（文本不发生变化的情形：块首退格、上下越界）
  // ================================================================

  /// 退格键压下时由块组件调用；返回 true 表示已拦截。
  ///
  /// 光标不在块首时不拦截，交 TextField 做普通删除。
  bool handleBackspace(BlockState state) {
    if (locked || state.block.readonly) return false;
    final selection = state.controller.selection;
    if (!selection.isCollapsed || selection.baseOffset != 0) {
      return false;
    }
    final index = _states.indexOf(state);
    if (index <= 0) return false;

    final prev = _states[index - 1];
    if (prev.block.readonly) return false;
    // 整篇仅剩一个空块：不删除。
    if (state.block.text.isEmpty && _states.length <= 1) return false;

    _pushSnapshot();
    if (state.block.text.isEmpty) {
      // 空块：删除自身，焦点落上一块末尾。
      _states.removeAt(index);
      state.dispose();
      _syncDocBlocks();
      _markDirty();
      notifyListeners();
      _postFocus(prev, prev.controller.text.length);
    } else {
      // 非空块：与上一块合并，保留上一块 ID/种类。
      final caret = prev.controller.text.length;
      final merged = prev.block.text + state.block.text;
      _states.removeAt(index);
      state.dispose();
      applyValue(prev, merged, TextSelection.collapsed(offset: caret));
      _syncDocBlocks();
      _markDirty();
      notifyListeners();
      _postFocus(prev, caret);
    }
    return true;
  }

  /// ↑/↓ 越界跳焦；返回 true 表示已拦截。
  bool handleVerticalMove(BlockState state, {required bool up}) {
    final index = _states.indexOf(state);
    if (up) {
      if (index <= 0) return false;
      if (state.controller.selection.baseOffset != 0) return false;
      final prev = _states[index - 1];
      _postFocus(prev, prev.controller.text.length);
      return true;
    } else {
      if (index >= _states.length - 1) return false;
      if (state.controller.selection.baseOffset !=
          state.controller.text.length) {
        return false;
      }
      final next = _states[index + 1];
      _postFocus(next, 0);
      return true;
    }
  }

  // ================================================================
  //  结构命令（M3 接 UI；M2 已实现并测试）
  // ================================================================

  void selectBlock(String? id) {
    if (selectedBlockId == id) return;
    selectedBlockId = id;
    notifyListeners();
  }

  void turnInto(BlockState state, DiaryBlockKind kind, {int? level}) {
    if (locked || state.block.readonly) return;
    if (kind == DiaryBlockKind.heading && (level == null || level < 1 || level > 3)) {
      throw ArgumentError.value(level, 'level', 'Echo 生成标题级别为 1..3');
    }
    if (state.block.kind == kind && state.block.level == level) return;
    _pushSnapshot();
    state.block.kind = kind;
    state.block.level = kind == DiaryBlockKind.heading ? level : null;
    state.block.updatedAt = _now();
    _markDirty();
    notifyListeners();
  }

  /// 设置块底色（1..13）；传 null 清除。
  void setBackground(BlockState state, int? number) {
    if (locked || state.block.readonly) return;
    if (number != null && !BlockBackgroundPalette.isValid(number)) {
      throw ArgumentError.value(number, 'number', '底色色号必须为 1..13');
    }
    if (state.block.background == number) return;
    _pushSnapshot();
    state.block.background = number;
    state.block.updatedAt = _now();
    _markDirty();
    notifyListeners();
  }

  // ================================================================
  //  撤销（结构级；字符级用 TextField 内建 UndoHistory）
  // ================================================================

  bool get canUndo => _undoStack.isNotEmpty;
  bool get canRedo => _redoStack.isNotEmpty;

  void undo() {
    if (_undoStack.isEmpty) return;
    _redoStack.add(_encodeSnapshot());
    _restoreSnapshot(_undoStack.removeLast());
  }

  void redo() {
    if (_redoStack.isEmpty) return;
    _undoStack.add(_encodeSnapshot());
    _restoreSnapshot(_redoStack.removeLast());
  }

  void _pushSnapshot({BlockState? editingState}) {
    _undoStack.add(_encodeSnapshot(editingState: editingState));
    if (_undoStack.length > _maxHistory) _undoStack.removeAt(0);
    _redoStack.clear();
  }

  /// 编码撤销快照。
  ///
  /// [editingState] 为触发结构操作的当前块时，保留其模型文本（操作前
  /// 旧值），其余块取控制器最新文本。
  String _encodeSnapshot({BlockState? editingState}) {
    _doc!.blocks.clear();
    for (final state in _states) {
      if (!identical(state, editingState)) {
        state.block.text = state.controller.text;
      }
      _doc!.blocks.add(state.block);
    }
    return _serializer.encodeJson(_doc!);
  }

  void _restoreSnapshot(String json) {
    final lockedNow = _doc!.locked;
    final readonlyById = {
      for (final s in _states)
        if (s.block.readonly) s.block.id: true,
    };
    final decoded = _serializer.decode(json).document;
    // 解码从 ID 还原出 08:00:00 的容器时刻，重新构造以归一为自然日；
    // locked 是运行时属性（不进 JSON），单独带回。
    final restored = DiaryDocument(
      id: decoded.id,
      date: DateTime(decoded.date.year, decoded.date.month, decoded.date.day),
      title: decoded.title,
      custom: decoded.custom,
      blocks: decoded.blocks,
      updatedAt: decoded.updatedAt,
      locked: lockedNow,
    );
    for (final block in restored.blocks) {
      if (readonlyById[block.id] ?? false) block.readonly = true;
    }
    for (final s in _states) {
      s.dispose();
    }
    _states.clear();
    _doc = restored;
    for (final block in restored.blocks) {
      final state = BlockState(block)
        ..lastValue = TextEditingValue(text: block.text);
      state.controller.addListener(() => _onBlockText(state));
      _states.add(state);
    }
    selectedBlockId = null;
    _markDirty();
    notifyListeners();
    if (_states.isNotEmpty) _postFocus(_states.first, 0);
  }

  // ================================================================
  //  工具
  // ================================================================

  /// 程序化写值（监听抑制 + 模型同步）。
  void applyValue(BlockState state, String text, TextSelection selection) {
    final value = TextEditingValue(
      text: text,
      selection: selection.copyWith(
        baseOffset: selection.baseOffset.clamp(0, text.length),
        extentOffset: selection.extentOffset.clamp(0, text.length),
      ),
    );
    state.suppress = true;
    state.controller.value = value;
    state.suppress = false;
    state.lastValue = value;
    state.block.text = text;
  }

  bool _disposed = false;

  void _postFocus(BlockState state, int offset) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      // 控制器或该块已在帧间销毁（pop/合并）则放弃这次跳焦。
      if (_disposed || state.focusNode.context == null) return;
      state.suppress = true;
      state.controller.selection =
          TextSelection.collapsed(offset: offset.clamp(0, state.text.length));
      state.suppress = false;
      state.focusNode.requestFocus();
    });
  }

  void _markDirty() {
    final now = _now();
    _doc?.updatedAt = now;
    _dirty.value = true;
  }

  @override
  void dispose() {
    _disposed = true;
    for (final s in _states) {
      s.dispose();
    }
    _dirty.dispose();
    super.dispose();
  }
}
