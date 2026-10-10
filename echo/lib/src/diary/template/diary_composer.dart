import '../data/diary_data_provider.dart';
import '../data/diary_repository.dart';
import '../sy/diary_model.dart';
import '../sy/sy_id.dart';
import 'daily_default_template.dart';
import 'diary_template_json.dart';

/// data 快照重拉结果：快照文本 + 文档根 custom 增删。
///
/// patch 中值为 null 表示移除该键（本次源不可用），非 null 为覆盖。
class DataSnapshotResult {
  const DataSnapshotResult({required this.text, required this.customPatch});

  final String text;
  final Map<String, String?> customPatch;
}

/// 日记成稿编排器（tech-plan §5.1/§5.2）。
///
/// 职责：
/// - [ensureDay]：命中已有草稿直接返回；否则模板实例化 + 拉 provider
///   填充 data 快照与 custom-* 并立即落盘。按日记日缓存 in-flight
///   Future，模块预热与快速点进并发时也只成稿一次。
/// - [fetchSnapshot]：↻ 刷新的取数+渲染纯逻辑，编辑页拿到结果后
///   自行经控制器替换（压撤销栈）。
/// - [isUserEmpty]：跨天清理的「什么都没写」判定。
class DiaryComposer {
  DiaryComposer({
    required this.template,
    required this.provider,
    required SyIdGenerator idGenerator,
    DateTime Function()? now,
  })  : _ids = idGenerator,
        _now = now ?? DateTime.now;

  final DailyDefaultTemplate template;
  final DiaryDataProvider provider;
  final SyIdGenerator _ids;
  final DateTime Function() _now;

  /// key = yyyymmdd；同一日记日的成稿 Future 去重。
  final Map<int, Future<DiaryDocument>> _inFlight = {};

  static int _dayKey(DateTime d) => d.year * 10000 + d.month * 100 + d.day;

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

    final document = template.instantiate(day, _ids);
    final snapshot = await fetchSnapshot(day);
    final dataBlock = document.blocks
        .firstWhere((b) => SyIdGenerator.isDataBlockId(b.id));
    dataBlock.text = snapshot.text;
    snapshot.customPatch.forEach((key, value) {
      if (value != null) document.custom[key] = value;
    });
    document.updatedAt = _now();
    await repository.upsertDraft(document);
    return document;
  }

  // ================================================================
  //  取数与快照渲染
  // ================================================================

  /// 拉取三个数据源（互不连坐）并渲染快照行；供成稿与 ↻ 复用。
  Future<DataSnapshotResult> fetchSnapshot(DateTime diaryDate) async {
    final day = DateTime(
      diaryDate.year,
      diaryDate.month,
      diaryDate.day,
    );

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

    final fragments = <String>[];
    final patch = <String, String?>{};

    if (env != null) {
      final temp = _formatNum(env!.tempC);
      fragments.add('🌡️ $temp°C　💧 ${env!.humidityPct}%');
      patch['custom-iot-temp'] = temp;
      patch['custom-iot-humidity'] = '${env!.humidityPct}';
    } else {
      patch['custom-iot-temp'] = null;
      patch['custom-iot-humidity'] = null;
    }

    if (scheduleCount != null) {
      fragments.add('📅 $scheduleCount 条日程');
      patch['custom-schedule-count'] = '$scheduleCount';
    } else {
      patch['custom-schedule-count'] = null;
    }

    final weatherText = weather?.trim();
    if (weatherText != null && weatherText.isNotEmpty) {
      fragments.add('☁️ $weatherText');
      patch['custom-weather'] = weatherText;
    } else {
      patch['custom-weather'] = null;
    }

    final text = fragments.isEmpty
        ? _placeholderText
        : [
            fragments.join('　'),
            if (provider.isSampleData) '（示例数据）',
          ].join('　');

    return DataSnapshotResult(text: text, customPatch: patch);
  }

  /// 模板里 data 块的占位文案（全失败时使用）。
  String get _placeholderText => template.spec.blocks
      .firstWhere((b) => b.type == DiaryTemplateBlockType.data)
      .placeholder;

  static String _formatNum(double v) =>
      v == v.roundToDouble() ? v.toInt().toString() : v.toString();

  // ================================================================
  //  跨天清理判定（§5.2 第 4 条）
  // ================================================================

  /// 判定一篇成稿是否「什么都没写」：
  ///
  /// 1. readonly 块（data 快照）一律忽略，快照内容不算写过；
  /// 2. 与模板骨架声明（heading/paragraph）多重集等价的块忽略；
  /// 3. 其余块中存在任一 trim 后非空文本即非空。
  ///
  /// 用户写了字又删光 → 文本归空 → 仍判为空，次日照常清理。
  bool isUserEmpty(DiaryDocument document) {
    final expected = template.spec.blocks
        .where((b) => b.type != DiaryTemplateBlockType.data)
        .map(_specKey)
        .toList();

    for (final block in document.blocks) {
      if (block.readonly) continue;
      final key = (
        kind: block.kind,
        level: block.level,
        text: block.text,
      );
      final match = expected.indexOf(key);
      if (match >= 0) {
        expected.removeAt(match);
        continue;
      }
      if (block.text.trim().isNotEmpty) return false;
    }
    return true;
  }

  /// 模板声明到块等价键（data 块不参与，故无 role）。
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
      DiaryTemplateBlockType.data => (
          kind: DiaryBlockKind.paragraph,
          level: null,
          text: spec.placeholder,
        ),
    };
  }
}
