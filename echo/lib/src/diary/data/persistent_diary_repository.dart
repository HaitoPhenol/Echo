import 'dart:io';

import 'package:sqflite/sqflite.dart';

import '../sy/diary_model.dart';
import '../sy/sy_id.dart';
import '../sy/sy_serializer.dart';
import 'diary_clock.dart';
import 'diary_repository.dart';
import 'diary_seed_data.dart';

/// sqflite meta 表 + 应用目录 `.sy` 正文文件的持久 [DiaryRepository]（M5）。
///
/// 分工：
/// - `diary_meta` 表存身份/状态/时间戳与列表反范式列（title/preview/
///   block_count），月年列表只读库不解析正文；
/// - 正文为 `{root}/diary/{yyyy}/{mm}/{docId}.sy`，tmp+rename 原子写；
/// - archived 删文件留 meta；exported 文件保留、打开只读。
///
/// 测试注入 [DatabaseFactory]（`databaseFactoryFfi`）与临时 [root]，
/// 生产用 sqflite 默认平台工厂。
class PersistentDiaryRepository extends DiaryRepository {
  PersistentDiaryRepository._({
    required this._db,
    required this.root,
    required this._ids,
    required this._clock,
  });

  final Database _db;
  final Directory root;
  final SyIdGenerator _ids;
  final DiaryClock _clock;
  final SySerializer _serializer = const SySerializer();

  /// 模板成稿共用同一 ID 发生器。
  @override
  SyIdGenerator get idGenerator => _ids;

  // ---- 开库 / schema ------------------------------------------------------

  static const int _schemaVersion = 1;
  static const String _table = 'diary_meta';

  /// 打开（必要时创建）仓储。[root] 为仓储根目录（生产为
  /// `<应用文档目录>/echo_diary`，不存在会创建）。
  ///
  /// 测试注入 FFI 工厂时需先自行 `sqfliteFfiInit()`；生产传 null
  /// 走 sqflite 平台默认工厂。
  static Future<PersistentDiaryRepository> open({
    required Directory root,
    SyIdGenerator? idGenerator,
    DiaryClock? clock,
    bool seedDebugData = false,
    DatabaseFactory? dbFactory,
  }) async {
    final factory = dbFactory ?? databaseFactory;
    await root.create(recursive: true);
    final dbPath = '${root.path}/diary.db';
    final db = await factory.openDatabase(
      dbPath,
      options: OpenDatabaseOptions(
        version: _schemaVersion,
        onCreate: _onCreate,
      ),
    );
    final repo = PersistentDiaryRepository._(
      db: db,
      root: root,
      ids: idGenerator ?? SyIdGenerator(),
      clock: clock ?? DiaryClock(),
    );
    await repo._healOrphanFiles();
    if (seedDebugData) await repo._installDebugSeeds();
    return repo;
  }

  static Future<void> _onCreate(Database db, int version) async {
    await db.execute('''
CREATE TABLE $_table(
  id          TEXT PRIMARY KEY,
  date        INTEGER NOT NULL UNIQUE,
  title       TEXT NOT NULL,
  state       TEXT NOT NULL DEFAULT 'draft',
  preview     TEXT NOT NULL DEFAULT '',
  block_count INTEGER NOT NULL DEFAULT 0,
  created_at  INTEGER NOT NULL,
  updated_at  INTEGER NOT NULL,
  exported_at INTEGER,
  file_path   TEXT
)''');
  }

  /// 关闭底层数据库（测试模拟进程重启时用；生产随进程存活）。
  Future<void> close() => _db.close();

  Future<void> _installDebugSeeds() async {
    final count = Sqflite.firstIntValue(
            await _db.rawQuery('SELECT COUNT(*) FROM $_table')) ??
        0;
    if (count > 0) return;
    final docs = DiarySeedData.build(
      idGenerator: _ids,
      today: _clock.today(),
    );
    await _db.transaction((txn) async {
      for (final doc in docs) {
        await _writeFile(doc);
        await _insertMeta(txn, doc, state: DiaryDocState.draft);
      }
    });
  }

  // ---- 路径 / 原子文件 ----------------------------------------------------

  static int _keyOf(DateTime date) =>
      date.year * 10000 + date.month * 100 + date.day;

  String _relativePath(DiaryDocument doc) =>
      'diary/${doc.date.year}/${doc.date.month.toString().padLeft(2, '0')}'
      '/${doc.id}.sy';

  /// tmp + rename 原子替换：硬杀最多留下 .tmp，不会读到半截 .sy。
  Future<void> _writeFile(DiaryDocument doc) async {
    final relative = _relativePath(doc);
    final target = File('${root.path}/$relative');
    await target.parent.create(recursive: true);
    final tmp = File('${target.path}.tmp');
    await tmp.writeAsBytes(_serializer.encodeBytes(doc), flush: true);
    await tmp.rename(target.path); // POSIX 上覆盖已有文件
  }

  /// 兜底自愈：删除无 meta 对应的 .sy 与所有 .tmp（崩溃/历史脏数据）。
  Future<void> _healOrphanFiles() async {
    final diaryDir = Directory('${root.path}/diary');
    if (!await diaryDir.exists()) return;
    final known = (await _db
            .query(_table, columns: ['file_path']))
        .map((row) => row['file_path'] as String?)
        .whereType<String>()
        .toSet();
    await for (final entity in diaryDir.list(recursive: true, followLinks: false)) {
      if (entity is! File) continue;
      final isSy = entity.path.endsWith('.sy');
      final isTmp = entity.path.endsWith('.sy.tmp');
      if (isTmp) {
        await entity.delete();
        continue;
      }
      if (!isSy) continue;
      final relative = entity.path.substring('${root.path}/'.length);
      if (!known.contains(relative)) await entity.delete();
    }
  }

  // ---- 读 ----------------------------------------------------------------

  @override
  DateTime today() => _clock.today();

  @override
  Future<List<int>> availableYears() async {
    final rows = await _db.rawQuery(
      'SELECT DISTINCT date / 10000 AS y FROM $_table ORDER BY y',
    );
    return rows.map((r) => r['y']! as int).toList();
  }

  @override
  Future<List<int>> monthsOfYear(int year) async {
    final rows = await _db.rawQuery(
      'SELECT DISTINCT (date / 100) % 100 AS m FROM $_table '
      'WHERE date / 10000 = ? ORDER BY m',
      [year],
    );
    return rows.map((r) => r['m']! as int).toList();
  }

  @override
  Future<List<DiaryDaySummary>> daysOfMonth(int year, int month) async {
    final rows = await _db.query(
      _table,
      where: '(date / 100) = ?',
      whereArgs: [year * 100 + month],
      orderBy: 'date ASC',
    );
    return rows.map(_summaryOfRow).toList();
  }

  @override
  Future<int> draftCountOfMonth(int year, int month) async {
    return Sqflite.firstIntValue(await _db.rawQuery(
          'SELECT COUNT(*) FROM $_table WHERE (date / 100) = ?',
          [year * 100 + month],
        )) ??
        0;
  }

  @override
  Future<DiaryDocument?> findDay(DateTime date) async {
    final row = await _metaRow(date);
    if (row == null) return null;
    final state = _stateOf(row['state']! as String);
    if (state == DiaryDocState.archived) return null;
    final relative = row['file_path'] as String?;
    if (relative == null) return null;
    final file = File('${root.path}/$relative');
    if (!await file.exists()) {
      // 极端损坏：draft 丢文件 → 清 meta 让 ensureDay 可重新成稿；
      // exported 丢文件 → 降级为不可打开（原子写保证正常不发生）。
      if (state == DiaryDocState.draft) {
        await _db.delete(_table, where: 'date = ?', whereArgs: [_keyOf(date)]);
        notifyListeners();
        return null;
      }
      return null;
    }
    final doc = _serializer.decodeBytes(await file.readAsBytes()).document;
    if (state == DiaryDocState.exported) doc.locked = true;
    return doc;
  }

  @override
  Future<bool> dayExists(DateTime date) async {
    final row = await _db.query(
      _table,
      columns: ['date'],
      where: 'date = ?',
      whereArgs: [_keyOf(date)],
    );
    return row.isNotEmpty;
  }

  @override
  Future<DiaryDocState?> stateOfDay(DateTime date) async {
    final row = await _metaRow(date);
    return row == null ? null : _stateOf(row['state']! as String);
  }

  @override
  Future<List<DiaryDocument>> draftDocumentsOfYear(int year) async {
    final rows = await _db.query(
      _table,
      where: "state = 'draft' AND (date / 10000) = ?",
      whereArgs: [year],
      orderBy: 'date ASC',
    );
    final docs = <DiaryDocument>[];
    for (final row in rows) {
      final relative = row['file_path']! as String;
      final file = File('${root.path}/$relative');
      if (await file.exists()) {
        docs.add(_serializer.decodeBytes(await file.readAsBytes()).document);
      }
    }
    return docs;
  }

  // ---- 写 / 状态迁移 ------------------------------------------------------

  @override
  Future<void> upsertDraft(DiaryDocument document) async {
    final key = _keyOf(document.date);
    await _db.transaction((txn) async {
      final existing = await txn.query(
        _table,
        where: 'date = ?',
        whereArgs: [key],
        limit: 1,
      );
      if (existing.isNotEmpty &&
          _stateOf(existing.first['state']! as String) !=
              DiaryDocState.draft) {
        throw StateError('${existing.first['state']} 态日记不可覆盖：'
            '${document.date.year}-${document.date.month}-${document.date.day}');
      }
      await _writeFile(document);
      if (existing.isEmpty) {
        await _insertMeta(txn, document, state: DiaryDocState.draft);
      } else {
        await txn.update(
          _table,
          {
            'id': document.id,
            'title': document.title,
            'preview': DiaryDaySummary.previewOf(document),
            'block_count': document.blocks.length,
            'updated_at': document.updatedAt.millisecondsSinceEpoch,
            'file_path': _relativePath(document),
          },
          where: 'date = ?',
          whereArgs: [key],
        );
      }
    });
    notifyListeners();
  }

  @override
  Future<void> markExported(
    Iterable<DateTime> dates, {
    required DateTime exportedAt,
  }) async {
    final keys = dates.map(_keyOf).toList();
    await _db.transaction((txn) async {
      // 先整批校验，任一非 draft 则全部不迁移。
      for (final key in keys) {
        final rows = await txn.query(
          _table,
          where: 'date = ?',
          whereArgs: [key],
          limit: 1,
        );
        if (rows.isEmpty) throw StateError('导出目标不存在：$key');
        requireStateTransition(
          _stateOf(rows.first['state']! as String),
          DiaryDocState.exported,
        );
      }
      final stamp = exportedAt.millisecondsSinceEpoch;
      for (final key in keys) {
        await txn.update(
          _table,
          {'state': 'exported', 'exported_at': stamp},
          where: 'date = ?',
          whereArgs: [key],
        );
      }
    });
    notifyListeners();
  }

  @override
  Future<void> archiveDay(DateTime date) async {
    final key = _keyOf(date);
    await _db.transaction((txn) async {
      final rows = await txn.query(
        _table,
        where: 'date = ?',
        whereArgs: [key],
        limit: 1,
      );
      if (rows.isEmpty) throw StateError('归档目标不存在：$date');
      requireStateTransition(
        _stateOf(rows.first['state']! as String),
        DiaryDocState.archived,
      );
      final relative = rows.first['file_path'] as String?;
      if (relative != null) {
        final file = File('${root.path}/$relative');
        if (await file.exists()) await file.delete();
      }
      await txn.update(
        _table,
        {'state': 'archived', 'file_path': null},
        where: 'date = ?',
        whereArgs: [key],
      );
    });
    notifyListeners();
  }

  @override
  Future<DiaryPruneResult> pruneEmptyBefore(
    DateTime cutoff,
    bool Function(DiaryDocument document) isEmpty, {
    bool dryRun = false,
  }) async {
    final cutoffKey = _keyOf(cutoff);
    final deleted = <DateTime>[];
    final kept = <(DateTime, String)>[];
    await _db.transaction((txn) async {
      // cutoff 之前的全部日记（含 exported/archived）都要进报告；
      // exported/archived 只带保留原因，不读正文。
      final candidates = await txn.query(
        _table,
        where: 'date < ?',
        whereArgs: [cutoffKey],
        orderBy: 'date ASC',
      );
      for (final row in candidates) {
        final rawDate = row['date']! as int;
        final day = DateTime(
          rawDate ~/ 10000,
          (rawDate ~/ 100) % 100,
          rawDate % 100,
        );
        final state = _stateOf(row['state']! as String);
        if (state != DiaryDocState.draft) {
          kept.add((day, state.name));
          continue;
        }
        final relative = row['file_path'] as String?;
        if (relative == null) continue;
        final file = File('${root.path}/$relative');
        if (!await file.exists()) continue;
        final doc =
            _serializer.decodeBytes(await file.readAsBytes()).document;
        if (!isEmpty(doc)) {
          kept.add((day, 'non-empty'));
          continue;
        }
        deleted.add(day);
        if (!dryRun) {
          await file.delete();
          await txn.delete(
            _table,
            where: 'date = ?',
            whereArgs: [rawDate],
          );
        }
      }
    });
    if (deleted.isNotEmpty && !dryRun) notifyListeners();
    return DiaryPruneResult(deleted: deleted, kept: kept);
  }

  @override
  Future<DiaryWipeResult> wipeAll() async {
    final removedDocs = Sqflite.firstIntValue(
          await _db.rawQuery('SELECT COUNT(*) FROM $_table'),
        ) ??
        0;
    var removedFiles = 0;
    // 整个 diary/ 正文目录连同空的年月父目录一起删掉；diary.db 保留
    // （连接仍打开，清空后可继续写）。
    final diaryDir = Directory('${root.path}/diary');
    if (await diaryDir.exists()) {
      await for (final entity in diaryDir.list(recursive: true)) {
        if (entity is File && entity.path.endsWith('.sy')) removedFiles++;
      }
      await diaryDir.delete(recursive: true);
    }
    await _db.delete(_table);
    if (removedDocs > 0) notifyListeners();
    return DiaryWipeResult(
      removedDocs: removedDocs,
      removedFiles: removedFiles,
    );
  }

  // ---- 行映射 -------------------------------------------------------------

  Future<Map<String, Object?>?> _metaRow(DateTime date) async {
    final rows = await _db.query(
      _table,
      where: 'date = ?',
      whereArgs: [_keyOf(date)],
      limit: 1,
    );
    return rows.isEmpty ? null : rows.first;
  }

  Future<void> _insertMeta(
    Transaction txn,
    DiaryDocument doc, {
    required DiaryDocState state,
  }) async {
    final now = doc.updatedAt.millisecondsSinceEpoch;
    await txn.insert(_table, {
      'id': doc.id,
      'date': _keyOf(doc.date),
      'title': doc.title,
      'state': state.name,
      'preview': DiaryDaySummary.previewOf(doc),
      'block_count': doc.blocks.length,
      'created_at': now,
      'updated_at': now,
      'exported_at': null,
      'file_path': _relativePath(doc),
    });
  }

  DiaryDaySummary _summaryOfRow(Map<String, Object?> row) {
    final rawDate = row['date']! as int;
    final year = rawDate ~/ 10000;
    final month = (rawDate ~/ 100) % 100;
    final day = rawDate % 100;
    return DiaryDaySummary(
      date: DateTime(year, month, day),
      title: row['title']! as String,
      preview: row['preview']! as String,
      blockCount: row['block_count']! as int,
      state: _stateOf(row['state']! as String),
      updatedAt: DateTime.fromMillisecondsSinceEpoch(
        row['updated_at']! as int,
      ),
    );
  }

  static DiaryDocState _stateOf(String raw) =>
      DiaryDocState.values.firstWhere((s) => s.name == raw);
}
