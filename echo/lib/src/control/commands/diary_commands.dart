import '../../diary/data/diary_clock.dart';
import '../../diary/data/diary_repository.dart';
import '../../diary/data/diary_seed_data.dart';
import '../../diary/export/diary_export_service.dart';
import '../../diary/template/diary_composer.dart';
import '../control_registry.dart';
import '../events/event_types.dart';
import '../protocol/command_spec.dart';
import '../protocol/control_error.dart';
import 'control_json.dart';

/// `diary` 命名空间：列表/读取/成稿/跨天清理/清空重置/灌数/打包导出
/// （手册 §5）。`diary.seed` 为 P4 引入的 debug-only 灌数命令。
///
/// 全部走 UI 同源的仓储/composer/导出服务实例（DiaryPage bootstrap
/// 后注册），命令层不直连 sqflite / 文件序列化器。
List<CommandSpec> buildDiaryCommands() => [
  diaryList,
  diaryGet,
  diaryEnsure,
  diaryPrune,
  diaryReset,
  diarySeed,
  diaryExport,
];

/// `diary.list`：按月或全量摘要，倒序 + 不透明游标分页。
final CommandSpec diaryList = CommandSpec(
  namespace: 'diary',
  verb: 'list',
  summary: '日记摘要列表（倒序，游标分页，不解析正文）',
  kind: CommandKind.read,
  level: ControlLevel.owner,
  params: [
    ParamSpec('month', type: ArgType.month, summary: 'YYYY-MM，缺省列全部'),
    ParamSpec('limit', type: ArgType.integer, defaults: 50, summary: '每页条数'),
    ParamSpec('cursor', type: ArgType.string, summary: '上一页返回的不透明游标（yyyymmdd）'),
  ],
  handler: (ctx) async {
    final repo = ctx.requireService<DiaryRepository>('日记仓储');
    final month = ctx.optionalArg<DateTime>('month');
    final limit = ctx.arg<int>('limit');
    if (limit < 1 || limit > 200) {
      throw const ControlException(
        ControlErrorCode.usage,
        '--limit 必须在 1..200 之间',
      );
    }

    final List<DiaryDaySummary> summaries;
    if (month != null) {
      summaries = await repo.daysOfMonth(month.year, month.month);
    } else {
      // 缺省：遍历所有年份的所有月（数据量小；仓储不提供全表接口，
      // 保持读模型与 UI 年→月→日浏览同构）。
      final all = <DiaryDaySummary>[];
      for (final year in await repo.availableYears()) {
        for (final m in await repo.monthsOfYear(year)) {
          all.addAll(await repo.daysOfMonth(year, m));
        }
      }
      summaries = all;
    }
    // 倒序：新日记在前。
    summaries.sort((a, b) => b.date.compareTo(a.date));

    final cursorKey = ctx.optionalArg<String>('cursor');
    var rows = summaries;
    if (cursorKey != null) {
      final cursor = int.tryParse(cursorKey);
      if (cursor == null) {
        throw const ControlException(
          ControlErrorCode.usage,
          '--cursor 必须是上一页原样返回的 yyyymmdd',
        );
      }
      // 游标即上一页最末一项日期键，本页取严格更早者。
      rows = rows
          .where((s) => _dayKey(s.date) < cursor)
          .toList(growable: false);
    }

    final hasMore = rows.length > limit;
    final page = hasMore ? rows.take(limit).toList() : rows;
    return {
      'items': page.map(diarySummaryJson).toList(),
      if (hasMore) 'cursor': _dayKey(page.last.date).toString(),
      'hasMore': hasMore,
    };
  },
);

/// `diary.get`：单篇完整文档；archived 只回状态（正文已物理清除）。
final CommandSpec diaryGet = CommandSpec(
  namespace: 'diary',
  verb: 'get',
  summary: '读取某日完整日记（archived 仅返回状态）',
  kind: CommandKind.read,
  level: ControlLevel.owner,
  params: [
    ParamSpec(
      'date',
      type: ArgType.date,
      required: true,
      summary: 'YYYY-MM-DD',
    ),
  ],
  handler: (ctx) async {
    final repo = ctx.requireService<DiaryRepository>('日记仓储');
    final paths = ctx.service<ControlPaths>();
    final day = _dayOnly(ctx.arg<DateTime>('date'));

    final state = await repo.stateOfDay(day);
    if (state == null) {
      throw ControlException(
        ControlErrorCode.notFound,
        '没有这篇日记：${isoDate(day)}',
      );
    }
    if (state == DiaryDocState.archived) {
      // 归档后正文不在本机：取归档前列表快照补充 title/preview。
      final summary = await _summaryOf(repo, day);
      return {
        'date': isoDate(day),
        'state': state.name,
        if (summary != null) 'title': summary.title,
        if (summary != null) 'preview': summary.preview,
        'blocks': null,
        'filePath': null,
      };
    }

    final doc = await repo.findDay(day);
    if (doc == null) {
      // meta 在但正文文件丢失：按不存在报告，避免返回半截结构。
      throw ControlException(
        ControlErrorCode.notFound,
        '日记正文缺失：${isoDate(day)}',
      );
    }
    final root = paths?.diaryRoot;
    return diaryDocumentJson(
      doc,
      state,
      // 内存仓储（测试）没有文件根；持久仓储路径规则与
      // PersistentDiaryRepository._relativePath 保持一致。
      filePath: root == null
          ? null
          : '${root.path}/diary/${day.year}/'
                '${day.month.toString().padLeft(2, '0')}/${doc.id}.sy',
    );
  },
);

/// `diary.ensure`：与进模块 bootstrap 完全同源的 composer.ensureDay。
final CommandSpec diaryEnsure = CommandSpec(
  namespace: 'diary',
  verb: 'ensure',
  summary: '确保某日草稿存在（无则自动成稿），幂等',
  kind: CommandKind.write,
  level: ControlLevel.user,
  params: [
    ParamSpec('date', type: ArgType.date, summary: 'YYYY-MM-DD，缺省=日记日今天'),
    ParamSpec(
      'waitSnapshot',
      type: ArgType.boolean,
      defaults: true,
      summary: '是否等待 data 快照拉取（成稿始终注入快照）',
    ),
  ],
  handler: (ctx) async {
    final repo = ctx.requireService<DiaryRepository>('日记仓储');
    final composer = ctx.requireService<DiaryComposer>('日记成稿器');
    final clock = ctx.requireService<DiaryClock>('日记日时钟');
    final day = _dayOnly(ctx.optionalArg<DateTime>('date') ?? clock.today());

    // archived 命中时 composer 抛 StateError（总线映射 CONFLICT）；
    // 未来日抛 ArgumentError（总线映射 USAGE）——均为同源行为。
    final existedBefore = await repo.dayExists(day);
    final doc = await composer.ensureDay(day, repo);
    final state = (await repo.stateOfDay(day))!;
    return {
      // archived 场景会先抛错；走到这里时 existedBefore 即「原本有草稿」。
      'created': !existedBefore,
      'document': diaryDocumentJson(doc, state),
    };
  },
);

/// `diary.prune`：跨天空日记清理，支持 dry-run 即时核查。
final CommandSpec diaryPrune = CommandSpec(
  namespace: 'diary',
  verb: 'prune',
  summary: '清理截止线前的空日记（meta 与正文同生共死）',
  kind: CommandKind.lifecycle,
  level: ControlLevel.admin,
  destructive: true,
  params: [
    ParamSpec(
      'before',
      type: ArgType.date,
      summary: '截止日期 YYYY-MM-DD，缺省=日记日今天',
    ),
    ParamSpec(
      'dryRun',
      type: ArgType.boolean,
      defaults: true,
      summary: '只报告不删除（真机核查用）',
    ),
  ],
  handler: (ctx) async {
    final repo = ctx.requireService<DiaryRepository>('日记仓储');
    final composer = ctx.requireService<DiaryComposer>('日记成稿器');
    final clock = ctx.requireService<DiaryClock>('日记日时钟');
    final cutoff = _dayOnly(
      ctx.optionalArg<DateTime>('before') ?? clock.today(),
    );
    final dryRun = ctx.arg<bool>('dryRun');

    final result = await repo.pruneEmptyBefore(
      cutoff,
      composer.isUserEmpty,
      dryRun: dryRun,
    );
    return {
      'cutoff': isoDate(cutoff),
      'dryRun': dryRun,
      'deleted': result.deleted.map(isoDate).toList(),
      'kept': [
        for (final (date, reason) in result.kept)
          {'date': isoDate(date), 'reason': reason},
      ],
    };
  },
);

/// `diary.reset`（debug-only）：清空日记域并重灌种子，替代伤全 App 的
/// `pm clear`。
final CommandSpec diaryReset = CommandSpec(
  namespace: 'diary',
  verb: 'reset',
  summary: '【仅 debug】清空日记仓储，可选重灌上月+昨天种子',
  kind: CommandKind.lifecycle,
  level: ControlLevel.admin,
  destructive: true,
  debugOnly: true,
  params: [
    ParamSpec(
      'keepSeeds',
      type: ArgType.boolean,
      defaults: false,
      summary: '清空后重灌「上月 28 + 昨天」种子',
    ),
  ],
  handler: (ctx) async {
    final repo = ctx.requireService<DiaryRepository>('日记仓储');
    final clock = ctx.requireService<DiaryClock>('日记日时钟');
    final wiped = await repo.wipeAll();

    var reseeded = 0;
    if (ctx.arg<bool>('keepSeeds')) {
      // 与 debug 包冷启动灌种同源（同一 clock 今天，今天不种）。
      final seeds = DiarySeedData.build(
        idGenerator: repo.idGenerator,
        today: clock.today(),
      );
      for (final doc in seeds) {
        await repo.upsertDraft(doc);
        reseeded++;
      }
    }
    return {
      'removedDocs': wiped.removedDocs,
      'removedFiles': wiped.removedFiles,
      'reseeded': reseeded,
    };
  },
);

/// `diary.seed`（debug-only，P4）：批量灌入**成稿形状**的草稿，专补
/// 跨天清理（`diary.prune`）的 R3 实证缺口——造出「有字稿保留、空稿
/// 被删」的可复现现场。
///
/// - 空稿与 composer 空稿判定（[DiaryComposer.isUserEmpty]）**同一构造**
///   （[DiaryComposer.buildEmptyDraft] 即模板实例化），保证 prune 认得；
///   命令层不得自创「空」定义；
/// - 非空稿走 [DiarySeedData.buildNonEmpty] 同源段落构造；
/// - 已存在日期跳过不覆盖（三态一律跳过；干净重灌用 diary.reset
///   --keep-seeds）；全程走 [DiaryRepository.upsertDraft]，不直连 sqflite。
///
/// 破坏性 3 级（与设计 §5.1 prune/reset/seed 集合一致）需 --confirm；
/// release manifest 物理不存在。
final CommandSpec diarySeed = CommandSpec(
  namespace: 'diary',
  verb: 'seed',
  summary: '【仅 debug】批量灌入成稿形状草稿（可穿插空稿验证 prune）',
  kind: CommandKind.lifecycle,
  level: ControlLevel.admin,
  destructive: true,
  debugOnly: true,
  idempotent: false,
  params: [
    ParamSpec(
      'days',
      type: ArgType.integer,
      defaults: 7,
      summary: '自 --end 向前回推的天数（含 end 当天），1..60',
    ),
    ParamSpec(
      'end',
      type: ArgType.date,
      summary: '截止日期 YYYY-MM-DD，缺省=日记日昨天（今天不自动种）',
    ),
    ParamSpec(
      'emptyEvery',
      type: ArgType.integer,
      defaults: 0,
      summary: '每 K 天造一篇空稿，0..days（0=全部非空）',
    ),
  ],
  handler: (ctx) async {
    final repo = ctx.requireService<DiaryRepository>('日记仓储');
    final composer = ctx.requireService<DiaryComposer>('日记成稿器');
    final clock = ctx.requireService<DiaryClock>('日记日时钟');

    final days = ctx.arg<int>('days');
    if (days < 1 || days > 60) {
      throw const ControlException(ControlErrorCode.usage, '--days 允许范围 1..60');
    }
    // 缺省＝昨天：今天不自动种（M4 起今天由进模块 composer.ensureDay
    // 接管）；显式给 --end 可种当天，但仍不许落到未来日记日。
    final today = clock.today();
    final end = _dayOnly(
      ctx.optionalArg<DateTime>('end') ??
          today.subtract(const Duration(days: 1)),
    );
    if (end.isAfter(today)) {
      throw const ControlException(
        ControlErrorCode.usage,
        '--end 不得晚于日记日今天（模块不提供未来日期入口）',
      );
    }
    final emptyEvery = ctx.arg<int>('emptyEvery');
    if (emptyEvery < 0 || emptyEvery > days) {
      throw const ControlException(
        ControlErrorCode.usage,
        '--empty-every 允许范围 0..days',
      );
    }

    final created = <DateTime>[];
    final empty = <DateTime>[];
    final skipped = <DateTime>[];
    // 自 end 向前回推 days 天（含 end 当天），升序落盘。
    for (var i = days - 1; i >= 0; i--) {
      final day = DateTime(end.year, end.month, end.day - i);
      if (await repo.dayExists(day)) {
        skipped.add(day);
        continue;
      }
      // 「距 end 天数」定义空稿节奏：--end 当天为 0，每 K 天（含当天）
      // 一篇空稿。用日期差分而非循环下标，保证与回推顺序无关。
      final offsetFromEnd = end.difference(day).inDays;
      final isBlank = emptyEvery > 0 && offsetFromEnd % emptyEvery == 0;
      final doc = isBlank
          ? composer.buildEmptyDraft(day)
          : DiarySeedData.buildNonEmpty(
              idGenerator: repo.idGenerator,
              day: day,
              variant: offsetFromEnd,
            );
      await repo.upsertDraft(doc);
      (isBlank ? empty : created).add(day);
    }
    return {
      'created': created.map(isoDate).toList(),
      'empty': empty.map(isoDate).toList(),
      'skipped': skipped.map(isoDate).toList(),
    };
  },
);

/// `diary.export`：跳过分享 UI，直接把 draft 打成 .sy.zip 落沙盒目录。
///
/// 慢命令（60s 上限）；不迁状态（markExported 是人工确认分享成功后的
/// UI 流程，不在命令范围），故导出物可重复生成。
///
/// 定级（2026-10-13 修订，设计 §5.1）：数据导出是「需要工具辅助的
/// 正常操作」而非攻击面，降为 user 级——本地通道直放、不要
/// --confirm；MCP 通道上限 1 仍物理挡住自动化导出。非破坏性。
final CommandSpec diaryExport = CommandSpec(
  namespace: 'diary',
  verb: 'export',
  summary: '打包 draft 日记为思源 .sy.zip（不分享、不迁状态）',
  kind: CommandKind.write,
  level: ControlLevel.user,
  slow: true,
  params: [
    ParamSpec('notebook', type: ArgType.string, summary: '思源笔记本名，缺省固定「日记」'),
    ParamSpec('year', type: ArgType.integer, summary: '只打某年，缺省全部年份'),
  ],
  handler: (ctx) async {
    final exporter = ctx.requireService<DiaryExportService>('日记导出服务');
    final paths = ctx.requireService<ControlPaths>('沙盒路径');
    final diaryRoot = paths.diaryRoot;
    if (diaryRoot == null) {
      throw const ControlException(
        ControlErrorCode.conflict,
        '日记存储路径尚未就绪，请先进入笔记页完成初始化',
      );
    }

    try {
      final build = await exporter.buildDraftZip(
        notebookName: ctx.optionalArg<String>('notebook'),
        year: ctx.optionalArg<int>('year'),
        outputDirectory: paths.diaryExports,
      );
      final result = {
        'path': build.path,
        'entries': build.entries,
        'sizeBytes': build.sizeBytes,
        'notebook': build.notebook,
      };
      // P4：导出成功（含后台作业路径）发 user 级事件；失败不发——
      // 失败结论在 command.finished（error）里。事件由 handler 经
      // 上下文缝发射，总线在 handler 返回后才发 command.finished，
      // 同一导出自此有先后两事件可关联。
      ctx.emitEvent(
        type: ControlEventType.diaryExportCompleted,
        level: ControlLevel.user,
        data: result,
      );
      return result;
    } on DiaryExportEmptyException {
      throw const ControlException(
        ControlErrorCode.exportEmpty,
        '没有可导出的 draft 日记',
      );
    }
  },
);

// ---- 域内小工具 -------------------------------------------------------

DateTime _dayOnly(DateTime d) => DateTime(d.year, d.month, d.day);

int _dayKey(DateTime d) => d.year * 10000 + d.month * 100 + d.day;

/// 从月列表里取某一天的摘要（archived 单篇返回 title/preview 用）。
Future<DiaryDaySummary?> _summaryOf(DiaryRepository repo, DateTime day) async {
  final rows = await repo.daysOfMonth(day.year, day.month);
  for (final row in rows) {
    if (row.date.year == day.year &&
        row.date.month == day.month &&
        row.date.day == day.day) {
      return row;
    }
  }
  return null;
}
