import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:meno/models/journal_entry.dart';
import 'package:meno/services/database_service.dart';
import 'package:meno/services/database_schema.dart' as schema;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  setUpAll(sqfliteFfiInit);

  late DatabaseService database;
  setUp(() {
    database = DatabaseService(
      factory: databaseFactoryFfi,
      databasePath: inMemoryDatabasePath,
    );
  });
  tearDown(() => database.close());

  test(
    'stores one daily entry, additional entries, gratitude, and mood',
    () async {
      const dateKey = '2026-09-01';
      final day = JournalDay.empty(dateKey).copyWith(gratitude: 'Warm tea.');
      final daily = DayEntry.empty(
        dateKey: dateKey,
        type: DayEntryType.daily,
      ).copyWith(content: 'The main thought.');
      final additional = DayEntry.empty(
        dateKey: dateKey,
        type: DayEntryType.additional,
      ).copyWith(content: 'A later thought.');
      await database.saveDay(day);
      await database.saveDayEntry(daily);
      await database.saveDayEntry(additional);
      await database.saveCheckIn(
        DailyCheckIn.forDate(
          dateKey: dateKey,
          moodAngle: .3,
          moodIntensity: .7,
        ),
      );

      final loaded = await database.loadBinderDay(dateKey);

      expect(loaded.dailyEntry?.content, 'The main thought.');
      expect(loaded.additionalEntries.single.content, 'A later thought.');
      expect(loaded.day.gratitude, 'Warm tea.');
      expect(loaded.isComplete, isTrue);
    },
  );

  test('enforces one daily entry per date', () async {
    const dateKey = '2026-09-01';
    await database.saveDayEntry(
      DayEntry.empty(dateKey: dateKey, type: DayEntryType.daily),
    );

    expect(
      () => database.saveDayEntry(
        DayEntry.empty(dateKey: dateKey, type: DayEntryType.daily),
      ),
      throwsA(anything),
    );
  });

  test('paginates recorded dates with a stable date cursor', () async {
    for (var day = 1; day <= 24; day++) {
      final key = '2026-08-${day.toString().padLeft(2, '0')}';
      await database.saveDayEntry(
        DayEntry.empty(
          dateKey: key,
          type: DayEntryType.daily,
        ).copyWith(content: 'Entry $day'),
      );
    }

    final first = await database.binderPage(limit: 10);
    final second = await database.binderPage(
      cursor: BinderCursor(first.last.day.dateKey),
      limit: 10,
    );

    expect(first, hasLength(10));
    expect(second, hasLength(10));
    expect(
      first.last.day.dateKey.compareTo(second.first.day.dateKey),
      greaterThan(0),
    );
    expect({
      ...first.map((day) => day.day.dateKey),
      ...second.map((day) => day.day.dateKey),
    }, hasLength(20));
  });

  test('replaces the evening preference', () async {
    await database.saveEveningPreference(
      const EveningPreference(minutesAfterMidnight: 20 * 60 + 15),
    );

    final loaded = await database.eveningPreference();

    expect(loaded.hour, 20);
    expect(loaded.minute, 15);
  });

  test(
    'uses NIV when no preference exists or the legacy BSB is selected',
    () async {
      expect(await database.preferredBibleId(), 'NIV');

      await database.saveSetting(
        DatabaseService.preferredBibleSettingKey,
        'BSB',
      );

      expect(await database.preferredBibleId(), 'NIV');
    },
  );

  test('includes a mood-only day in recorded-date pagination', () async {
    const dateKey = '2026-08-30';
    await database.saveCheckIn(
      DailyCheckIn.forDate(dateKey: dateKey, moodAngle: .7, moodIntensity: .4),
    );

    final page = await database.binderPage();

    expect(page.single.day.dateKey, dateKey);
    expect(page.single.entries, isEmpty);
    expect(page.single.checkIn, isNotNull);
  });

  test('creates the current schema without legacy Scripture columns', () async {
    final db = await database.database;
    final columns = await db.rawQuery('PRAGMA table_info(entry_scriptures)');

    expect(
      columns.map((column) => column['name']),
      containsAll(<String>[
        'bible_id',
        'translation_abbreviation',
        'passage_id',
        'reference',
        'copyright',
      ]),
    );
    expect(columns.map((column) => column['name']), isNot(contains('source')));
    expect(
      columns.map((column) => column['name']),
      isNot(contains('cached_text')),
    );
    expect(
      await database.setting(DatabaseService.quietTimeLoggingSettingKey),
      'false',
    );
  });

  test('batches shared tag and Scripture candidate lookup', () async {
    const dateKey = '2026-09-01';
    final source = DayEntry.empty(
      dateKey: dateKey,
      type: DayEntryType.daily,
    ).copyWith(content: 'Source');
    final candidate = DayEntry.empty(
      dateKey: dateKey,
      type: DayEntryType.additional,
    ).copyWith(content: 'Candidate');
    await database.saveDayEntry(source);
    await database.saveDayEntry(candidate);
    final tag = await database.ensureTag('Prayer');
    for (final entry in [source, candidate]) {
      await database.attachTag(
        entryId: entry.id,
        tag: tag,
        source: EntryTagSource.manual,
      );
      await database.saveScripture(
        ScriptureReference(
          id: 'scripture-${entry.id}',
          entryId: entry.id,
          bibleId: '111',
          translationAbbreviation: 'NIV',
          passageId: 'JHN.3.16',
          reference: 'John 3:16',
          copyright: 'Licensed attribution',
        ),
      );
    }

    expect(await database.tagUsageCounts(), {'prayer': 2});
    expect(await database.sharedTagCandidates(source.id), [
      (entryId: candidate.id, tagName: 'Prayer'),
    ]);
    expect(await database.sharedScriptureCandidates(source.id), [
      (entryId: candidate.id, reference: 'John 3:16'),
    ]);
  });

  test(
    'migrates schema 1 transactionally after creating a safety snapshot',
    () async {
      final directory = await Directory.systemTemp.createTemp('meno-migrate-');
      addTearDown(() => directory.delete(recursive: true));
      final path = '${directory.path}/meno.sqlite';
      final old = await databaseFactoryFfi.openDatabase(
        path,
        options: OpenDatabaseOptions(
          version: 1,
          onCreate: (db, version) async {
            await schema.createDatabaseSchema(db);
            await db.execute('DROP TABLE data_imports');
          },
        ),
      );
      await old.close();

      final migrated = DatabaseService(
        factory: databaseFactoryFfi,
        databasePath: path,
        supportDirectory: directory,
      );
      addTearDown(migrated.close);
      final opened = await migrated.database;

      expect(await opened.getVersion(), DatabaseService.schemaVersion);
      expect(
        await opened.rawQuery(
          "SELECT name FROM sqlite_master WHERE type='table' AND name='data_imports'",
        ),
        isNotEmpty,
      );
      final snapshots = Directory('${directory.path}/Backups')
          .listSync()
          .whereType<File>()
          .where((file) => file.path.contains('pre-migration-v1-to-v2'));
      expect(snapshots, hasLength(1));
    },
  );

  test('refuses a higher-version database without deleting it', () async {
    final directory = await Directory.systemTemp.createTemp('meno-reset-');
    addTearDown(() => directory.delete(recursive: true));
    final path = '${directory.path}/development.sqlite';
    final old = await databaseFactoryFfi.openDatabase(
      path,
      options: OpenDatabaseOptions(
        version: 4,
        onCreate: (db, version) async {
          await db.execute('CREATE TABLE legacy_marker (value TEXT NOT NULL)');
          await db.insert('legacy_marker', {'value': 'preserve me'});
        },
      ),
    );
    await old.close();

    final reset = DatabaseService(
      factory: databaseFactoryFfi,
      databasePath: path,
    );
    addTearDown(reset.close);
    await expectLater(
      reset.database,
      throwsA(isA<UnsupportedDatabaseVersionException>()),
    );
    final preserved = await databaseFactoryFfi.openDatabase(
      path,
      options: OpenDatabaseOptions(readOnly: true, singleInstance: false),
    );
    addTearDown(preserved.close);
    expect(await preserved.getVersion(), 4);
    expect(await preserved.query('legacy_marker'), [
      {'value': 'preserve me'},
    ]);
  });
}
