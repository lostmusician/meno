import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';

import 'database_service.dart';

class LegacyImportResult {
  const LegacyImportResult({
    required this.importedEntries,
    required this.importedDays,
    required this.skippedBecauseAlreadyImported,
    required this.archiveDirectory,
  });

  final int importedEntries;
  final int importedDays;
  final bool skippedBecauseAlreadyImported;
  final Directory archiveDirectory;
}

class LegacyImportService {
  LegacyImportService(this._database);

  static const _uuid = Uuid();
  final DatabaseService _database;

  Future<File?> discoverSottoDatabase() async {
    final current = await _database.databaseFilePath;
    final candidate = File(p.join(p.dirname(current), 'sotto.sqlite'));
    return await candidate.exists() ? candidate : null;
  }

  Future<LegacyImportResult> importSotto(File source) async {
    final bytes = await source.readAsBytes();
    final checksum = sha256.convert(bytes).toString();
    final importKey = 'sotto-schema4-$checksum';
    final support = await _database.supportDirectory;
    final archive = Directory(p.join(support.path, 'Legacy Archive'));
    await archive.create(recursive: true);
    final sourceArchive = File(p.join(archive.path, 'sotto-$checksum.sqlite'));
    if (!await sourceArchive.exists()) {
      await source.copy(sourceArchive.path);
      await _makeReadOnly(sourceArchive);
    }
    final currentArchive = File(
      p.join(archive.path, 'meno-before-sotto-import-$checksum.sqlite'),
    );
    if (!await currentArchive.exists()) {
      await _database.createConsistentCopy(currentArchive);
      await _makeReadOnly(currentArchive);
    }

    final db = await _database.database;
    final already = await db.query(
      'data_imports',
      where: 'import_key = ?',
      whereArgs: [importKey],
      limit: 1,
    );
    if (already.isNotEmpty) {
      return LegacyImportResult(
        importedEntries: 0,
        importedDays: 0,
        skippedBecauseAlreadyImported: true,
        archiveDirectory: archive,
      );
    }

    final escaped = source.path.replaceAll("'", "''");
    await db.execute("ATTACH DATABASE '$escaped' AS sotto");
    var importedEntries = 0;
    var importedDays = 0;
    try {
      await db.transaction((txn) async {
        final entryIds = <String, String>{};
        if (await _hasTable(txn, 'journal_days')) {
          for (final row in await txn.rawQuery(
            'SELECT * FROM sotto.journal_days',
          )) {
            final dateKey = row['date_key']! as String;
            final existing = await txn.query(
              'journal_days',
              where: 'date_key = ?',
              whereArgs: [dateKey],
              limit: 1,
            );
            if (existing.isEmpty) {
              await txn.insert('journal_days', row);
              importedDays++;
            } else {
              final oldGratitude = (row['gratitude'] as String? ?? '').trim();
              final newGratitude =
                  (existing.single['gratitude'] as String? ?? '').trim();
              if (oldGratitude.isNotEmpty &&
                  newGratitude.isNotEmpty &&
                  oldGratitude != newGratitude) {
                await _insertImportedEntry(
                  txn,
                  dateKey: dateKey,
                  title: 'Imported Sotto gratitude ($dateKey)',
                  content: oldGratitude,
                  createdAt: row['created_at']! as String,
                  updatedAt: row['updated_at']! as String,
                );
                importedEntries++;
              } else if (newGratitude.isEmpty && oldGratitude.isNotEmpty) {
                await txn.update(
                  'journal_days',
                  {'gratitude': oldGratitude, 'updated_at': row['updated_at']},
                  where: 'date_key = ?',
                  whereArgs: [dateKey],
                );
              }
            }
          }
        }

        if (await _hasTable(txn, 'day_entries')) {
          for (final row in await txn.rawQuery(
            'SELECT * FROM sotto.day_entries',
          )) {
            final originalId = row['id']! as String;
            await _ensureDay(
              txn,
              row['date_key']! as String,
              row['created_at']! as String,
            );
            final existingById = await txn.query(
              'day_entries',
              where: 'id = ?',
              whereArgs: [originalId],
              limit: 1,
            );
            final dailyOnDate = row['entry_type'] == 'daily'
                ? await txn.query(
                    'day_entries',
                    where: "date_key = ? AND entry_type = 'daily'",
                    whereArgs: [row['date_key']],
                    limit: 1,
                  )
                : const <Map<String, Object?>>[];
            if (existingById.isEmpty && dailyOnDate.isEmpty) {
              await txn.insert('day_entries', _currentEntryRow(row));
              entryIds[originalId] = originalId;
              importedEntries++;
            } else if (existingById.isNotEmpty &&
                _sameEntry(existingById.single, row)) {
              entryIds[originalId] = originalId;
            } else {
              final newId = _uuid.v4();
              await txn.insert('day_entries', {
                ..._currentEntryRow(row),
                'id': newId,
                'entry_type': 'additional',
                'title': _importTitle(row['title'] as String?),
              });
              entryIds[originalId] = newId;
              importedEntries++;
            }
          }
        }

        if (await _hasTable(txn, 'journal_entries')) {
          for (final row in await txn.rawQuery(
            'SELECT * FROM sotto.journal_entries',
          )) {
            final originalId = row['id']! as String;
            var destinationId = entryIds[originalId];
            if (destinationId == null) {
              final createdAt = row['created_at']! as String;
              final dateKey = createdAt.substring(0, 10);
              await _ensureDay(txn, dateKey, createdAt);
              destinationId = _uuid.v4();
              await txn.insert('day_entries', {
                'id': destinationId,
                'date_key': dateKey,
                'entry_type': 'additional',
                'entry_purpose': 'freeform',
                'title': _importTitle(row['title'] as String?),
                'content': row['content'] as String? ?? '',
                'created_at': createdAt,
                'updated_at': row['updated_at'],
              });
              entryIds[originalId] = destinationId;
              importedEntries++;
            }
            final question = (row['reflection_question'] as String? ?? '')
                .trim();
            final reply = (row['reflection_reply'] as String? ?? '').trim();
            if (question.isNotEmpty || reply.isNotEmpty) {
              final destination = (await txn.query(
                'day_entries',
                where: 'id = ?',
                whereArgs: [destinationId],
                limit: 1,
              )).single;
              final reflection = [
                '\n\n---\nReflection',
                if (question.isNotEmpty) question,
                if (reply.isNotEmpty) reply,
              ].join('\n\n');
              final content = destination['content']! as String;
              if (!content.contains(reflection)) {
                await txn.update(
                  'day_entries',
                  {'content': '$content$reflection'},
                  where: 'id = ?',
                  whereArgs: [destinationId],
                );
              }
            }
          }
        }

        await _importCheckIns(txn);
        await _importSettings(txn);
        await _importTags(txn, entryIds);
        await _importScriptures(txn, entryIds);
        await _importQuietTime(txn, entryIds);
        await txn.insert('data_imports', {
          'import_key': importKey,
          'source_checksum': checksum,
          'imported_at': DateTime.now().toUtc().toIso8601String(),
          'details': jsonEncode({
            'entries': importedEntries,
            'days': importedDays,
          }),
        });
      });
    } finally {
      await db.execute('DETACH DATABASE sotto');
    }
    await _database.rebuildDerivedData();
    return LegacyImportResult(
      importedEntries: importedEntries,
      importedDays: importedDays,
      skippedBecauseAlreadyImported: false,
      archiveDirectory: archive,
    );
  }

  Future<bool> _hasTable(DatabaseExecutor db, String name) async =>
      (await db.rawQuery(
        "SELECT 1 FROM sotto.sqlite_master WHERE type='table' AND name = ?",
        [name],
      )).isNotEmpty;

  Map<String, Object?> _currentEntryRow(Map<String, Object?> row) => {
    'id': row['id'],
    'date_key': row['date_key'],
    'entry_type': row['entry_type'],
    'entry_purpose': row['entry_purpose'] ?? 'freeform',
    'title': row['title'] ?? '',
    'content': row['content'] ?? '',
    'created_at': row['created_at'],
    'updated_at': row['updated_at'],
  };

  bool _sameEntry(Map<String, Object?> current, Map<String, Object?> old) =>
      current['date_key'] == old['date_key'] &&
      current['entry_type'] == old['entry_type'] &&
      current['title'] == old['title'] &&
      current['content'] == old['content'];

  String _importTitle(String? title) => title == null || title.trim().isEmpty
      ? 'Imported from Sotto'
      : 'Imported from Sotto — ${title.trim()}';

  Future<void> _ensureDay(
    DatabaseExecutor db,
    String dateKey,
    String timestamp,
  ) async {
    await db.insert('journal_days', {
      'date_key': dateKey,
      'gratitude': '',
      'created_at': timestamp,
      'updated_at': timestamp,
    }, conflictAlgorithm: ConflictAlgorithm.ignore);
  }

  Future<void> _insertImportedEntry(
    DatabaseExecutor db, {
    required String dateKey,
    required String title,
    required String content,
    required String createdAt,
    required String updatedAt,
  }) async {
    await _ensureDay(db, dateKey, createdAt);
    await db.insert('day_entries', {
      'id': _uuid.v4(),
      'date_key': dateKey,
      'entry_type': 'additional',
      'entry_purpose': 'freeform',
      'title': title,
      'content': content,
      'created_at': createdAt,
      'updated_at': updatedAt,
    });
  }

  Future<void> _importCheckIns(DatabaseExecutor txn) async {
    if (!await _hasTable(txn, 'daily_checkins')) return;
    for (final row in await txn.rawQuery(
      'SELECT * FROM sotto.daily_checkins',
    )) {
      final dateKey = row['date_key']! as String;
      await _ensureDay(txn, dateKey, row['created_at']! as String);
      final current = await txn.query(
        'daily_checkins',
        where: 'date_key = ?',
        whereArgs: [dateKey],
        limit: 1,
      );
      if (current.isEmpty ||
          (row['updated_at']! as String).compareTo(
                current.single['updated_at']! as String,
              ) >
              0) {
        await txn.insert(
          'daily_checkins',
          row,
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }
    }
  }

  Future<void> _importSettings(DatabaseExecutor txn) async {
    if (!await _hasTable(txn, 'app_settings')) return;
    for (final row in await txn.rawQuery('SELECT * FROM sotto.app_settings')) {
      await txn.insert(
        'app_settings',
        row,
        conflictAlgorithm: ConflictAlgorithm.ignore,
      );
    }
  }

  Future<void> _importTags(
    DatabaseExecutor txn,
    Map<String, String> entryIds,
  ) async {
    if (!await _hasTable(txn, 'tags')) return;
    final tagIds = <String, String>{};
    for (final row in await txn.rawQuery('SELECT * FROM sotto.tags')) {
      final normalized = row['normalized_name']! as String;
      final existing = await txn.query(
        'tags',
        columns: ['id'],
        where: 'normalized_name = ?',
        whereArgs: [normalized],
        limit: 1,
      );
      if (existing.isEmpty) {
        await txn.insert('tags', row);
        tagIds[row['id']! as String] = row['id']! as String;
      } else {
        tagIds[row['id']! as String] = existing.single['id']! as String;
      }
    }
    if (!await _hasTable(txn, 'entry_tags')) return;
    for (final source in await txn.rawQuery('SELECT * FROM sotto.entry_tags')) {
      final entryId = entryIds[source['entry_id']];
      final tagId = tagIds[source['tag_id']];
      if (entryId == null || tagId == null) continue;
      await txn.insert('entry_tags', {
        ...source,
        'entry_id': entryId,
        'tag_id': tagId,
      }, conflictAlgorithm: ConflictAlgorithm.ignore);
    }
  }

  Future<void> _importScriptures(
    DatabaseExecutor txn,
    Map<String, String> entryIds,
  ) async {
    if (!await _hasTable(txn, 'entry_scriptures')) return;
    for (final row in await txn.rawQuery(
      'SELECT * FROM sotto.entry_scriptures',
    )) {
      final entryId = entryIds[row['entry_id']];
      if (entryId == null) continue;
      var scriptureId = row['id']! as String;
      final existing = await txn.query(
        'entry_scriptures',
        where: 'id = ?',
        whereArgs: [scriptureId],
        limit: 1,
      );
      if (existing.isNotEmpty &&
          (existing.single['entry_id'] != entryId ||
              existing.single['passage_id'] != row['passage_id'])) {
        scriptureId = _uuid.v4();
      }
      await txn.insert('entry_scriptures', {
        'id': scriptureId,
        'entry_id': entryId,
        'bible_id': row['bible_id'],
        'translation_abbreviation': row['translation_abbreviation'],
        'passage_id': row['passage_id'],
        'reference': row['reference'],
        'copyright': row['copyright'] ?? '',
        'created_at': row['created_at'],
      }, conflictAlgorithm: ConflictAlgorithm.ignore);
    }
  }

  Future<void> _importQuietTime(
    DatabaseExecutor txn,
    Map<String, String> entryIds,
  ) async {
    if (!await _hasTable(txn, 'quiet_time_reflections')) return;
    for (final row in await txn.rawQuery(
      'SELECT * FROM sotto.quiet_time_reflections',
    )) {
      final entryId = entryIds[row['entry_id']];
      if (entryId == null) continue;
      final existing = await txn.query(
        'quiet_time_reflections',
        where: 'entry_id = ?',
        whereArgs: [entryId],
        limit: 1,
      );
      if (existing.isEmpty) {
        await txn.insert('quiet_time_reflections', {
          ...row,
          'entry_id': entryId,
        });
        continue;
      }
      final same = const [
        'observation',
        'application',
        'prayer',
      ].every((field) => existing.single[field] == row[field]);
      if (!same) {
        final entry = (await txn.query(
          'day_entries',
          where: 'id = ?',
          whereArgs: [entryId],
          limit: 1,
        )).single;
        final imported = StringBuffer('\n\n---\nImported Sotto Quiet Time');
        for (final field in const ['observation', 'application', 'prayer']) {
          final value = (row[field] as String? ?? '').trim();
          if (value.isNotEmpty) {
            imported.write(
              '\n\n${field[0].toUpperCase()}${field.substring(1)}\n\n$value',
            );
          }
        }
        await txn.update(
          'day_entries',
          {'content': '${entry['content']}$imported'},
          where: 'id = ?',
          whereArgs: [entryId],
        );
      }
    }
  }

  Future<void> _makeReadOnly(File file) async {
    if (Platform.isMacOS || Platform.isLinux) {
      await Process.run('chmod', ['444', file.path]);
    }
  }
}
