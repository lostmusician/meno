import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart' as mobile;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../models/journal_entry.dart';
import 'database_schema.dart' as schema;

typedef SharedTagCandidate = ({String entryId, String tagName});
typedef SharedScriptureCandidate = ({String entryId, String reference});

class UnsupportedDatabaseVersionException implements Exception {
  const UnsupportedDatabaseVersionException(this.found, this.supported);

  final int found;
  final int supported;

  @override
  String toString() =>
      'This journal uses database version $found, but this version of Meno '
      'supports up to version $supported. Install a newer Meno build.';
}

class DatabaseIntegrityException implements Exception {
  const DatabaseIntegrityException(this.message);

  final String message;

  @override
  String toString() => message;
}

class DatabaseService {
  DatabaseService({
    DatabaseFactory? factory,
    String? databasePath,
    Directory? supportDirectory,
  }) : _injectedFactory = factory,
       _injectedPath = databasePath,
       _injectedSupportDirectory = supportDirectory;

  static const schemaVersion = schema.databaseSchemaVersion;
  static const eveningSettingKey = schema.eveningSettingKey;
  static const smartOrganizationSettingKey = schema.smartOrganizationSettingKey;
  static const quietTimeLoggingSettingKey = schema.quietTimeLoggingSettingKey;
  static const preferredBibleSettingKey = schema.preferredBibleSettingKey;
  static const editorTextSizeSettingKey = schema.editorTextSizeSettingKey;
  static const glassModeSettingKey = schema.glassModeSettingKey;
  static const lastExternalBackupSettingKey =
      schema.lastExternalBackupSettingKey;
  static const firstRestorePromptSettingKey =
      schema.firstRestorePromptSettingKey;

  final DatabaseFactory? _injectedFactory;
  final String? _injectedPath;
  final Directory? _injectedSupportDirectory;
  Future<Database>? _databaseFuture;

  Future<Database> get database => _databaseFuture ??= _open();

  Future<String> get databaseFilePath async =>
      _injectedPath ?? await _defaultPath();

  Future<Directory> get supportDirectory async =>
      _injectedSupportDirectory ?? await getApplicationSupportDirectory();

  Future<Database> _open() async {
    final factory = _injectedFactory ?? _platformFactory();
    final path = _injectedPath ?? await _defaultPath();
    await _preflightExistingDatabase(factory, path);
    return factory.openDatabase(
      path,
      options: OpenDatabaseOptions(
        version: schemaVersion,
        onConfigure: (db) => db.execute('PRAGMA foreign_keys = ON'),
        onCreate: (db, version) => schema.createDatabaseSchema(db),
        onUpgrade: schema.migrateDatabaseSchema,
        onDowngrade: (db, oldVersion, newVersion) =>
            throw UnsupportedDatabaseVersionException(oldVersion, newVersion),
      ),
    );
  }

  Future<void> _preflightExistingDatabase(
    DatabaseFactory factory,
    String path,
  ) async {
    if (path == inMemoryDatabasePath || !await File(path).exists()) return;
    final probe = await factory.openDatabase(
      path,
      options: OpenDatabaseOptions(readOnly: true, singleInstance: false),
    );
    try {
      await _assertIntegrity(probe);
      final found = await probe.getVersion();
      if (found > schemaVersion) {
        throw UnsupportedDatabaseVersionException(found, schemaVersion);
      }
      if (found > 0 && found < schemaVersion) {
        await _createPreMigrationSnapshot(
          probe,
          path,
          kind: 'pre-migration-v$found-to-v$schemaVersion',
          keep: 5,
        );
        return;
      }
    } finally {
      if (probe.isOpen) await probe.close();
    }
  }

  static Future<void> _assertIntegrity(DatabaseExecutor db) async {
    final integrity = await db.rawQuery('PRAGMA integrity_check');
    if (integrity.isEmpty || integrity.first.values.first != 'ok') {
      throw DatabaseIntegrityException(
        'The journal database failed its integrity check.',
      );
    }
    final foreignKeys = await db.rawQuery('PRAGMA foreign_key_check');
    if (foreignKeys.isNotEmpty) {
      throw DatabaseIntegrityException(
        'The journal database contains broken references.',
      );
    }
  }

  Future<File> createConsistentCopy(File destination) async {
    final db = await database;
    await _assertIntegrity(db);
    await destination.parent.create(recursive: true);
    if (await destination.exists()) await destination.delete();
    final escaped = destination.path.replaceAll("'", "''");
    await db.execute("VACUUM INTO '$escaped'");
    return destination;
  }

  Future<File> createSnapshot({required String kind, int keep = 5}) async {
    final path = await databaseFilePath;
    if (path == inMemoryDatabasePath) {
      throw StateError('Snapshots require a file-backed database.');
    }
    final directory = Directory(
      p.join((await supportDirectory).path, 'Backups'),
    );
    await directory.create(recursive: true);
    final timestamp = DateTime.now().toUtc().toIso8601String().replaceAll(
      ':',
      '-',
    );
    final destination = File(p.join(directory.path, '$kind-$timestamp.sqlite'));
    await createConsistentCopy(destination);
    await _pruneSnapshots(directory, kind, keep);
    return destination;
  }

  Future<File?> createDailySnapshotIfNeeded({DateTime? now}) async {
    final path = await databaseFilePath;
    if (path == inMemoryDatabasePath || !await File(path).exists()) return null;
    final date = (now ?? DateTime.now()).toLocal();
    final key =
        '${date.year.toString().padLeft(4, '0')}-'
        '${date.month.toString().padLeft(2, '0')}-'
        '${date.day.toString().padLeft(2, '0')}';
    final directory = Directory(
      p.join((await supportDirectory).path, 'Backups'),
    );
    await directory.create(recursive: true);
    final existing = directory.listSync().whereType<File>().any(
      (file) => p.basename(file.path).startsWith('daily-$key-'),
    );
    if (existing) return null;
    final timestamp = DateTime.now().toUtc().toIso8601String().replaceAll(
      ':',
      '-',
    );
    final destination = File(
      p.join(directory.path, 'daily-$key-$timestamp.sqlite'),
    );
    await createConsistentCopy(destination);
    await _pruneSnapshots(directory, 'daily-', 30);
    return destination;
  }

  Future<void> _createPreMigrationSnapshot(
    DatabaseExecutor source,
    String sourcePath, {
    required String kind,
    required int keep,
  }) async {
    final directory = Directory(p.join(p.dirname(sourcePath), 'Backups'));
    await directory.create(recursive: true);
    final timestamp = DateTime.now().toUtc().toIso8601String().replaceAll(
      ':',
      '-',
    );
    final destination = p.join(directory.path, '$kind-$timestamp.sqlite');
    final escaped = destination.replaceAll("'", "''");
    await source.execute("VACUUM INTO '$escaped'");
    await _pruneSnapshots(directory, kind.split('-v').first, keep);
  }

  static Future<void> _pruneSnapshots(
    Directory directory,
    String prefix,
    int keep,
  ) async {
    final files =
        directory
            .listSync()
            .whereType<File>()
            .where((file) => p.basename(file.path).startsWith(prefix))
            .toList()
          ..sort((a, b) => b.path.compareTo(a.path));
    for (final file in files.skip(keep)) {
      await file.delete();
    }
  }

  Future<void> verifyIntegrity() async => _assertIntegrity(await database);

  Future<File> copyRawDatabase(File destination) async {
    final source = File(await databaseFilePath);
    if (!await source.exists()) {
      throw StateError('The journal database file does not exist.');
    }
    await destination.parent.create(recursive: true);
    if (await destination.exists()) await destination.delete();
    return source.copy(destination.path);
  }

  Future<Map<String, int>> recordCounts() async {
    final db = await database;
    const tables = <String>[
      'journal_days',
      'day_entries',
      'daily_checkins',
      'tags',
      'entry_tags',
      'entry_scriptures',
      'quiet_time_reflections',
      'app_settings',
    ];
    return {
      for (final table in tables)
        table:
            mobile.Sqflite.firstIntValue(
              await db.rawQuery('SELECT COUNT(*) FROM $table'),
            ) ??
            0,
    };
  }

  Future<bool> shouldOfferFirstRestore() async {
    if (await setting(firstRestorePromptSettingKey) == 'true') return false;
    final counts = await recordCounts();
    return (counts['day_entries'] ?? 0) == 0;
  }

  Future<void> restoreFromDatabaseFile(File source) async {
    if (!await source.exists()) {
      throw ArgumentError.value(
        source.path,
        'source',
        'Backup database is missing.',
      );
    }
    final destinationPath = await databaseFilePath;
    if (destinationPath == inMemoryDatabasePath) {
      throw StateError('Restore requires a file-backed database.');
    }
    await createSnapshot(kind: 'pre-restore', keep: 5);
    final destination = File(destinationPath);
    final staged = File('$destinationPath.restore-staged');
    final rollback = File('$destinationPath.restore-rollback');
    if (await staged.exists()) await staged.delete();
    if (await rollback.exists()) await rollback.delete();
    await source.copy(staged.path);

    final stagedService = DatabaseService(
      factory: _injectedFactory,
      databasePath: staged.path,
      supportDirectory: await supportDirectory,
    );
    try {
      await stagedService.verifyIntegrity();
      await stagedService.rebuildDerivedData();
      await stagedService.verifyIntegrity();
    } finally {
      await stagedService.close();
    }

    await close();
    try {
      for (final suffix in const ['-wal', '-shm']) {
        final sidecar = File('$destinationPath$suffix');
        if (await sidecar.exists()) await sidecar.delete();
      }
      if (await destination.exists()) await destination.rename(rollback.path);
      await staged.rename(destination.path);
      await verifyIntegrity();
      if (await rollback.exists()) await rollback.delete();
    } catch (_) {
      await close();
      if (await destination.exists()) await destination.delete();
      if (await rollback.exists()) await rollback.rename(destination.path);
      rethrow;
    } finally {
      if (await staged.exists()) await staged.delete();
    }
  }

  Future<Map<String, int>> validateCandidateDatabase(File source) async {
    final candidate = DatabaseService(
      factory: _injectedFactory,
      databasePath: source.path,
      supportDirectory: source.parent,
    );
    try {
      await candidate.verifyIntegrity();
      return await candidate.recordCounts();
    } finally {
      await candidate.close();
    }
  }

  Future<void> rebuildDerivedData() async {
    final db = await database;
    await db.transaction((txn) async {
      await txn.delete('entry_relationships');
      await txn.delete('entry_embeddings');
      await txn.delete('entry_search');
      final entries = await txn.query('day_entries', columns: ['id']);
      for (final row in entries) {
        await _syncSearchEntry(txn, row['id']! as String);
      }
    });
  }

  Future<void> _syncSearchEntry(DatabaseExecutor db, String entryId) async {
    final entries = await db.rawQuery(
      '''
      SELECT e.id AS entry_id, e.date_key, e.title, e.content, d.gratitude,
             COALESCE((SELECT group_concat(t.name, ' ')
                       FROM entry_tags et JOIN tags t ON t.id = et.tag_id
                       WHERE et.entry_id = e.id), '') AS tags,
             COALESCE((SELECT observation || ' ' || application || ' ' || prayer
                       FROM quiet_time_reflections q
                       WHERE q.entry_id = e.id), '') AS quiet_time
      FROM day_entries e JOIN journal_days d ON d.date_key = e.date_key
      WHERE e.id = ?
    ''',
      [entryId],
    );
    await db.delete(
      'entry_search',
      where: 'entry_id = ?',
      whereArgs: [entryId],
    );
    if (entries.isNotEmpty) {
      await db.insert('entry_search', entries.single);
    }
  }

  DatabaseFactory _platformFactory() {
    if (Platform.isWindows || Platform.isLinux) {
      sqfliteFfiInit();
      return databaseFactoryFfi;
    }
    return mobile.databaseFactory;
  }

  Future<String> _defaultPath() async {
    final directory =
        _injectedSupportDirectory ?? await getApplicationSupportDirectory();
    await directory.create(recursive: true);
    return p.join(directory.path, 'meno.sqlite');
  }

  Future<JournalDay> ensureDay(String dateKey, {DateTime? now}) async {
    final db = await database;
    final existing = await journalDay(dateKey);
    if (existing != null) return existing;
    final day = JournalDay.empty(dateKey, now: now);
    await db.insert(
      'journal_days',
      day.toMap(),
      conflictAlgorithm: ConflictAlgorithm.ignore,
    );
    return await journalDay(dateKey) ?? day;
  }

  Future<JournalDay?> journalDay(String dateKey) async {
    final db = await database;
    final rows = await db.query(
      'journal_days',
      where: 'date_key = ?',
      whereArgs: [dateKey],
      limit: 1,
    );
    return rows.isEmpty ? null : JournalDay.fromMap(rows.first);
  }

  Future<void> saveDay(JournalDay day) async {
    final db = await database;
    final changed = await db.update(
      'journal_days',
      day.toMap(),
      where: 'date_key = ?',
      whereArgs: [day.dateKey],
    );
    if (changed == 0) await db.insert('journal_days', day.toMap());
    final entries = await db.query(
      'day_entries',
      columns: ['id'],
      where: 'date_key = ?',
      whereArgs: [day.dateKey],
    );
    for (final entry in entries) {
      await _syncSearchEntry(db, entry['id']! as String);
    }
  }

  Future<List<DayEntry>> entriesForDay(String dateKey) async {
    final db = await database;
    final rows = await db.query(
      'day_entries',
      where: 'date_key = ?',
      whereArgs: [dateKey],
      orderBy: "CASE entry_type WHEN 'daily' THEN 0 ELSE 1 END, created_at DESC, id DESC",
    );
    return rows.map(DayEntry.fromMap).toList();
  }

  Future<DayEntry?> entryById(String id) async {
    final db = await database;
    final rows = await db.query(
      'day_entries',
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    return rows.isEmpty ? null : DayEntry.fromMap(rows.first);
  }

  Future<List<DayEntry>> allNonEmptyEntries() async {
    final db = await database;
    final rows = await db.query(
      'day_entries',
      where: "trim(content) != '' OR trim(title) != ''",
      orderBy: 'updated_at DESC',
    );
    return rows.map(DayEntry.fromMap).toList();
  }

  Future<List<String>> entryIdsForTag(String tagId) async {
    final db = await database;
    final rows = await db.query(
      'entry_tags',
      columns: ['entry_id'],
      where: 'tag_id = ?',
      whereArgs: [tagId],
    );
    return rows.map((row) => row['entry_id']! as String).toList();
  }

  Future<Map<String, int>> tagUsageCounts() async {
    final db = await database;
    final rows = await db.rawQuery('''
      SELECT t.normalized_name, COUNT(et.entry_id) AS usage_count
      FROM tags t
      LEFT JOIN entry_tags et ON et.tag_id = t.id
      GROUP BY t.id, t.normalized_name
      ''');
    return {
      for (final row in rows)
        row['normalized_name']! as String: row['usage_count']! as int,
    };
  }

  Future<List<SharedTagCandidate>> sharedTagCandidates(String entryId) async {
    final db = await database;
    final rows = await db.rawQuery(
      '''
      SELECT DISTINCT candidate.entry_id, t.name AS tag_name
      FROM entry_tags source
      JOIN entry_tags candidate ON candidate.tag_id = source.tag_id
      JOIN tags t ON t.id = source.tag_id
      WHERE source.entry_id = ? AND candidate.entry_id != ?
      ''',
      [entryId, entryId],
    );
    return [
      for (final row in rows)
        (
          entryId: row['entry_id']! as String,
          tagName: row['tag_name']! as String,
        ),
    ];
  }

  Future<List<SharedScriptureCandidate>> sharedScriptureCandidates(
    String entryId,
  ) async {
    final db = await database;
    final rows = await db.rawQuery(
      '''
      SELECT DISTINCT candidate.entry_id, source.reference
      FROM entry_scriptures source
      JOIN entry_scriptures candidate
        ON candidate.bible_id = source.bible_id
       AND candidate.passage_id = source.passage_id
      WHERE source.entry_id = ? AND candidate.entry_id != ?
      ''',
      [entryId, entryId],
    );
    return [
      for (final row in rows)
        (
          entryId: row['entry_id']! as String,
          reference: row['reference']! as String,
        ),
    ];
  }

  Future<void> saveDayEntry(DayEntry entry) async {
    final db = await database;
    await ensureDay(entry.dateKey, now: entry.createdAt);
    final changed = await db.update(
      'day_entries',
      entry.toMap(),
      where: 'id = ?',
      whereArgs: [entry.id],
    );
    if (changed == 0) await db.insert('day_entries', entry.toMap());
    await _syncSearchEntry(db, entry.id);
  }

  Future<void> deleteDayEntry(String id) async {
    final db = await database;
    await db.delete('day_entries', where: 'id = ?', whereArgs: [id]);
    await db.delete('entry_search', where: 'entry_id = ?', whereArgs: [id]);
  }

  Future<DailyCheckIn?> checkInForDate(String dateKey) async {
    final db = await database;
    final rows = await db.query(
      'daily_checkins',
      where: 'date_key = ?',
      whereArgs: [dateKey],
      limit: 1,
    );
    return rows.isEmpty ? null : DailyCheckIn.fromMap(rows.first);
  }

  Future<void> saveCheckIn(DailyCheckIn checkIn) async {
    final db = await database;
    await ensureDay(checkIn.dateKey, now: checkIn.createdAt);
    final existing = await checkInForDate(checkIn.dateKey);
    final row = checkIn.copyWith(updatedAt: DateTime.now().toUtc()).toMap();
    if (existing != null) {
      row['created_at'] = existing.createdAt.toIso8601String();
    }
    await db.insert(
      'daily_checkins',
      row,
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<BinderDay> loadBinderDay(String dateKey, {bool create = false}) async {
    final day = create
        ? await ensureDay(dateKey)
        : await journalDay(dateKey) ?? JournalDay.empty(dateKey);
    final values = await Future.wait<Object?>([
      entriesForDay(dateKey),
      checkInForDate(dateKey),
    ]);
    return BinderDay(
      day: day,
      entries: values[0] as List<DayEntry>,
      checkIn: values[1] as DailyCheckIn?,
    );
  }

  Future<List<BinderDay>> binderPage({
    BinderCursor? cursor,
    int limit = 20,
  }) async {
    final db = await database;
    final where = StringBuffer('''
      (trim(gratitude) != '' OR
       EXISTS (SELECT 1 FROM day_entries e
               WHERE e.date_key = journal_days.date_key
                 AND (trim(e.content) != '' OR trim(e.title) != '')) OR
       EXISTS (SELECT 1 FROM daily_checkins c
               WHERE c.date_key = journal_days.date_key))
    ''');
    final args = <Object?>[];
    if (cursor != null) {
      where.write(' AND date_key < ?');
      args.add(cursor.dateKey);
    }
    final rows = await db.query(
      'journal_days',
      where: where.toString(),
      whereArgs: args,
      orderBy: 'date_key DESC',
      limit: limit,
    );
    return Future.wait(
      rows.map((row) => loadBinderDay(row['date_key']! as String)),
    );
  }

  Future<EveningPreference> eveningPreference() async {
    final db = await database;
    final rows = await db.query(
      'app_settings',
      where: 'setting_key = ?',
      whereArgs: [eveningSettingKey],
      limit: 1,
    );
    final value = rows.isEmpty
        ? 18 * 60
        : int.tryParse(rows.first['setting_value']! as String) ?? 18 * 60;
    return EveningPreference(minutesAfterMidnight: value.clamp(0, 1439));
  }

  Future<void> saveEveningPreference(EveningPreference preference) async {
    final db = await database;
    await db.insert('app_settings', {
      'setting_key': eveningSettingKey,
      'setting_value': '${preference.minutesAfterMidnight.clamp(0, 1439)}',
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<String?> setting(String key) async {
    final db = await database;
    final rows = await db.query(
      'app_settings',
      columns: ['setting_value'],
      where: 'setting_key = ?',
      whereArgs: [key],
      limit: 1,
    );
    return rows.firstOrNull?['setting_value'] as String?;
  }

  Future<void> saveSetting(String key, String value) async {
    final db = await database;
    await db.insert('app_settings', {
      'setting_key': key,
      'setting_value': value,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<bool> smartOrganizationEnabled() async =>
      await setting(smartOrganizationSettingKey) == 'true';

  Future<bool> quietTimeLoggingEnabled() async =>
      await setting(quietTimeLoggingSettingKey) == 'true';

  Future<String> preferredBibleId() async {
    final value = await setting(preferredBibleSettingKey);
    return value == null || value == 'BSB' ? 'NIV' : value;
  }

  Future<String> editorTextSizePreference() async {
    final value = await setting(editorTextSizeSettingKey);
    return const {'small', 'medium', 'large'}.contains(value)
        ? value!
        : 'large';
  }

  Future<bool> glassModeEnabled() async =>
      await setting(glassModeSettingKey) == 'true';

  Future<List<JournalTag>> allTags() async {
    final db = await database;
    final rows = await db.query('tags', orderBy: 'name COLLATE NOCASE');
    return rows.map(JournalTag.fromMap).toList();
  }

  Future<JournalTag> ensureTag(String name, {DateTime? now}) async {
    final normalized = normalizeTagName(name);
    if (normalized.isEmpty) throw ArgumentError.value(name, 'name');
    final db = await database;
    final rows = await db.query(
      'tags',
      where: 'normalized_name = ?',
      whereArgs: [normalized],
      limit: 1,
    );
    if (rows.isNotEmpty) return JournalTag.fromMap(rows.first);
    final tag = JournalTag.create(name, now: now);
    await db.insert('tags', tag.toMap());
    return tag;
  }

  Future<List<EntryTag>> tagsForEntry(String entryId) async {
    final db = await database;
    final rows = await db.rawQuery(
      '''
      SELECT t.*, et.source, et.confidence
      FROM entry_tags et JOIN tags t ON t.id = et.tag_id
      WHERE et.entry_id = ?
      ORDER BY CASE et.source WHEN 'manual' THEN 0 ELSE 1 END,
               COALESCE(et.confidence, 1) DESC, t.name COLLATE NOCASE
    ''',
      [entryId],
    );
    return rows
        .map(
          (row) => EntryTag(
            entryId: entryId,
            tag: JournalTag.fromMap(row),
            source: EntryTagSource.values.byName(row['source']! as String),
            confidence: (row['confidence'] as num?)?.toDouble(),
          ),
        )
        .toList();
  }

  Future<void> attachTag({
    required String entryId,
    required JournalTag tag,
    required EntryTagSource source,
    double? confidence,
  }) async {
    final db = await database;
    final existing = await db.query(
      'entry_tags',
      where: 'entry_id = ? AND tag_id = ?',
      whereArgs: [entryId, tag.id],
      limit: 1,
    );
    if (existing.isNotEmpty && existing.first['source'] == 'manual') return;
    await db.insert('entry_tags', {
      'entry_id': entryId,
      'tag_id': tag.id,
      'source': source.name,
      'confidence': confidence,
      'created_at': DateTime.now().toUtc().toIso8601String(),
    }, conflictAlgorithm: ConflictAlgorithm.replace);
    await _syncSearchEntry(db, entryId);
  }

  Future<void> detachTag(String entryId, String tagId) async {
    final db = await database;
    await db.delete(
      'entry_tags',
      where: 'entry_id = ? AND tag_id = ?',
      whereArgs: [entryId, tagId],
    );
    await _syncSearchEntry(db, entryId);
  }

  Future<JournalTag> renameTag(String tagId, String name) async {
    final normalized = normalizeTagName(name);
    if (normalized.isEmpty) throw ArgumentError.value(name, 'name');
    final db = await database;
    final rows = await db.query('tags', where: 'id = ?', whereArgs: [tagId]);
    if (rows.isEmpty) throw StateError('Tag not found: $tagId');
    final existing = await db.query(
      'tags',
      where: 'normalized_name = ? AND id != ?',
      whereArgs: [normalized, tagId],
      limit: 1,
    );
    if (existing.isNotEmpty) {
      final target = JournalTag.fromMap(existing.first);
      await mergeTags(tagId, target.id);
      return target;
    }
    final updated = JournalTag.fromMap(rows.first).copyWith(
      name: name.trim(),
      normalizedName: normalized,
      updatedAt: DateTime.now().toUtc(),
    );
    final entryIds = await entryIdsForTag(tagId);
    await db.update(
      'tags',
      updated.toMap(),
      where: 'id = ?',
      whereArgs: [tagId],
    );
    for (final entryId in entryIds) {
      await _syncSearchEntry(db, entryId);
    }
    return updated;
  }

  Future<void> mergeTags(String sourceTagId, String targetTagId) async {
    if (sourceTagId == targetTagId) return;
    final db = await database;
    await db.transaction((txn) async {
      final sourceRows = await txn.query(
        'entry_tags',
        where: 'tag_id = ?',
        whereArgs: [sourceTagId],
      );
      for (final source in sourceRows) {
        final entryId = source['entry_id']! as String;
        final targetRows = await txn.query(
          'entry_tags',
          where: 'entry_id = ? AND tag_id = ?',
          whereArgs: [entryId, targetTagId],
          limit: 1,
        );
        final target = targetRows.firstOrNull;
        final manual =
            source['source'] == EntryTagSource.manual.name ||
            target?['source'] == EntryTagSource.manual.name;
        final confidences = <double>[
          if (source['confidence'] case final num value) value.toDouble(),
          if (target?['confidence'] case final num value) value.toDouble(),
        ];
        await txn.insert('entry_tags', {
          'entry_id': entryId,
          'tag_id': targetTagId,
          'source': manual
              ? EntryTagSource.manual.name
              : EntryTagSource.generated.name,
          'confidence': confidences.isEmpty
              ? null
              : confidences.reduce(math.max),
          'created_at': target?['created_at'] ?? source['created_at'],
        }, conflictAlgorithm: ConflictAlgorithm.replace);
      }
      await txn.delete('tags', where: 'id = ?', whereArgs: [sourceTagId]);
      for (final source in sourceRows) {
        await _syncSearchEntry(txn, source['entry_id']! as String);
      }
    });
  }

  Future<void> replaceGeneratedTags(
    String entryId,
    List<(String, double)> candidates,
  ) async {
    final db = await database;
    await db.transaction((txn) async {
      await txn.delete(
        'entry_tags',
        where: "entry_id = ? AND source = 'generated'",
        whereArgs: [entryId],
      );
      for (final candidate in candidates.take(5)) {
        final tag = await _ensureTagWithExecutor(txn, candidate.$1);
        await txn.insert('entry_tags', {
          'entry_id': entryId,
          'tag_id': tag.id,
          'source': EntryTagSource.generated.name,
          'confidence': candidate.$2.clamp(0, 1),
          'created_at': DateTime.now().toUtc().toIso8601String(),
        }, conflictAlgorithm: ConflictAlgorithm.ignore);
      }
      await _syncSearchEntry(txn, entryId);
    });
  }

  Future<JournalTag> _ensureTagWithExecutor(
    DatabaseExecutor db,
    String name,
  ) async {
    final normalized = normalizeTagName(name);
    final existing = await db.query(
      'tags',
      where: 'normalized_name = ?',
      whereArgs: [normalized],
      limit: 1,
    );
    if (existing.isNotEmpty) return JournalTag.fromMap(existing.first);
    final tag = JournalTag.create(name);
    await db.insert(
      'tags',
      tag.toMap(),
      conflictAlgorithm: ConflictAlgorithm.ignore,
    );
    final saved = await db.query(
      'tags',
      where: 'normalized_name = ?',
      whereArgs: [normalized],
      limit: 1,
    );
    return JournalTag.fromMap(saved.first);
  }

  Future<List<JournalSearchResult>> searchEntries(
    JournalSearchQuery query, {
    int limit = 50,
  }) async {
    final db = await database;
    final joins = <String>['JOIN entry_search s ON s.entry_id = e.id'];
    final where = <String>[];
    final args = <Object?>[];
    if (query.text.trim().isNotEmpty) {
      where.add('entry_search MATCH ?');
      args.add(query.text.trim().replaceAll('"', '""'));
    }
    if (query.purpose != null) {
      where.add('e.entry_purpose = ?');
      args.add(query.purpose!.name);
    }
    if (query.fromDateKey != null) {
      where.add('e.date_key >= ?');
      args.add(query.fromDateKey);
    }
    if (query.toDateKey != null) {
      where.add('e.date_key <= ?');
      args.add(query.toDateKey);
    }
    if (query.scriptureBook != null) {
      where.add(
        'EXISTS (SELECT 1 FROM entry_scriptures es WHERE es.entry_id = e.id AND es.passage_id LIKE ?)',
      );
      args.add('${query.scriptureBook}.%');
    }
    for (final tagId in query.tagIds) {
      where.add(
        'EXISTS (SELECT 1 FROM entry_tags et WHERE et.entry_id = e.id AND et.tag_id = ?)',
      );
      args.add(tagId);
    }
    final rows = await db.rawQuery(
      '''
      SELECT DISTINCT e.* FROM day_entries e ${joins.join(' ')}
      ${where.isEmpty ? '' : 'WHERE ${where.join(' AND ')}'}
      ORDER BY e.date_key DESC, e.updated_at DESC LIMIT ?
    ''',
      [...args, limit],
    );
    final results = <JournalSearchResult>[];
    for (final row in rows) {
      final entry = DayEntry.fromMap(row);
      results.add(
        JournalSearchResult(entry: entry, tags: await tagsForEntry(entry.id)),
      );
    }
    return results;
  }

  Future<List<EntryRelationship>> relationshipsForEntry(
    String entryId, {
    int limit = 8,
  }) async {
    final db = await database;
    final rows = await db.query(
      'entry_relationships',
      where: 'source_entry_id = ?',
      whereArgs: [entryId],
      orderBy: 'score DESC',
      limit: limit,
    );
    return rows
        .map(
          (row) => EntryRelationship(
            sourceEntryId: row['source_entry_id']! as String,
            targetEntryId: row['target_entry_id']! as String,
            score: (row['score']! as num).toDouble(),
            reasons: (row['reasons'] as String? ?? '')
                .split('|')
                .where((value) => value.isNotEmpty)
                .toList(),
          ),
        )
        .toList();
  }

  Future<void> saveEmbedding({
    required String entryId,
    required String modelId,
    required String contentHash,
    required List<double> vector,
  }) async {
    final db = await database;
    final values = Float32List.fromList(vector);
    await db.insert('entry_embeddings', {
      'entry_id': entryId,
      'model_id': modelId,
      'content_hash': contentHash,
      'dimensions': vector.length,
      'vector_blob': values.buffer.asUint8List(),
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<({String contentHash, List<double> vector})?> embeddingForEntry(
    String entryId,
    String modelId,
  ) async {
    final db = await database;
    final rows = await db.query(
      'entry_embeddings',
      where: 'entry_id = ? AND model_id = ?',
      whereArgs: [entryId, modelId],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return _embeddingRecord(rows.first);
  }

  Future<Map<String, ({String contentHash, List<double> vector})>>
  embeddingsForModel(String modelId) async {
    final db = await database;
    final rows = await db.query(
      'entry_embeddings',
      where: 'model_id = ?',
      whereArgs: [modelId],
    );
    return {
      for (final row in rows) row['entry_id']! as String: _embeddingRecord(row),
    };
  }

  ({String contentHash, List<double> vector}) _embeddingRecord(
    Map<String, Object?> row,
  ) {
    final bytes = row['vector_blob']! as Uint8List;
    final aligned = Uint8List.fromList(bytes);
    final vector = aligned.buffer
        .asFloat32List(0, row['dimensions']! as int)
        .map((value) => value.toDouble())
        .toList();
    return (contentHash: row['content_hash']! as String, vector: vector);
  }

  Future<void> saveRelationships(
    String sourceEntryId,
    List<EntryRelationship> relationships, {
    String modelId = 'shared-tags-v1',
  }) async {
    final db = await database;
    await db.transaction((txn) async {
      await txn.delete(
        'entry_relationships',
        where: 'source_entry_id = ?',
        whereArgs: [sourceEntryId],
      );
      for (final relationship in relationships.take(8)) {
        await txn.insert('entry_relationships', {
          'source_entry_id': sourceEntryId,
          'target_entry_id': relationship.targetEntryId,
          'score': relationship.score,
          'reasons': relationship.reasons.join('|'),
          'model_id': modelId,
          'updated_at': DateTime.now().toUtc().toIso8601String(),
        });
      }
    });
  }

  Future<List<ScriptureReference>> scripturesForEntry(String entryId) async {
    final db = await database;
    final rows = await db.query(
      'entry_scriptures',
      where: 'entry_id = ?',
      whereArgs: [entryId],
      orderBy: 'created_at',
    );
    return rows.map(ScriptureReference.fromMap).toList();
  }

  Future<void> saveScripture(ScriptureReference reference) async {
    final db = await database;
    await db.insert('entry_scriptures', {
      'id': reference.id,
      'entry_id': reference.entryId,
      'bible_id': reference.bibleId,
      'translation_abbreviation': reference.translationAbbreviation,
      'passage_id': reference.passageId,
      'reference': reference.reference,
      'copyright': reference.copyright,
      'created_at': DateTime.now().toUtc().toIso8601String(),
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<void> deleteScripture(String id) async {
    final db = await database;
    await db.delete('entry_scriptures', where: 'id = ?', whereArgs: [id]);
  }

  Future<QuietTimeReflection?> quietTimeForEntry(String entryId) async {
    final db = await database;
    final rows = await db.query(
      'quiet_time_reflections',
      where: 'entry_id = ?',
      whereArgs: [entryId],
      limit: 1,
    );
    return rows.isEmpty ? null : QuietTimeReflection.fromMap(rows.first);
  }

  Future<void> saveQuietTime(QuietTimeReflection reflection) async {
    final db = await database;
    await db.insert('quiet_time_reflections', {
      'entry_id': reflection.entryId,
      'observation': reflection.observation,
      'application': reflection.application,
      'prayer': reflection.prayer,
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    }, conflictAlgorithm: ConflictAlgorithm.replace);
    await _syncSearchEntry(db, reflection.entryId);
  }

  Future<void> close() async {
    final pendingDatabase = _databaseFuture;
    _databaseFuture = null;
    if (pendingDatabase != null) {
      try {
        await (await pendingDatabase).close();
      } catch (_) {
        // Opening can fail for a corrupt or newer database. There is no open
        // handle to close in that case, and close must remain safe to call.
      }
    }
  }
}
