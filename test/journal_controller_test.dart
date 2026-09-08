import 'package:flutter_test/flutter_test.dart';
import 'package:meno/models/journal_entry.dart';
import 'package:meno/providers/journal_providers.dart';
import 'package:meno/services/database_service.dart';

import 'support/session_test_doubles.dart';

void main() {
  test('before evening opens an empty daily journal', () async {
    final database = FakeDatabaseService();
    final controller = JournalController(database);
    final now = DateTime(2026, 9, 1, 10);

    await controller.initialize(now: now);

    expect(controller.state.phase, AppPhase.journal);
    expect(controller.state.selectedEntry?.type, DayEntryType.daily);
    expect(controller.state.selectedDateKey, localDateKey(now));
  });

  test('loads and persists writing appearance preferences', () async {
    final database = FakeDatabaseService();
    database.settings[DatabaseService.editorTextSizeSettingKey] = 'medium';
    database.settings[DatabaseService.glassModeSettingKey] = 'true';
    final controller = JournalController(database);

    await controller.initialize(now: DateTime(2026, 9, 1, 10));

    expect(controller.state.editorTextSize, EditorTextSize.medium);
    expect(controller.state.glassModeEnabled, isTrue);

    await controller.setEditorTextSize(EditorTextSize.small);
    await controller.setGlassModeEnabled(false);

    expect(controller.state.editorTextSize, EditorTextSize.small);
    expect(controller.state.glassModeEnabled, isFalse);
    expect(
      database.settings[DatabaseService.editorTextSizeSettingKey],
      'small',
    );
    expect(database.settings[DatabaseService.glassModeSettingKey], 'false');
  });

  test('invalid or missing appearance settings use safe defaults', () async {
    final database = FakeDatabaseService();
    database.settings[DatabaseService.editorTextSizeSettingKey] = 'huge';
    final controller = JournalController(database);

    await controller.initialize(now: DateTime(2026, 9, 1, 10));

    expect(controller.state.editorTextSize, EditorTextSize.large);
    expect(controller.state.glassModeEnabled, isFalse);
  });

  test('at evening opens mood first, then the missing journal', () async {
    final database = FakeDatabaseService();
    final controller = JournalController(database);
    final now = DateTime(2026, 9, 1, 18);

    await controller.initialize(now: now);
    expect(controller.state.phase, AppPhase.mood);

    controller.updateMood(.4, .8, now: now);
    await controller.finishMood(now: now);

    expect(controller.state.phase, AppPhase.journal);
    expect(database.checkIns[localDateKey(now)], isNotNull);
  });

  test('5:59 PM stays journal-first and 6:00 PM becomes mood-first', () async {
    final before = JournalController(FakeDatabaseService());
    final evening = JournalController(FakeDatabaseService());

    await before.initialize(now: DateTime(2026, 9, 1, 17, 59));
    await evening.initialize(now: DateTime(2026, 9, 1, 18));

    expect(before.state.phase, AppPhase.journal);
    expect(evening.state.phase, AppPhase.mood);
  });

  test(
    'before evening, an existing mood still routes to the journal',
    () async {
      final database = FakeDatabaseService();
      const dateKey = '2026-09-01';
      await database.saveCheckIn(
        DailyCheckIn.forDate(
          dateKey: dateKey,
          moodAngle: .1,
          moodIntensity: .5,
        ),
      );
      final controller = JournalController(database);

      await controller.initialize(now: DateTime(2026, 9, 1, 10));

      expect(controller.state.phase, AppPhase.journal);
    },
  );

  test(
    'completed journal before evening opens binder with mood reminder',
    () async {
      final database = FakeDatabaseService();
      final now = DateTime(2026, 9, 1, 12);
      final dateKey = localDateKey(now);
      await database.saveDayEntry(
        DayEntry.empty(
          dateKey: dateKey,
          type: DayEntryType.daily,
        ).copyWith(content: 'Already wrote today.'),
      );
      final controller = JournalController(database);

      await controller.initialize(now: now);

      expect(controller.state.phase, AppPhase.binder);
      expect(controller.state.showMoodReminder, isTrue);
    },
  );

  test('completed journal and mood open binder', () async {
    final database = FakeDatabaseService();
    final now = DateTime(2026, 9, 1, 20);
    final dateKey = localDateKey(now);
    await database.saveDayEntry(
      DayEntry.empty(
        dateKey: dateKey,
        type: DayEntryType.daily,
      ).copyWith(content: 'A complete page.'),
    );
    await database.saveCheckIn(
      DailyCheckIn.forDate(dateKey: dateKey, moodAngle: .2, moodIntensity: .6),
    );
    final controller = JournalController(database);

    await controller.initialize(now: now);

    expect(controller.state.phase, AppPhase.binder);
    expect(controller.state.showMoodReminder, isFalse);
  });

  test(
    'keeps additional entries separate and discards an empty new entry',
    () async {
      final database = FakeDatabaseService();
      final controller = JournalController(database);
      await controller.initialize(now: DateTime(2026, 9, 1, 10));
      controller.updateEntry(content: 'Main daily journal.');
      await controller.saveCurrentEntry();

      await controller.addEntry(now: DateTime(2026, 9, 1, 12));
      controller.updateEntry(title: 'Lunch', content: 'A separate thought.');
      await controller.saveCurrentEntry();
      final savedAdditionalId = controller.state.selectedEntryId;

      await controller.addEntry(now: DateTime(2026, 9, 1, 14));
      await controller.selectEntry(controller.state.dailyEntry!.id);

      expect(controller.state.entries, hasLength(2));
      expect(
        database.entries[savedAdditionalId]?.content,
        'A separate thought.',
      );
    },
  );

  test('historical edits return to binder without launch routing', () async {
    final database = FakeDatabaseService();
    final controller = JournalController(database);
    await controller.initialize(now: DateTime(2026, 9, 1, 10));

    await controller.openDay('2026-08-20');
    controller.updateEntry(content: 'Corrected history.');
    await controller.finishEditing(now: DateTime(2026, 9, 1, 20));

    expect(controller.state.phase, AppPhase.binder);
    expect(
      database.entries.values
          .singleWhere((entry) => entry.dateKey == '2026-08-20')
          .content,
      'Corrected history.',
    );
  });

  test('a failed autosave does not switch entries or lose text', () async {
    final database = FakeDatabaseService();
    final controller = JournalController(database);
    await controller.initialize(now: DateTime(2026, 9, 1, 10));
    controller.updateEntry(content: 'Daily text.');
    await controller.saveCurrentEntry();
    await controller.addEntry(now: DateTime(2026, 9, 1, 12));
    controller.updateEntry(content: 'Unsaved but still present.');
    final additionalId = controller.state.selectedEntryId;
    database.failEntrySaves = true;

    await controller.selectEntry(controller.state.dailyEntry!.id);

    expect(controller.state.selectedEntryId, additionalId);
    expect(
      controller.state.selectedEntry?.content,
      'Unsaved but still present.',
    );
    expect(controller.state.error, isA<StateError>());
  });
}
