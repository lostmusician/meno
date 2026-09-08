import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:meno/models/journal_entry.dart';
import 'package:meno/services/database_service.dart';
import 'package:meno/services/markdown_export_service.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  setUpAll(sqfliteFfiInit);

  test(
    'exports complete readable metadata without licensed passage text',
    () async {
      final directory = await Directory.systemTemp.createTemp('meno-markdown-');
      addTearDown(() => directory.delete(recursive: true));
      final database = DatabaseService(
        factory: databaseFactoryFfi,
        databasePath: '${directory.path}/meno.sqlite',
        supportDirectory: directory,
      );
      addTearDown(database.close);
      const dateKey = '2026-09-08';
      final entry = DayEntry.empty(
        dateKey: dateKey,
        type: DayEntryType.daily,
      ).copyWith(title: 'Steady', content: 'Authored journal text.');
      await database.saveDay(
        JournalDay.empty(dateKey).copyWith(gratitude: 'A safe home.'),
      );
      await database.saveDayEntry(entry);
      await database.saveCheckIn(
        DailyCheckIn.forDate(
          dateKey: dateKey,
          moodAngle: .25,
          moodIntensity: .75,
        ),
      );
      final tag = await database.ensureTag('Personal');
      await database.attachTag(
        entryId: entry.id,
        tag: tag,
        source: EntryTagSource.manual,
      );
      await database.saveQuietTime(
        QuietTimeReflection(entryId: entry.id, prayer: 'Guide me.'),
      );
      await database.saveScripture(
        ScriptureReference(
          id: 'reference',
          entryId: entry.id,
          bibleId: '111',
          translationAbbreviation: 'NIV',
          passageId: 'JHN.3.16',
          reference: 'John 3:16',
          copyright: 'Licensed attribution',
        ),
      );

      final export = await MarkdownExportService(database).exportTo(directory);
      final markdown = await File(
        '${export.path}/2026/$dateKey.md',
      ).readAsString();

      expect(markdown, contains('# 2026-09-08'));
      expect(markdown, contains('Authored journal text.'));
      expect(markdown, contains('A safe home.'));
      expect(markdown, contains('Tags: Personal'));
      expect(markdown, contains('Guide me.'));
      expect(markdown, contains('John 3:16 (NIV) — Licensed attribution'));
      expect(markdown, isNot(contains('passage text')));
    },
  );
}
