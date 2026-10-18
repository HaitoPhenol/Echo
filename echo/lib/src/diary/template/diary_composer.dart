import '../data/diary_data_provider.dart';
import '../data/diary_repository.dart';
import '../sy/diary_model.dart';
import '../sy/sy_id.dart';
import 'daily_default_template.dart';
import 'diary_template_json.dart';

/// 日记成稿编排器（tech-plan §5；2026-10-18 模板重设后）。
///
/// 职责：
/// - [ensureDay]：命中已有草稿直接返回；否则模板实例化 + 拉 provider
///   写文档根 custom-* 并立即落盘。按日记日缓存 in-flight Future，
///   模块预热与快速点进并发时也只成稿一次。
/// - [ensureStamp]：确保存在「当前段」时间戳块（距上次 ≥ 30 分钟才新建），
///   由编辑页入口触发；[ensureDay] 本身不生成时间戳。
/// - [fetchCustomPatch]：取数纯逻辑（三源并发、互不连坐），返回文档根
///   custom-* 增删面；成稿与编辑页胶囊行点按刷新共用。
/// - [isUserEmpty]：跨天清理的「什么都没写」判定（跳过时间戳块）。
class DiaryComposer {
  DiaryComposer({
    required this.template,
    required this.provider,
    required SyIdGenerator idGenerator,
    DateTime Function()? now,
  }) : _ids = idGenerator,
       _now = now ?? DateTime.now;

  final DailyDefaultTemplate template;
  final DiaryDataProvider provider;
  final SyIdGenerator _ids;
  final DateTime Function() _now;

  /// 时间戳复用窗口：距**最后一个**时间戳块的 `updatedAt` 不足此时长即
  /// 复用不新建（用户裁定 30 分钟）。用 stamp 自身的 `updatedAt` 判定而
  /// 非解析文本——stamp 只读、后文编辑不会改写它（plan 决策 7）。
  static const Duration stampReuseWindow = Duration(minutes: 30);

  /// key = yyyymmdd；同一日记日的成稿 Future 去重。
  final Map<int, Future<DiaryDocument>> _inFlight = {};

  static int _dayKey(DateTime d) => d.year * 10000 + d.month * 100 + d.day;

  // ================================================================
  //  时间戳段编排（2026-10-18 进入编辑页时触发）
  // ================================================================

  /// 「一句话概述今日」段底色号（参考模板 12 号底色）。
  ///
  /// 该段是模板骨架的首块（普通可编辑段落，非时间戳），导出时落在首行
  /// 胶囊超级块与首个时间戳段之间（`SySerializer._rowSegments` 的
  /// 「首个 stamp 前散块」路径）。
  static const int summaryBackground = 12;

  /// 判定某块是否为「一句话概述今日」段：首块位置上的 12 号底色段落。
  static bool isSummaryBlock(DiaryBlock block) =>
      !block.isStamp &&
      block.kind == DiaryBlockKind.paragraph &&
      block.background == summaryBackground;

  /// 确保文档存在「一句话概述今日」段与「当前段」的时间戳块。
  ///
  /// * 「概述段」（[summaryBackground] 段落）恒在文档首位：模板骨架自带，
  ///   旧稿（早于本机制）缺失时在此补建；
  /// * 时间戳：取文档中**最后一个** [DiaryBlock.isStamp] 块——
  ///   - 不存在 → 新建 stamp **插到索引 1**（概述段之后，模板原有的那个
  ///     空段落即成为本段正文行，见 plan 决策 13）；
  ///   - 存在且 `_now() - last.updatedAt < [stampReuseWindow]` → 复用；
  ///   - 存在但已超窗 → 新建 stamp **追加到文档末尾**（开新段），并在其
  ///     后补一个空段落作为新段正文行。
  /// * 无论哪条分支，都保证该 stamp 之后至少有一个非 stamp 块（否则文档
  ///   尾部无任何可输入位置，用户被锁死，见 plan 决策 17）。
  ///
  /// 触发点在**编辑页入口**（用户原话「进入编辑页时会自动生成」）；
  /// [ensureDay] 保持纯成稿语义、不生成时间戳（plan 决策 14）。
  ///
  /// 返回 `true` 表示本次确实改动了文档（新建时间戳，或补齐了缺失的概述
  /// 段）——调用方需落盘并跳焦；`false` 表示复用未改动。
  bool ensureStamp(DiaryDocument document) {
    // 已导出（只读锁定）文档不自动生成时间戳：导出后正文只读、禁止改动，
    // 且仓储禁止覆盖 exported 态（否则 upsertDraft 抛 StateError）。
    if (document.locked) return false;

    final now = _now();
    var changed = false;

    // 1. 确保「一句话概述今日」段恒在首位（模板骨架自带，旧稿补建）。
    if (document.blocks.isEmpty || !isSummaryBlock(document.blocks.first)) {
      document.blocks.insert(
        0,
        DiaryBlock(
          id: _ids.next(),
          background: summaryBackground,
          updatedAt: now,
        ),
      );
      changed = true;
    }

    // 2. 当前段的时间戳：距上次 < 30 分钟则复用。
    DiaryBlock? last;
    for (final block in document.blocks) {
      if (block.isStamp) last = block;
    }
    if (last != null && now.difference(last.updatedAt) < stampReuseWindow) {
      if (changed) document.updatedAt = now;
      return changed;
    }

    final stamp = DiaryBlock(
      id: _ids.next(),
      text: _formatStamp(now),
      custom: {kEchoStampAttr: '1'},
      updatedAt: now,
    );
    // 首段插在概述段之后（索引 1）；换段追加到文档末尾。
    document.blocks.insert(last == null ? 1 : document.blocks.length, stamp);

    final index = document.blocks.indexOf(stamp);
    final hasBodyRow =
        index + 1 < document.blocks.length &&
        !document.blocks[index + 1].isStamp;
    if (!hasBodyRow) {
      document.blocks.insert(
        index + 1,
        DiaryBlock(id: _ids.next(), updatedAt: now),
      );
    }

    document.updatedAt = now;
    return true;
  }

  /// 时间戳文本：`yyyy-MM-dd HH:mm`（年月日时分，用户原话）。
  ///
  /// 与参考样本（带秒 `yyyy-MM-dd HH:mm:ss`）不同——如后续要秒仅改此处。
  static String _formatStamp(DateTime t) {
    String p(int value, int width) => value.toString().padLeft(width, '0');
    return '${p(t.year, 4)}-${p(t.month, 2)}-${p(t.day, 2)} '
        '${p(t.hour, 2)}:${p(t.minute, 2)}';
  }

  /// 确保某日记日已有草稿：有则原样返回，无则成稿落盘后返回。
  ///
  /// [date] 允许带时分秒（内部归一）。晚于仓储时钟「今天」的未来日期
  /// 抛 [ArgumentError]——M4 不提供任何未来日期入口（补记选择器亦禁选）。
  Future<DiaryDocument> ensureDay(
    DateTime date,
    DiaryRepository repository,
  ) async {
    final day = DateTime(date.year, date.month, date.day);
    if (day.isAfter(repository.today())) {
      throw ArgumentError.value(date, 'date', '不能为未来日记日自动成稿');
    }

    final key = _dayKey(day);
    final inflight = _inFlight[key];
    if (inflight != null) return inflight;

    // _compose 同步执行到首个 await 前完成 Map 注册，并发调用必见同一 Future。
    final future = _compose(day, repository);
    _inFlight[key] = future;
    try {
      return await future;
    } finally {
      _inFlight.remove(key);
    }
  }

  Future<DiaryDocument> _compose(
    DateTime day,
    DiaryRepository repository,
  ) async {
    final existing = await repository.findDay(day);
    if (existing != null) return existing;
    // M5：findDay 为 null 仍可能是「正文已清除的 archived」——
    // 有 meta 即历史日记，禁止模板复活（UI 对 archived 走占位页）。
    if (await repository.dayExists(day)) {
      throw StateError('该日记已归档（本机正文已清除），不能重新成稿：$day');
    }

    final document = template.instantiate(day, _ids);
    final patch = await fetchCustomPatch(day);
    patch.forEach((key, value) {
      if (value != null) document.custom[key] = value;
    });
    document.updatedAt = _now();
    await repository.upsertDraft(document);
    return document;
  }

  // ================================================================
  //  取数（文档根 custom-* 数据面）
  // ================================================================

  /// 构造一篇「骨架态空稿」：与 [ensureDay] 走**同一**模板实例化
  /// （只差未拉 custom-*），故 [isUserEmpty] 必判为空。
  ///
  /// 注：模板骨架为「一句话概述今日」段（12 号底色）+ 一个空正文段，
  /// **不含时间戳块**——时间戳由编辑页入口调 [ensureStamp] 生成
  /// （用户原话「进入编辑页时会自动生成」）。
  ///
  /// `diary.seed` 造空稿专用——保证「空稿形状」与 prune 判定同源，
  /// 命令层不得自创「空」定义（否则 prune 认不得，端到端验证失效）。
  DiaryDocument buildEmptyDraft(DateTime date) {
    final day = DateTime(date.year, date.month, date.day);
    return template.instantiate(day, _ids);
  }

  /// 拉取三个数据源（互不连坐）并产出文档根 custom-* 增删面。
  ///
  /// patch 值为 `null` 表示该源本次不可用（调用方应从 custom 移除该键）。
  /// 成稿（[_compose]）与编辑页胶囊行点按刷新共用同一入口，保证两路
  /// 数据口径完全一致。
  Future<Map<String, String?>> fetchCustomPatch(DateTime diaryDate) async {
    final day = DateTime(diaryDate.year, diaryDate.month, diaryDate.day);

    HomeEnvironment? env;
    int? scheduleCount;
    String? weather;
    await Future.wait<void>([
      provider
          .fetchHomeEnvironment(day)
          .then((v) => env = v)
          .catchError((Object _) => null),
      provider
          .fetchScheduleCount(day)
          .then((v) => scheduleCount = v)
          .catchError((Object _) => null),
      provider
          .fetchWeather(day)
          .then((v) => weather = v)
          .catchError((Object _) => null),
    ]);

    final patch = <String, String?>{};

    if (env != null) {
      patch['custom-iot-temp'] = _formatNum(env!.tempC);
      patch['custom-iot-humidity'] = '${env!.humidityPct}';
    } else {
      patch['custom-iot-temp'] = null;
      patch['custom-iot-humidity'] = null;
    }

    patch['custom-schedule-count'] = scheduleCount == null
        ? null
        : '$scheduleCount';

    final weatherText = weather?.trim();
    patch['custom-weather'] = (weatherText != null && weatherText.isNotEmpty)
        ? weatherText
        : null;

    return patch;
  }

  static String _formatNum(double v) =>
      v == v.roundToDouble() ? v.toInt().toString() : v.toString();

  // ================================================================
  //  跨天清理判定（§5.2 第 4 条）
  // ================================================================

  /// 判定一篇成稿是否「什么都没写」：
  ///
  /// 1. 自动生成的时间戳块（[DiaryBlock.isStamp]）一律跳过——它是骨架
  ///    自动产物，不代表用户写了字；
  /// 2. 与模板骨架声明（heading/paragraph）多重集等价的块忽略；
  /// 3. 其余块中存在任一 trim 后非空文本即非空。
  ///
  /// 用户写了字又删光 → 文本归空 → 仍判为空，次日照常清理。
  ///
  /// 自动数据与心情只存文档根 custom-*、不占块，故天然不参与本判定。
  bool isUserEmpty(DiaryDocument document) {
    final expected = template.spec.blocks.map(_specKey).toList();

    for (final block in document.blocks) {
      if (block.isStamp) continue;
      final key = (kind: block.kind, level: block.level, text: block.text);
      final match = expected.indexOf(key);
      if (match >= 0) {
        expected.removeAt(match);
        continue;
      }
      if (block.text.trim().isNotEmpty) return false;
    }
    return true;
  }

  /// 模板声明到块等价键。
  static ({DiaryBlockKind kind, int? level, String text}) _specKey(
    DiaryTemplateBlockSpec spec,
  ) {
    return switch (spec.type) {
      DiaryTemplateBlockType.heading => (
        kind: DiaryBlockKind.heading,
        level: spec.level,
        text: spec.text,
      ),
      DiaryTemplateBlockType.paragraph => (
        kind: DiaryBlockKind.paragraph,
        level: null,
        text: spec.text,
      ),
    };
  }
}
