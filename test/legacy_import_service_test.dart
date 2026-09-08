import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:meno/services/database_service.dart';
import 'package:meno/services/legacy_import_service.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  setUpAll(sqfliteFfiInit);

  test('schema-4 Sotto history imports once and preserves reflections', () async {
    final directory = await Directory.systemTemp.createTemp('meno-sotto-test-');
    addTearDown(() => directory.delete(recursive: true));
    final sourcePath = '${directory.path}/sotto.sqlite';
    final source = await databaseFactoryFfi.openDatabase(sourcePath);
    await source.execute('PRAGMA user_version = 4');
    await source.execute('''CREATE TABLE journal_days (
      date_key TEXT PRIMARY KEY, gratitude TEXT NOT NULL,
      created_at TEXT NOT NULL, updated_at TEXT NOT NULL)''');
    await source.execute(
      '''CREATE TABLE day_entries (
      id TEXT PRIMARY KEY, date_key TEXT NOT NULL, entry_type TEXT NOT NULL,
      title TEXT NOT NULL, content TEXT NOT NULL, created_at TEXT NOT NULL,
      updated_at TEXT NOT NULL, entry_purpose TEXT NOT NULL DEFAULT 'freeform')''',
    );
    await source.execute('''CREATE TABLE journal_entries (
      id TEXT PRIMARY KEY, title TEXT NOT NULL, content TEXT NOT NULL,
      created_at TEXT NOT NULL, updated_at TEXT NOT NULL,
      reflection_question TEXT, reflection_reply TEXT NOT NULL DEFAULT '')''');
    await source.execute('''CREATE TABLE daily_checkins (
      date_key TEXT PRIMARY KEY, mood_angle REAL NOT NULL,
      mood_intensity REAL NOT NULL, created_at TEXT NOT NULL,
      updated_at TEXT NOT NULL)''');
    await source.execute(
      'CREATE TABLE app_settings (setting_key TEXT PRIMARY KEY, setting_value TEXT NOT NULL)',
    );
    const timestamp = '2026-09-01T10:00:00.000Z';
    await source.insert('journal_days', {
      'date_key': '2026-09-01',
      'gratitude': 'Old gratitude',
      'created_at': timestamp,
      'updated_at': timestamp,
    });
    await source.insert('day_entries', {
      'id': 'old-entry',
      'date_key': '2026-09-01',
      'entry_type': 'daily',
      'entry_purpose': 'freeform',
      'title': 'Old title',
      'content': 'Old content',
      'created_at': timestamp,
      'updated_at': timestamp,
    });
    await source.insert('journal_entries', {
      'id': 'old-entry',
      'title': 'Old title',
      'content': 'Old content',
      'created_at': timestamp,
      'updated_at': timestamp,
      'reflection_question': 'What mattered?',
      'reflection_reply': 'Being present.',
    });
    await source.close();

    final database = DatabaseService(
      factory: databaseFactoryFfi,
      databasePath: '${directory.path}/meno.sqlite',
      supportDirectory: directory,
    );
    addTearDown(database.close);
    final importer = LegacyImportService(database);
    final first = await importer.importSotto(File(sourcePath));
    final second = await importer.importSotto(File(sourcePath));

    expect(first.importedEntries, 1);
    expect(second.skippedBecauseAlreadyImported, isTrue);
    final entries = await database.entriesForDay('2026-09-01');
    expect(entries, hasLength(1));
    expect(entries.single.content, contains('What mattered?'));
    expect(entries.single.content, contains('Being present.'));
    expect(
      (await database.journalDay('2026-09-01'))?.gratitude,
      'Old gratitude',
    );
    expect(first.archiveDirectory.listSync().whereType<File>(), hasLength(2));
  });
}
