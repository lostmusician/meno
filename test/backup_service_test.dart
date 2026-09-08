import 'dart:io';

import 'package:archive/archive.dart';
import 'package:archive/archive_io.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meno/models/journal_entry.dart';
import 'package:meno/services/backup_service.dart';
import 'package:meno/services/database_service.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  setUpAll(sqfliteFfiInit);

  test('backup round-trips authored data and settings', () async {
    final directory = await Directory.systemTemp.createTemp(
      'meno-backup-test-',
    );
    addTearDown(() => directory.delete(recursive: true));
    final database = DatabaseService(
      factory: databaseFactoryFfi,
      databasePath: '${directory.path}/meno.sqlite',
      supportDirectory: directory,
    );
    addTearDown(database.close);
    final entry = DayEntry.empty(
      dateKey: '2026-09-08',
      type: DayEntryType.daily,
    ).copyWith(title: 'A day', content: 'Kept safely.');
    await database.saveDay(
      JournalDay.empty(entry.dateKey).copyWith(gratitude: 'Recovery paths.'),
    );
    await database.saveDayEntry(entry);
    await database.saveCheckIn(
      DailyCheckIn.forDate(
        dateKey: entry.dateKey,
        moodAngle: .4,
        moodIntensity: .8,
      ),
    );
    final tag = await database.ensureTag('Trust');
    await database.attachTag(
      entryId: entry.id,
      tag: tag,
      source: EntryTagSource.manual,
    );
    await database.saveScripture(
      ScriptureReference(
        id: 'scripture',
        entryId: entry.id,
        bibleId: '111',
        translationAbbreviation: 'NIV',
        passageId: 'PSA.23.1',
        reference: 'Psalm 23:1',
        copyright: 'Attribution only',
      ),
    );
    await database.saveQuietTime(
      QuietTimeReflection(entryId: entry.id, observation: 'Stillness.'),
    );
    await database.saveSetting('custom', 'value');

    final service = BackupService(database);
    final backup = await service.createBackup(
      File('${directory.path}/journal.meno-backup'),
      appVersion: 'test',
    );
    await database.saveDayEntry(
      DayEntry.empty(
        dateKey: entry.dateKey,
        type: DayEntryType.additional,
      ).copyWith(content: 'Not in backup.'),
    );

    await service.restore(backup.file);

    final restored = await database.entryById(entry.id);
    expect(restored?.content, 'Kept safely.');
    expect((await database.entriesForDay(entry.dateKey)), hasLength(1));
    expect((await database.tagsForEntry(entry.id)).single.tag.name, 'Trust');
    expect(
      (await database.scripturesForEntry(entry.id)).single.reference,
      'Psalm 23:1',
    );
    expect(
      (await database.quietTimeForEntry(entry.id))?.observation,
      'Stillness.',
    );
    expect(await database.setting('custom'), 'value');
    expect(backup.manifest.recordCounts['day_entries'], 1);
  });

  test('tampered backup is rejected without changing the journal', () async {
    final directory = await Directory.systemTemp.createTemp(
      'meno-tamper-test-',
    );
    addTearDown(() => directory.delete(recursive: true));
    final database = DatabaseService(
      factory: databaseFactoryFfi,
      databasePath: '${directory.path}/meno.sqlite',
      supportDirectory: directory,
    );
    addTearDown(database.close);
    final entry = DayEntry.empty(
      dateKey: '2026-09-08',
      type: DayEntryType.daily,
    ).copyWith(content: 'Original remains.');
    await database.saveDayEntry(entry);
    final backup = await BackupService(database).createBackup(
      File('${directory.path}/journal.meno-backup'),
      appVersion: 'test',
    );
    final archive = ZipDecoder().decodeBytes(await backup.file.readAsBytes());
    final sqlite = archive.files.singleWhere(
      (file) => file.name == 'journal.sqlite',
    );
    final bytes = List<int>.from(sqlite.content as List<int>);
    bytes[100] ^= 0xff;
    final tampered = Archive();
    for (final file in archive.files) {
      final content = file.name == 'journal.sqlite'
          ? bytes
          : List<int>.from(file.content as List<int>);
      tampered.addFile(ArchiveFile(file.name, content.length, content));
    }
    await backup.file.writeAsBytes(ZipEncoder().encode(tampered)!);

    await expectLater(
      BackupService(database).restore(backup.file),
      throwsA(isA<BackupValidationException>()),
    );
    expect((await database.entryById(entry.id))?.content, 'Original remains.');
  });
}
