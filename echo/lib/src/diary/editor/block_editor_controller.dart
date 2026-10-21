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
  }) : _ids = idGenerator,
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

  /// 待启用 = 该时间戳的段内目前没有任何用户内容（时间尚未锚定）。
  ///
  /// 按 stamp id 记录，支持同时存在多个待启用时间戳；`pendingStamp`
  /// 保留原语义，只回答「最后一个时间戳是否待启用」。
  ///
  /// 待启用语义（2026-10-19 用户裁定）：该时间戳不落盘（只存在于 UI，
  /// 下次进编辑页重新生成），且用户在本段输入**第一个字符**时重打点为
  /// 当前时间；此后不再自动更新，直到内容再次被清空。
  final Set<String> _pendingStampIds = <String>{};

  /// 「最后一个时间戳是否待启用」只读视图（测试与诊断用）。
  bool get pendingStamp {
    final index = _lastStampIndex();
    return index >= 0 &&
        _pendingStampIds.contains(_states[index].block.id);
  }

  /// 全部待启用时间戳 id 的只读视图（测试与诊断用）。
  Set<String> get pendingStampIds => Set<String>.unmodifiable(_pendingStampIds);

  /// 当前选中块（块标点击）；null 无选中。
  String? selectedBlockId;

  /// 文档是否整体锁定（导出后只读）。
  bool get locked => _doc?.locked ?? false;

  /// 文档级 custom-* 属性只读视图（M5：custom-mood 心情等）。
  Map<String, String> get documentCustom =>
      Map<String, String>.unmodifiable(_doc?.custom ?? const {});

  /// 设置或移除文档级 custom-* 属性（M5 心情入口）。
  ///
  /// 与正文编辑同纪律：改 [DiaryDocument.custom] 后置 dirty，走编辑页
  /// 防抖落盘链路；[value] 为 null 时移除该键。文档未挂载或锁定
  /// （导出只读）时 no-op，值未变化时不产生脏标记。
  void setDocumentCustom(String key, String? value) {
    final doc = _doc;
    if (doc == null || locked) return;
    if (value == null) {
      if (!doc.custom.containsKey(key)) return;
      doc.custom.remove(key);
    } else {
      if (doc.custom[key] == value) return;
      doc.custom[key] = value;
    }
    _markDirty();
    notifyListeners();
  }

  /// 批量写入/移除文档级 custom-* 属性（胶囊行数据刷新用）。
  ///
  /// 与 [setDocumentCustom] 同纪律：文档未挂载或锁定（导出只读）时
  /// no-op；[patch] 中值为 null 的键移除；任一键实际变化才置 dirty 并
  /// 通知，全无变化时不产生脏标记。**不压撤销快照**——数据刷新是系统
  /// 动作，不进用户撤销链。
  void applyCustomPatch(Map<String, String?> patch) {
    final doc = _doc;
    if (doc == null || locked) return;
    var changed = false;
    patch.forEach((key, value) {
      if (value == null) {
        if (doc.custom.remove(key) != null) changed = true;
      } else if (doc.custom[key] != value) {
        doc.custom[key] = value;
        changed = true;
      }
    });
    if (!changed) return;
    _markDirty();
    notifyListeners();
  }

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
  ///
  /// 挂载时校验段结构：每个时间戳后缺正文块则补一个空段落。
  /// 返回 `true` 表示补齐改动了文档，调用方需立即落盘。
  bool attach(DiaryDocument document) {
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
    final changed = _normalizeSegments();
    if (changed) {
      _syncDocBlocks();
      _markDirty();
    }
    _initStampPending();
    return changed;
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
  //  待启用时间戳（空段不落盘 + 首次输入重打点）
  // ================================================================

  /// 挂载/撤销恢复后按当前块内容初始化「待启用」集合（不重打点）。
  ///
  /// 所有段内为空的 stamp 都进入待启用——不只最后一个。这样删除末段
  /// 时间戳后，上一段（原本为空、下方有正文）才有机会在内容归属变化时
  /// 重新锚定时间（2026-10-21 用户报告）。
  void _initStampPending() {
    _pendingStampIds.clear();
    for (var i = 0; i < _states.length; i++) {
      if (_states[i].block.isStamp && _segmentEmpty(i)) {
        _pendingStampIds.add(_states[i].block.id);
      }
    }
  }

  /// 最后一个时间戳块的状态下标；无时间戳返回 -1。
  int _lastStampIndex() {
    for (var i = _states.length - 1; i >= 0; i--) {
      if (_states[i].block.isStamp) return i;
    }
    return -1;
  }

  /// 时间戳块 [stampIndex] 的段内是否没有任何用户内容（非 stamp 块全空）。
  bool _segmentEmpty(int stampIndex) {
    for (var i = stampIndex + 1; i < _states.length; i++) {
      final state = _states[i];
      if (state.block.isStamp) break;
      if (state.controller.text.trim().isNotEmpty) return false;
    }
    return true;
  }

  /// 补齐每个时间戳段：stamp 位于末尾、或下一块仍是 stamp 时插入空段落。
  ///
  /// 「每个超级块至少有一行时间戳块和一行正文块」（2026-10-21 用户裁定）。
  /// 只补正文，绝不凭空创建新 stamp；锁定文档不处理。
  /// 返回 true 表示块列表发生变化（调用方负责 sync + 置脏）。
  bool _normalizeSegments() {
    if (locked) return false;
    var changed = false;
    for (var i = 0; i < _states.length; i++) {
      if (!_states[i].block.isStamp) continue;
      final next = i + 1;
      if (next < _states.length && !_states[next].block.isStamp) continue;

      final block = DiaryBlock(id: _ids.next(), text: '', updatedAt: _now());
      final state = BlockState(block)..lastValue = const TextEditingValue();
      state.controller.addListener(() => _onBlockText(state));
      _states.insert(next, state);
      changed = true;
      i = next;
    }
    return changed;
  }

  /// 内容/结构变化后全量校准「待启用」集合。
  ///
  /// * 段内为空 → 保持/进入待启用，时间戳文本暂不改变；
  /// * 段内已有内容且此前待启用 → 重打点为当前时间并移出集合
  ///   （用户原话：输入第一个字符时更新到「动笔时间」，此后冻结）；
  /// * 段内容再次清空 → 下次校准重新进入待启用，再次输入时重新打点。
  ///
  /// 删除时间戳后，其下一段正文并入上一段：若上一段此前为空且处于
  /// 待启用态，这里会把它重打点为当前时间（本次 bug 的修复点）。
  void _reconcilePendingStamps() {
    final present = <String>{};
    for (var i = 0; i < _states.length; i++) {
      final state = _states[i];
      if (!state.block.isStamp) continue;
      final id = state.block.id;
      present.add(id);

      if (_segmentEmpty(i)) {
        _pendingStampIds.add(id);
        continue;
      }
      if (_pendingStampIds.remove(id)) {
        _restampStamp(i);
      }
    }
    // 已删除的 stamp 从集合中清理。
    _pendingStampIds.removeWhere((id) => !present.contains(id));
  }

  /// 把时间戳块改写为当前时间（用户输入首个字符的「动笔时间」）。
  void _restampStamp(int stampIndex) {
    final state = _states[stampIndex];
    final now = _now();
    final text = formatDiaryStamp(now);
    if (state.block.text == text) return;
    applyValue(state, text, TextSelection.collapsed(offset: text.length));
    state.block.updatedAt = now;
    notifyListeners();
  }

  // ================================================================
  //  文本变更主通道（IME delta，兼容各类软键盘）
  // ================================================================

  void _onBlockText(BlockState state) {
    final newValue = state.controller.value;
    final oldValue = state.lastValue;
    state.lastValue = newValue;
    if (state.suppress) return;
    if (locked) return;
    if (identical(newValue, oldValue)) return;

    final oldText = oldValue.text;
    final newText = newValue.text;
    if (newText == oldText) return;

    // 拼音等组词进行中：只同步文本，绝不拆块（Enter 此时只负责上屏）。
    if (newValue.composing.isValid) {
      state.block.text = newText;
      _markDirty();
      _reconcilePendingStamps();
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
      _reconcilePendingStamps();
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
    _normalizeSegments();
    _syncDocBlocks();

    // 依据新坐标把光标落到对应块（处理在段中回车/粘贴中段的情况）。
    final maxOffset = texts.fold<int>(0, (n, t) => n + t.length + 1) - 1;
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
    _reconcilePendingStamps();
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
    if (locked) return false;
    final selection = state.controller.selection;
    if (!selection.isCollapsed || selection.baseOffset != 0) {
      return false;
    }
    final index = _states.indexOf(state);
    if (index <= 0) return false;

    final prev = _states[index - 1];
    // 上一块是时间戳块：一律不拦截——既不允许把正文并入只读的时间戳块，
    // 也保证每个段的第一个正文行不被删掉（否则段尾只剩时间戳、无输入位）。
    if (prev.block.isStamp) return false;
    // 整篇仅剩一个空块：不删除。
    if (state.block.text.isEmpty && _states.length <= 1) return false;

    _pushSnapshot();
    if (state.block.text.isEmpty) {
      // 空块：删除自身，焦点落上一块末尾。
      _states.removeAt(index);
      state.dispose();
      _normalizeSegments();
      _syncDocBlocks();
      _markDirty();
      _reconcilePendingStamps();
      notifyListeners();
      _postFocus(prev, prev.controller.text.length);
    } else {
      // 非空块：与上一块合并，保留上一块 ID/种类。
      final caret = prev.controller.text.length;
      final merged = prev.block.text + state.block.text;
      _states.removeAt(index);
      state.dispose();
      applyValue(prev, merged, TextSelection.collapsed(offset: caret));
      _normalizeSegments();
      _syncDocBlocks();
      _markDirty();
      _reconcilePendingStamps();
      notifyListeners();
      _postFocus(prev, caret);
    }
    return true;
  }

  /// ↑/↓ 越界跳焦；返回 true 表示已拦截。
  ///
  /// 跳过只读的时间戳块：向上取最近的前一个非 stamp 块，向下取最近的
  /// 后一个非 stamp 块；找不到（该方向只剩时间戳或已到边界）返回 false。
  bool handleVerticalMove(BlockState state, {required bool up}) {
    final index = _states.indexOf(state);
    if (up) {
      if (state.controller.selection.baseOffset != 0) return false;
      for (var i = index - 1; i >= 0; i--) {
        if (_states[i].block.isStamp) continue;
        _postFocus(_states[i], _states[i].controller.text.length);
        return true;
      }
      return false;
    } else {
      if (state.controller.selection.baseOffset !=
          state.controller.text.length) {
        return false;
      }
      for (var i = index + 1; i < _states.length; i++) {
        if (_states[i].block.isStamp) continue;
        _postFocus(_states[i], 0);
        return true;
      }
      return false;
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
    if (locked) return;
    // 时间戳块只读，无排版入口（UI 亦无入口，防御）。
    if (state.block.isStamp) return;
    if (kind == DiaryBlockKind.heading &&
        (level == null || level < 1 || level > 3)) {
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
    if (locked) return;
    // 时间戳块只读，无底色入口（UI 亦无入口，防御）。
    if (state.block.isStamp) return;
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

  /// 删除整块（块标菜单「删除」）。时间戳块同样可删。
  ///
  /// 生效时压一次撤销快照；删空后补一个空段落，保证文档始终有可输入块。
  /// 若删除后某段时间戳后不再有正文块，自动补一个空段落。
  /// 焦点落到删除位置之后最近的正文块（没有则之前），避免悬空。
  void deleteBlock(BlockState state) {
    if (locked) return;
    final index = _states.indexOf(state);
    if (index < 0) return;
    final id = state.block.id;
    _pushSnapshot();
    _states.removeAt(index);
    state.dispose();
    if (_states.isEmpty) {
      final block = DiaryBlock(id: _ids.next(), text: '', updatedAt: _now());
      final blank = BlockState(block)
        ..lastValue = const TextEditingValue();
      blank.controller.addListener(() => _onBlockText(blank));
      _states.add(blank);
    }
    if (selectedBlockId == id) selectedBlockId = null;
    _normalizeSegments();
    _syncDocBlocks();
    _markDirty();
    _reconcilePendingStamps();
    notifyListeners();

    BlockState? focus;
    for (var i = index; i < _states.length; i++) {
      if (!_states[i].block.isStamp) {
        focus = _states[i];
        break;
      }
    }
    if (focus == null) {
      for (var i = index - 1; i >= 0; i--) {
        if (!_states[i].block.isStamp) {
          focus = _states[i];
          break;
        }
      }
    }
    if (focus != null) _postFocus(focus, 0);
  }

  /// debug 测试入口：在光标所在块的下一行插入一个「时间戳段」。
  ///
  /// 仅供 debug 包竖单按钮使用（release 不暴露入口）。与成稿期的
  /// `DiaryComposer.ensureStamp` 不同，这里不做 30 分钟复用判定，直接以
  /// 当前时间打点，便于在文档任意位置快速造出一个新超级块观察段框。
  ///
  /// 光标块按「获得焦点的块 → 块标选中的块 → 最后一个正文块」回退；
  /// 锁定文档或没有任何可插入位置时返回 false。
  bool insertStampBelowCursor() {
    if (locked) return false;

    var index = -1;
    for (var i = 0; i < _states.length; i++) {
      if (_states[i].focusNode.hasFocus) {
        index = i;
        break;
      }
    }
    if (index < 0) {
      final selected = selectedBlockId;
      if (selected != null) {
        index = _states.indexWhere((s) => s.block.id == selected);
      }
    }
    if (index < 0) {
      for (var i = _states.length - 1; i >= 0; i--) {
        if (!_states[i].block.isStamp) {
          index = i;
          break;
        }
      }
    }
    if (index < 0) return false;

    _pushSnapshot();
    final now = _now();
    final stampBlock = DiaryBlock(
      id: _ids.next(),
      text: formatDiaryStamp(now),
      custom: {kEchoStampAttr: '1'},
      updatedAt: now,
    );
    final bodyBlock = DiaryBlock(id: _ids.next(), text: '', updatedAt: now);
    final stampState = BlockState(stampBlock)
      ..lastValue = const TextEditingValue();
    final bodyState = BlockState(bodyBlock)
      ..lastValue = const TextEditingValue();
    stampState.controller.addListener(() => _onBlockText(stampState));
    bodyState.controller.addListener(() => _onBlockText(bodyState));

    _states.insertAll(index + 1, [stampState, bodyState]);
    _normalizeSegments();
    _syncDocBlocks();
    _markDirty();
    _reconcilePendingStamps();
    notifyListeners();
    // 光标落到新段的正文行，便于立刻输入内容观察段框与待启用行为。
    _postFocus(bodyState, 0);
    return true;
  }

  /// 拖动重排：把 [oldIndex] 处的块搬到 [newIndex]（搬移后的目标下标）。
  ///
  /// [newIndex] 直接采用 `SliverReorderableList.onReorderItem` 的语义——
  /// 框架已替调用方扣除「被拖块移除后列表短一位」的偏移，这里只做越界
  /// 收敛到 `[0, len-1]`。锁定、索引越界或落点未变时 no-op（不压快照、
  /// 不置脏）；生效时先压一次撤销快照再搬移，块对象（ID / 文本控制器 /
  /// 焦点节点）整体随位移动、不重建。
  ///
  /// 时间戳与超级块强相关：拖**时间戳块**时整段一起搬移（时间戳 + 其后
  /// 直到下一个时间戳前的正文块），且**只允许落在段边界**（某时间戳之前、
  /// 文档末尾）——落进其他超级块中间时按拖动方向吸附到最近的边界：
  /// 向下拖吸到该段之后，向上拖吸到该段之前。正文块仍按单块自由移动，
  /// 可以拖进其他段。
  void moveBlockAt(int oldIndex, int newIndex) {
    if (locked) return;
    if (oldIndex < 0 || oldIndex >= _states.length) return;
    final target = newIndex.clamp(0, _states.length - 1);
    if (target == oldIndex) return;

    // 时间戳块携带整段搬移；正文块仍是长度 1 的单块。
    var end = oldIndex;
    if (_states[oldIndex].block.isStamp) {
      while (end + 1 < _states.length && !_states[end + 1].block.isStamp) {
        end++;
      }
    }
    final length = end - oldIndex + 1;
    // 落点仍在本段范围内（含段尾紧邻插槽）：顺序没有变化。
    if (target > oldIndex && target <= end) return;

    // 框架给的目标下标按「只移除被拖的时间戳一块」折算；整段移动时，
    // 向下落要再扣掉段内其余块的数量（向上落则下标原样可用）。
    var insertAt = target < oldIndex ? target : target - (length - 1);
    if (length > 1) {
      insertAt = _snapToSegmentBoundary(
        insertAt,
        oldIndex: oldIndex,
        end: end,
        movingDown: target > oldIndex,
      );
      // 吸附回原位：不产生任何结构变化，不压快照。
      if (insertAt == oldIndex) return;
    }

    _pushSnapshot();
    final moved = _states.sublist(oldIndex, end + 1);
    _states.removeRange(oldIndex, end + 1);
    _states.insertAll(insertAt, moved);
    final now = _now();
    for (final state in moved) {
      state.block.updatedAt = now;
    }
    _normalizeSegments();
    _syncDocBlocks();
    _markDirty();
    _reconcilePendingStamps();
    notifyListeners();
  }

  /// 把整段落点 [insertAt] 收敛到**段边界**，返回在「移除被拖段后」的
  /// 列表里的插入下标。
  ///
  /// 合法边界只有两类：某时间戳块之前（即段的起点）、文档末尾。概述段
  /// （首个时间戳之前）保持恒在顶部，因此不把 0 当作边界。落入其他段
  /// 中间时按拖动方向吸附：向下拖取其后第一个边界（落到该段之后），
  /// 向上拖取其前最后一个边界（落到该段之前）。
  int _snapToSegmentBoundary(
    int insertAt, {
    required int oldIndex,
    required int end,
    required bool movingDown,
  }) {
    final bounds = <int>[];
    var index = 0;
    for (var i = 0; i < _states.length; i++) {
      if (i >= oldIndex && i <= end) continue;
      if (_states[i].block.isStamp) bounds.add(index);
      index++;
    }
    bounds.add(index); // 文档末尾
    if (movingDown) {
      for (final bound in bounds) {
        if (bound >= insertAt) return bound;
      }
      return bounds.last;
    }
    for (final bound in bounds.reversed) {
      if (bound <= insertAt) return bound;
    }
    return bounds.first;
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
    // 恢复态同样校验段结构；只初始化待启用，不在此刻重打点。
    _normalizeSegments();
    _syncDocBlocks();
    _initStampPending();
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
      state.controller.selection = TextSelection.collapsed(
        offset: offset.clamp(0, state.text.length),
      );
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
