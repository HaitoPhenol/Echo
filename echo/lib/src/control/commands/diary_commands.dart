import 'dart:convert';

import '../../diary/data/diary_clock.dart';
import '../../diary/data/diary_repository.dart';
import '../../diary/data/diary_seed_data.dart';
import '../../diary/diary_navigator.dart';
import '../../diary/export/diary_export_service.dart';
import '../../diary/sy/diary_model.dart';
import '../../diary/sy/sy_id.dart';
import '../../diary/template/diary_composer.dart';
import '../../navigation/nav_destination_specs.dart';
import '../../navigation/nav_physics.dart';
import '../control_registry.dart';
import '../events/event_types.dart';
import '../protocol/command_spec.dart';
import '../protocol/control_error.dart';
import 'control_json.dart';

/// `diary` 命名空间：列表/读取/成稿/导航/跨天清理/清空重置/灌数/打包导出
/// 与内容写入（手册 §5）。`diary.seed` 为 P4 引入的 debug-only 灌数命令；
/// `diary.goto` 为 P5 引入的笔记页内层导航命令。
///
/// 全部走 UI 同源的仓储/composer/导出服务实例（DiaryPage bootstrap
/// 后注册），命令层不直连 sqflite / 文件序列化器。
List<CommandSpec> buildDiaryCommands() => [
  diaryList,
  diaryGet,
  diaryEnsure,
  diaryGoto,
  diaryPrune,
  diaryReset,
  diarySeed,
  diaryExport,
  diaryStateSet,
  diaryBlockSet,
  diaryDocumentSet,
  diaryCustomSet,
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
///
/// 2026-10-18 日模板重设后成稿只写文档根 `custom-*`、不再有独立的
/// 「data 快照拉取」步骤，原 `--wait-snapshot` 占位参数随之删除。
final CommandSpec diaryEnsure = CommandSpec(
  namespace: 'diary',
  verb: 'ensure',
  summary: '确保某日草稿存在（无则自动成稿），幂等',
  kind: CommandKind.write,
  level: ControlLevel.user,
  params: [
    ParamSpec('date', type: ArgType.date, summary: 'YYYY-MM-DD，缺省=日记日今天'),
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

/// `diary.goto`：驱动笔记页**内层**路由栈（年→月→日→编辑页）导航。
///
/// 同路原则：先把顶层导航 snap 到 notes 页（[NavPhysicsController] 可选取
/// 用，命令可在导航控制器尚未注册时仅驱动内层栈），再经
/// [DiaryNavigatorController] 调与用户手动点击**完全相同**的栈操作，不另
/// 造控制专用跳转。
///
/// 参数语义（至少给 `--date` 或 `--level` 之一）：
/// - `--date`：直接跳该日编辑页（等价 `--level editor`，与 `--level` 互斥）；
/// - `--level year`：回年列表（根）；
/// - `--level month`：需 `--year`；
/// - `--level day`：需 `--year --month`；
/// - `--level editor`：需 `--year --month --day`。
///
/// 日期约束：与模块一致，目标日历日期/年份不得晚于日记日时钟的「今天」
/// （M4 起不提供未来日期入口），越界抛 USAGE。
final CommandSpec diaryGoto = CommandSpec(
  namespace: 'diary',
  verb: 'goto',
  summary: '跳转笔记页各层级（年/月/日/编辑页，可给日期直达编辑页）',
  kind: CommandKind.write,
  level: ControlLevel.user,
  params: [
    ParamSpec(
      'date',
      type: ArgType.date,
      summary: 'YYYY-MM-DD，给出即直达该日编辑页（与 --level 互斥）',
    ),
    ParamSpec(
      'level',
      type: ArgType.string,
      summary: 'year/month/day/editor，缺省且无 --date 时=year',
    ),
    ParamSpec('year', type: ArgType.integer, summary: '目标年份（月/日/编辑页需）'),
    ParamSpec('month', type: ArgType.integer, summary: '目标月份 1-12（日/编辑页需）'),
    ParamSpec('day', type: ArgType.integer, summary: '目标日 1-31（编辑页需）'),
  ],
  handler: (ctx) async {
    final clock = ctx.requireService<DiaryClock>('日记日时钟');
    final navigator = ctx.requireService<DiaryNavigatorController>(
      '笔记页导航控制器（请先进入笔记页完成装配）',
    );
    final today = clock.today();

    final rawDate = ctx.optionalArg<DateTime>('date');
    final rawLevel = ctx.optionalArg<String>('level');

    // 先把顶层导航带到 notes（未注册导航控制器时跳过，仅驱动内层栈）。
    final nav = ctx.service<NavPhysicsController>();
    if (nav != null) {
      final notesIndex = resolveNavPageIndex('notes', nav.pageCount);
      if (notesIndex != null && notesIndex != nav.activePage) {
        nav.snapTo(notesIndex);
      }
    }

    if (rawDate != null) {
      if (rawLevel != null) {
        throw const ControlException(
          ControlErrorCode.usage,
          '--date 与 --level 互斥：给 --date 即等价 --level editor',
        );
      }
      final day = _dayOnly(rawDate);
      if (day.isAfter(today)) {
        throw const ControlException(
          ControlErrorCode.usage,
          '目标日期不得晚于今天（模块不提供未来日期入口）',
        );
      }
      await navigator.showEditor(day);
      return {'page': 'notes', 'level': 'editor', 'date': isoDate(day)};
    }

    final level = (rawLevel ?? 'year').toLowerCase();
    final year = ctx.optionalArg<int>('year');
    final month = ctx.optionalArg<int>('month');
    final day = ctx.optionalArg<int>('day');

    switch (level) {
      case 'year':
        await navigator.showYearList();
        return {'page': 'notes', 'level': 'year'};
      case 'month':
        final y = _requireInt(year, '--year', 'level=month');
        _rejectFutureYear(y, today);
        await navigator.showMonthList(y);
        return {'page': 'notes', 'level': 'month', 'year': y};
      case 'day':
        final y = _requireInt(year, '--year', 'level=day');
        final m = _requireMonth(month, 'level=day');
        _rejectFutureYear(y, today);
        await navigator.showDayList(y, m);
        return {'page': 'notes', 'level': 'day', 'year': y, 'month': m};
      case 'editor':
        final y = _requireInt(year, '--year', 'level=editor');
        final m = _requireMonth(month, 'level=editor');
        final d = _requireInt(day, '--day', 'level=editor');
        final target = _composeDay(y, m, d);
        if (target.isAfter(today)) {
          throw const ControlException(
            ControlErrorCode.usage,
            '目标日期不得晚于今天（模块不提供未来日期入口）',
          );
        }
        await navigator.showEditor(target);
        return {
          'page': 'notes',
          'level': 'editor',
          'year': y,
          'month': m,
          'day': d,
          'date': isoDate(target),
        };
      default:
        throw ControlException(
          ControlErrorCode.usage,
          '未知 --level：$level（可选 year/month/day/editor）',
        );
    }
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
    ParamSpec(
      'month',
      type: ArgType.integer,
      summary: '与 --year 同给出时收紧到某月（1-12），实现按月导出',
    ),
    ParamSpec(
      'date',
      type: ArgType.date,
      summary: 'YYYY-MM-DD，只打该日（与 --year/--month 互斥），实现按日导出',
    ),
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

    final date = ctx.optionalArg<DateTime>('date');
    final year = ctx.optionalArg<int>('year');
    final month = ctx.optionalArg<int>('month');
    if (date != null && (year != null || month != null)) {
      throw const ControlException(
        ControlErrorCode.usage,
        '--date 与 --year/--month 互斥：按日导出请只给 --date',
      );
    }

    try {
      final build = await exporter.buildDraftZip(
        notebookName: ctx.optionalArg<String>('notebook'),
        year: year,
        month: month,
        date: date,
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

/// `diary.state.set`：在 draft↔exported 之间迁移某日日记状态。
///
/// 语义（仅这两态，archived 是终态、归档流程走 UI，不在此暴露）：
/// - `--state exported`：draft→exported（标记已导出、正文转只读）；
/// - `--state draft`：exported→draft（**恢复导出状态**、正文解锁）。
///
/// 非 draft 的 exported/archived 在目标态迁移非法时由仓储抛
/// [StateError]（总线映射 CONFLICT）；目标不存在抛 NOT_FOUND。
/// 供 MCP 侧「恢复导出状态」与「精确标记导出」复用。
final CommandSpec diaryStateSet = CommandSpec(
  namespace: 'diary',
  verb: 'state.set',
  summary: '迁移某日日记状态（draft↔exported，draft 即恢复导出状态）',
  kind: CommandKind.write,
  level: ControlLevel.user,
  idempotent: false,
  params: [
    ParamSpec(
      'date',
      type: ArgType.date,
      required: true,
      summary: 'YYYY-MM-DD',
    ),
    ParamSpec(
      'state',
      type: ArgType.string,
      required: true,
      summary: '目标状态 draft/exported',
    ),
  ],
  handler: (ctx) async {
    final repo = ctx.requireService<DiaryRepository>('日记仓储');
    final day = _dayOnly(ctx.arg<DateTime>('date'));
    final target = ctx.arg<String>('state').toLowerCase();

    final from = await repo.stateOfDay(day);
    if (from == null) {
      throw ControlException(
        ControlErrorCode.notFound,
        '没有这篇日记：${isoDate(day)}',
      );
    }

    switch (target) {
      case 'exported':
        await repo.markExported([day], exportedAt: DateTime.now());
      case 'draft':
        await repo.restoreDraft(day);
      default:
        throw ControlException(
          ControlErrorCode.usage,
          '未知 --state：$target（可选 draft/exported）',
        );
    }

    final to = (await repo.stateOfDay(day))!;
    final doc = await repo.findDay(day);
    return {
      'date': isoDate(day),
      'from': from.name,
      'to': to.name,
      'document': doc == null ? null : diaryDocumentJson(doc, to),
    };
  },
);

/// `diary.block.set`：按块 JSON 补丁修改某日草稿的块内容。
///
/// `--json` 为**块对象**或**块对象数组**；每项字段（均可选）：
/// `id` / `kind`(paragraph|heading) / `level`(1..6) / `text` /
/// `background`(1..13 或 null) / `custom`(对象) / `index`(新块插入位置)。
///
/// - 带 `id`：按 id 就地补丁（块不存在抛 NOT_FOUND）；
/// - 无 `id`：新建块，追加到末尾；给 `index` 则插入该位置。
///
/// 仅 draft 可写（exported/archived 抛 CONFLICT）；返回完整文档 JSON。
/// `--json` 标注 `auditRedact`：正文内容不入审计流水。
final CommandSpec diaryBlockSet = CommandSpec(
  namespace: 'diary',
  verb: 'block.set',
  summary: '按 JSON 补丁修改草稿块（带 id 改、无 id 追加/插入）',
  kind: CommandKind.write,
  level: ControlLevel.user,
  idempotent: false,
  params: [
    ParamSpec(
      'date',
      type: ArgType.date,
      required: true,
      summary: 'YYYY-MM-DD',
    ),
    ParamSpec(
      'json',
      type: ArgType.string,
      required: true,
      auditRedact: true,
      summary: '块对象或块对象数组（见手册 §5）',
    ),
  ],
  handler: (ctx) async {
    final repo = ctx.requireService<DiaryRepository>('日记仓储');
    final day = _dayOnly(ctx.arg<DateTime>('date'));
    final doc = await _requireEditableDraft(repo, day);

    for (final patch in _jsonItems(ctx.arg<String>('json'), '--json')) {
      final rawId = patch['id'];
      if (rawId != null) {
        if (rawId is! String) {
          throw const ControlException(ControlErrorCode.usage, '块 id 必须是字符串');
        }
        final index = doc.blocks.indexWhere((b) => b.id == rawId);
        if (index < 0) {
          throw ControlException(
            ControlErrorCode.notFound,
            '块不存在：$rawId',
          );
        }
        _patchBlock(doc.blocks[index], patch);
      } else {
        final block = _newBlockFromJson(patch, repo.idGenerator.next());
        final rawIndex = patch['index'];
        if (rawIndex == null) {
          doc.blocks.add(block);
        } else {
          if (rawIndex is! num) {
            throw const ControlException(ControlErrorCode.usage, '块 index 必须是数字');
          }
          doc.blocks.insert(
            rawIndex.toInt().clamp(0, doc.blocks.length),
            block,
          );
        }
      }
    }

    doc.updatedAt = DateTime.now();
    await repo.upsertDraft(doc);
    return diaryDocumentJson(doc, DiaryDocState.draft);
  },
);

/// `diary.document.set`：全文替换某日草稿（title / blocks / custom）。
///
/// `--json` 为对象，字段（均可选）：`title`(字符串) / `blocks`(块对象数组，
/// **整体替换**现有块) / `custom`(对象，按 [diary.custom.set] 规则合并)。
/// `blocks` 每项字段同 [diary.block.set]，`id` 缺省时自动生成思源 22 位
/// 块 ID（缺省段落类型）。
///
/// 仅 draft 可写；返回完整文档 JSON。`--json` 标注 `auditRedact`。
final CommandSpec diaryDocumentSet = CommandSpec(
  namespace: 'diary',
  verb: 'document.set',
  summary: '全文替换草稿内容（title/blocks/custom）',
  kind: CommandKind.write,
  level: ControlLevel.user,
  idempotent: false,
  params: [
    ParamSpec(
      'date',
      type: ArgType.date,
      required: true,
      summary: 'YYYY-MM-DD',
    ),
    ParamSpec(
      'json',
      type: ArgType.string,
      required: true,
      auditRedact: true,
      summary: '对象：{title?, blocks?, custom?}',
    ),
  ],
  handler: (ctx) async {
    final repo = ctx.requireService<DiaryRepository>('日记仓储');
    final day = _dayOnly(ctx.arg<DateTime>('date'));
    final doc = await _requireEditableDraft(repo, day);
    final json = _jsonObject(ctx.arg<String>('json'), '--json');

    if (json.containsKey('title')) {
      final title = json['title'];
      if (title is! String) {
        throw const ControlException(ControlErrorCode.usage, 'title 必须是字符串');
      }
      doc.title = title;
    }

    if (json.containsKey('blocks')) {
      final rawBlocks = json['blocks'];
      if (rawBlocks is! List) {
        throw const ControlException(ControlErrorCode.usage, 'blocks 必须是数组');
      }
      final rebuilt = <DiaryBlock>[];
      for (final item in rawBlocks) {
        if (item is! Map) {
          throw const ControlException(
            ControlErrorCode.usage,
            'blocks 每项必须是 JSON 对象',
          );
        }
        final map = item.cast<String, Object?>();
        final rawId = map['id'];
        if (rawId != null && rawId is! String) {
          throw const ControlException(ControlErrorCode.usage, '块 id 必须是字符串');
        }
        final id = (rawId as String?) ?? repo.idGenerator.next();
        if (!SyIdGenerator.isValid(id)) {
          throw ControlException(
            ControlErrorCode.usage,
            '块 id 不符合思源 22 位规范：$id',
          );
        }
        rebuilt.add(_newBlockFromJson(map, id));
      }
      doc.blocks
        ..clear()
        ..addAll(rebuilt);
    }

    if (json.containsKey('custom')) {
      final custom = json['custom'];
      if (custom is! Map) {
        throw const ControlException(ControlErrorCode.usage, 'custom 必须是对象');
      }
      _mergeCustom(doc.custom, custom.cast<String, Object?>(), scope: '文档');
    }

    doc.updatedAt = DateTime.now();
    await repo.upsertDraft(doc);
    return diaryDocumentJson(doc, DiaryDocState.draft);
  },
);

/// `diary.custom.set`：合并某日草稿的文档级 `custom-*` 自定义属性。
///
/// `--json` 为对象：键须以 `custom-` 开头；值为 null 表示删除该键，
/// 字符串/数字/布尔统一转字符串落库（思源自定义属性皆文本）。
/// **合并**语义（非整体替换），只动补丁中出现的键。
///
/// 仅 draft 可写；返回完整文档 JSON。`--json` 标注 `auditRedact`。
final CommandSpec diaryCustomSet = CommandSpec(
  namespace: 'diary',
  verb: 'custom.set',
  summary: '合并草稿文档级 custom-* 属性（null 删键）',
  kind: CommandKind.write,
  level: ControlLevel.user,
  params: [
    ParamSpec(
      'date',
      type: ArgType.date,
      required: true,
      summary: 'YYYY-MM-DD',
    ),
    ParamSpec(
      'json',
      type: ArgType.string,
      required: true,
      auditRedact: true,
      summary: '对象：{"custom-key": value, ...}，value=null 删键',
    ),
  ],
  handler: (ctx) async {
    final repo = ctx.requireService<DiaryRepository>('日记仓储');
    final day = _dayOnly(ctx.arg<DateTime>('date'));
    final doc = await _requireEditableDraft(repo, day);
    final json = _jsonObject(ctx.arg<String>('json'), '--json');
    if (json.isNotEmpty) {
      _mergeCustom(doc.custom, json, scope: '文档');
      doc.updatedAt = DateTime.now();
      await repo.upsertDraft(doc);
    }
    return diaryDocumentJson(doc, DiaryDocState.draft);
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

/// 取某日**可编辑草稿**：不存在 NOT_FOUND；exported/archived 只读抛
/// CONFLICT（导出后正文锁定、归档后正文已物理清除）。
Future<DiaryDocument> _requireEditableDraft(
  DiaryRepository repo,
  DateTime day,
) async {
  final state = await repo.stateOfDay(day);
  if (state == null) {
    throw ControlException(
      ControlErrorCode.notFound,
      '没有这篇日记：${isoDate(day)}',
    );
  }
  if (state != DiaryDocState.draft) {
    throw ControlException(
      ControlErrorCode.conflict,
      '${state.name} 态日记只读，不能修改：${isoDate(day)}',
    );
  }
  final doc = await repo.findDay(day);
  if (doc == null) {
    throw ControlException(
      ControlErrorCode.notFound,
      '日记正文缺失：${isoDate(day)}',
    );
  }
  return doc;
}

/// 解析 JSON 文本；非法 JSON 抛 USAGE（附解析器错误信息）。
Object? _decodeJson(String raw, String what) {
  try {
    return jsonDecode(raw);
  } on FormatException catch (e) {
    throw ControlException(
      ControlErrorCode.usage,
      '$what 不是合法 JSON：${e.message}',
    );
  }
}

/// 解析 JSON 文本为对象；非对象抛 USAGE。
Map<String, Object?> _jsonObject(String raw, String what) {
  final decoded = _decodeJson(raw, what);
  if (decoded is! Map) {
    throw ControlException(ControlErrorCode.usage, '$what 必须是 JSON 对象');
  }
  return decoded.cast<String, Object?>();
}

/// 解析 JSON 文本为「对象或对象数组」并归一为对象列表；空数组抛 USAGE。
List<Map<String, Object?>> _jsonItems(String raw, String what) {
  final decoded = _decodeJson(raw, what);
  final list = decoded is List ? decoded : [decoded];
  final out = <Map<String, Object?>>[];
  for (final item in list) {
    if (item is! Map) {
      throw ControlException(ControlErrorCode.usage, '$what 每项必须是 JSON 对象');
    }
    out.add(item.cast<String, Object?>());
  }
  if (out.isEmpty) {
    throw ControlException(ControlErrorCode.usage, '$what 不能是空数组');
  }
  return out;
}

DiaryBlockKind _parseBlockKind(Object? raw) => switch (raw) {
  'paragraph' => DiaryBlockKind.paragraph,
  'heading' => DiaryBlockKind.heading,
  _ => throw ControlException(
    ControlErrorCode.usage,
    '未知块类型：$raw（可选 paragraph/heading）',
  ),
};

/// 校验并归一底色：null 合法（无底色），数字须落在思源 1..13 色号内。
int? _parseBackground(Object? raw) {
  if (raw == null) return null;
  if (raw is! num) {
    throw const ControlException(
      ControlErrorCode.usage,
      '块 background 必须是数字或 null',
    );
  }
  final value = raw.toInt();
  if (value < 1 || value > 13) {
    throw const ControlException(
      ControlErrorCode.usage,
      '块 background 取值须在思源 1..13 色号内',
    );
  }
  return value;
}

/// 合并自定义属性补丁：键须以 `custom-` 开头；值为 null 表示删除该键，
/// 字符串/数字/布尔统一以字符串落库（思源自定义属性皆文本）。
void _mergeCustom(
  Map<String, String> target,
  Map<String, Object?> patch, {
  required String scope,
}) {
  for (final entry in patch.entries) {
    final key = entry.key;
    if (!key.startsWith('custom-') || key.length <= 'custom-'.length) {
      throw ControlException(
        ControlErrorCode.usage,
        '$scope自定义属性键必须以 custom- 开头且非空：$key',
      );
    }
    final value = entry.value;
    if (value == null) {
      target.remove(key);
    } else if (value is String || value is num || value is bool) {
      target[key] = value.toString();
    } else {
      throw ControlException(
        ControlErrorCode.usage,
        '$scope自定义属性值须为字符串/数字/布尔或 null：$key',
      );
    }
  }
}

/// 把 JSON 补丁块对象构造为新块（无原块可比，字段一律取补丁值或默认）。
DiaryBlock _newBlockFromJson(Map<String, Object?> json, String id) {
  final kind = json.containsKey('kind')
      ? _parseBlockKind(json['kind'])
      : DiaryBlockKind.paragraph;
  final textRaw = json['text'];
  if (textRaw != null && textRaw is! String) {
    throw const ControlException(ControlErrorCode.usage, '块 text 必须是字符串');
  }
  final levelRaw = json['level'];
  if (levelRaw != null && levelRaw is! num) {
    throw const ControlException(ControlErrorCode.usage, '块 level 必须是数字或 null');
  }
  final level = (levelRaw as num?)?.toInt();
  if (kind == DiaryBlockKind.heading && (level == null || level < 1 || level > 6)) {
    throw const ControlException(
      ControlErrorCode.usage,
      '标题块 level 必须为 1..6',
    );
  }

  final custom = <String, String>{};
  final customRaw = json['custom'];
  if (customRaw != null) {
    if (customRaw is! Map) {
      throw const ControlException(ControlErrorCode.usage, '块 custom 必须是对象');
    }
    _mergeCustom(custom, customRaw.cast<String, Object?>(), scope: '块');
  }

  return DiaryBlock(
    id: id,
    kind: kind,
    level: kind == DiaryBlockKind.heading ? level : null,
    text: (textRaw as String?) ?? '',
    background: _parseBackground(json['background']),
    custom: custom,
  );
}

/// 把 JSON 补丁**就地**应用到既有块：只改补丁中出现的字段。
void _patchBlock(DiaryBlock block, Map<String, Object?> json) {
  var touched = false;
  if (json.containsKey('kind')) {
    block.kind = _parseBlockKind(json['kind']);
    touched = true;
  }
  if (json.containsKey('text')) {
    final text = json['text'];
    if (text is! String) {
      throw const ControlException(ControlErrorCode.usage, '块 text 必须是字符串');
    }
    block.text = text;
    touched = true;
  }
  if (json.containsKey('background')) {
    block.background = _parseBackground(json['background']);
    touched = true;
  }
  if (json.containsKey('level')) {
    final level = json['level'];
    if (level != null && level is! num) {
      throw const ControlException(ControlErrorCode.usage, '块 level 必须是数字或 null');
    }
    block.level = (level as num?)?.toInt();
    touched = true;
  }
  if (json.containsKey('custom')) {
    final custom = json['custom'];
    if (custom is! Map) {
      throw const ControlException(ControlErrorCode.usage, '块 custom 必须是对象');
    }
    _mergeCustom(block.custom, custom.cast<String, Object?>(), scope: '块');
    touched = true;
  }

  // kind/level 一致性收口：标题必须 1..6 级，段落一律清级别。
  if (block.kind == DiaryBlockKind.heading) {
    final level = block.level;
    if (level == null || level < 1 || level > 6) {
      throw const ControlException(
        ControlErrorCode.usage,
        '标题块 level 必须为 1..6',
      );
    }
  } else {
    block.level = null;
  }
  if (touched) block.updatedAt = DateTime.now();
}

int _requireInt(int? value, String flag, String need) {
  if (value == null) {
    throw ControlException(ControlErrorCode.usage, '缺少 $flag（$need 需要）');
  }
  return value;
}

int _requireMonth(int? value, String need) {
  final month = _requireInt(value, '--month', need);
  if (month < 1 || month > 12) {
    throw const ControlException(ControlErrorCode.usage, '--month 必须在 1..12');
  }
  return month;
}

void _rejectFutureYear(int year, DateTime today) {
  if (year > today.year) {
    throw const ControlException(
      ControlErrorCode.usage,
      '目标年份不得晚于今年（模块不提供未来日期入口）',
    );
  }
}

/// 由年月日合成目标日；非法组合（如 02-31）显式拒绝而非交给
/// [DateTime] 归一化悄悄改期。
DateTime _composeDay(int year, int month, int day) {
  if (month < 1 || month > 12) {
    throw const ControlException(ControlErrorCode.usage, '--month 必须在 1..12');
  }
  if (day < 1 || day > 31) {
    throw const ControlException(ControlErrorCode.usage, '--day 必须在 1..31');
  }
  final composed = DateTime(year, month, day);
  if (composed.year != year ||
      composed.month != month ||
      composed.day != day) {
    throw ControlException(
      ControlErrorCode.usage,
      '非法日期：$year-${month.toString().padLeft(2, '0')}-'
      '${day.toString().padLeft(2, '0')}',
    );
  }
  return composed;
}
