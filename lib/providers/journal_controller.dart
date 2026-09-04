import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/journal_entry.dart';
import '../services/database_service.dart';
import 'service_providers.dart';

class JournalAppState {
  const JournalAppState({
    this.phase = AppPhase.loading,
    this.selectedDateKey,
    this.day,
    this.entries = const [],
    this.selectedEntryId,
    this.checkIn,
    this.eveningPreference = const EveningPreference(),
    this.showMoodReminder = false,
    this.smartOrganizationEnabled = false,
    this.quietTimeLoggingEnabled = false,
    this.preferredBibleId = 'NIV',
    this.isLoading = false,
    this.error,
  });

  final AppPhase phase;
  final String? selectedDateKey;
  final JournalDay? day;
  final List<DayEntry> entries;
  final String? selectedEntryId;
  final DailyCheckIn? checkIn;
  final EveningPreference eveningPreference;
  final bool showMoodReminder;
  final bool smartOrganizationEnabled;
  final bool quietTimeLoggingEnabled;
  final String preferredBibleId;
  final bool isLoading;
  final Object? error;

  DayEntry? get selectedEntry =>
      entries.where((entry) => entry.id == selectedEntryId).firstOrNull;
  DayEntry? get dailyEntry =>
      entries.where((entry) => entry.type == DayEntryType.daily).firstOrNull;
  bool get journalComplete => dailyEntry?.content.trim().isNotEmpty ?? false;
  bool get dayComplete => journalComplete && checkIn != null;

  JournalAppState copyWith({
    AppPhase? phase,
    String? selectedDateKey,
    JournalDay? day,
    List<DayEntry>? entries,
    String? selectedEntryId,
    bool clearSelectedEntry = false,
    DailyCheckIn? checkIn,
    bool clearCheckIn = false,
    EveningPreference? eveningPreference,
    bool? showMoodReminder,
    bool? smartOrganizationEnabled,
    bool? quietTimeLoggingEnabled,
    String? preferredBibleId,
    bool? isLoading,
    Object? error,
    bool clearError = false,
  }) => JournalAppState(
    phase: phase ?? this.phase,
    selectedDateKey: selectedDateKey ?? this.selectedDateKey,
    day: day ?? this.day,
    entries: entries ?? this.entries,
    selectedEntryId: clearSelectedEntry
        ? null
        : selectedEntryId ?? this.selectedEntryId,
    checkIn: clearCheckIn ? null : checkIn ?? this.checkIn,
    eveningPreference: eveningPreference ?? this.eveningPreference,
    showMoodReminder: showMoodReminder ?? this.showMoodReminder,
    smartOrganizationEnabled:
        smartOrganizationEnabled ?? this.smartOrganizationEnabled,
    quietTimeLoggingEnabled:
        quietTimeLoggingEnabled ?? this.quietTimeLoggingEnabled,
    preferredBibleId: preferredBibleId ?? this.preferredBibleId,
    isLoading: isLoading ?? this.isLoading,
    error: clearError ? null : error ?? this.error,
  );
}

class JournalController extends StateNotifier<JournalAppState> {
  JournalController(this._database) : super(const JournalAppState());

  final DatabaseService _database;
  bool _continueToJournalAfterMood = false;

  Future<void> initialize({DateTime? now}) async {
    final timestamp = now ?? DateTime.now();
    final dateKey = localDateKey(timestamp);
    state = state.copyWith(isLoading: true, clearError: true);
    try {
      final preferences = await Future.wait<Object>([
        _database.eveningPreference(),
        _database.smartOrganizationEnabled(),
        _database.quietTimeLoggingEnabled(),
        _database.preferredBibleId(),
      ]);
      final preference = preferences[0] as EveningPreference;
      final binderDay = await _database.loadBinderDay(dateKey);
      state = state.copyWith(
        selectedDateKey: dateKey,
        day: binderDay.day,
        entries: binderDay.entries,
        checkIn: binderDay.checkIn,
        clearCheckIn: binderDay.checkIn == null,
        eveningPreference: preference,
        smartOrganizationEnabled: preferences[1] as bool,
        quietTimeLoggingEnabled: preferences[2] as bool,
        preferredBibleId: preferences[3] as String,
        isLoading: false,
      );
      if (binderDay.isComplete) {
        state = state.copyWith(phase: AppPhase.binder, showMoodReminder: false);
      } else if (preference.isEvening(timestamp) && binderDay.checkIn == null) {
        await openMood(dateKey, continueToJournal: true);
      } else if (!binderDay.journalComplete) {
        await openDay(dateKey, now: timestamp);
      } else {
        state = state.copyWith(
          phase: AppPhase.binder,
          showMoodReminder: binderDay.checkIn == null,
        );
      }
    } catch (error) {
      state = state.copyWith(
        phase: AppPhase.binder,
        isLoading: false,
        error: error,
      );
    }
  }

  Future<void> openDay(
    String dateKey, {
    bool createAdditional = false,
    DateTime? now,
  }) async {
    if (!await saveCurrentEntry()) return;
    final binderDay = await _database.loadBinderDay(dateKey, create: true);
    var entries = binderDay.entries;
    var daily = entries
        .where((entry) => entry.type == DayEntryType.daily)
        .firstOrNull;
    if (daily == null) {
      daily = DayEntry.empty(
        dateKey: dateKey,
        type: DayEntryType.daily,
        now: now,
      );
      await _database.saveDayEntry(daily);
      entries = [daily, ...entries];
    }
    state = state.copyWith(
      phase: AppPhase.journal,
      selectedDateKey: dateKey,
      day: binderDay.day,
      entries: entries,
      selectedEntryId: daily.id,
      checkIn: binderDay.checkIn,
      clearCheckIn: binderDay.checkIn == null,
      showMoodReminder: false,
      clearError: true,
    );
    if (createAdditional) await addEntry(now: now);
  }

  Future<void> selectEntry(String entryId) async {
    if (state.phase != AppPhase.journal || entryId == state.selectedEntryId) {
      return;
    }
    if (!await saveCurrentEntry()) return;
    if (state.entries.any((entry) => entry.id == entryId)) {
      state = state.copyWith(selectedEntryId: entryId);
    }
  }

  Future<void> addEntry({DateTime? now}) async {
    final dateKey = state.selectedDateKey;
    if (state.phase != AppPhase.journal || dateKey == null) return;
    if (!await saveCurrentEntry()) return;
    final entry = DayEntry.empty(
      dateKey: dateKey,
      type: DayEntryType.additional,
      now: now,
    );
    state = state.copyWith(
      entries: [
        state.dailyEntry!,
        entry,
        ...state.entries.where((e) => e.type == DayEntryType.additional),
      ],
      selectedEntryId: entry.id,
      clearError: true,
    );
  }

  Future<void> addQuietTime({DateTime? now}) async {
    final dateKey = state.selectedDateKey;
    if (state.phase != AppPhase.journal || dateKey == null) return;
    if (!await saveCurrentEntry()) return;
    final entry = DayEntry.empty(
      dateKey: dateKey,
      type: DayEntryType.additional,
      purpose: EntryPurpose.quietTime,
      now: now,
    ).copyWith(title: 'Quiet Time');
    state = state.copyWith(
      entries: [
        state.dailyEntry!,
        entry,
        ...state.entries.where((e) => e.type == DayEntryType.additional),
      ],
      selectedEntryId: entry.id,
      clearError: true,
    );
  }

  void updateEntry({String? title, String? content, DateTime? now}) {
    final selected = state.selectedEntry;
    if (state.phase != AppPhase.journal || selected == null) return;
    final updated = selected.copyWith(
      title: title,
      content: content,
      updatedAt: (now ?? DateTime.now()).toUtc(),
    );
    state = state.copyWith(
      entries: [
        for (final entry in state.entries)
          if (entry.id == updated.id) updated else entry,
      ],
      clearError: true,
    );
  }

  void updateGratitude(String gratitude, {DateTime? now}) {
    if (state.phase != AppPhase.journal || state.day == null) return;
    state = state.copyWith(
      day: state.day!.copyWith(
        gratitude: gratitude,
        updatedAt: (now ?? DateTime.now()).toUtc(),
      ),
      clearError: true,
    );
  }

  Future<bool> saveCurrentEntry() async {
    final entry = state.selectedEntry;
    if (entry == null) return true;
    try {
      if (entry.type == DayEntryType.additional && entry.isEmpty) {
        await _database.deleteDayEntry(entry.id);
        state = state.copyWith(
          entries: state.entries.where((item) => item.id != entry.id).toList(),
          selectedEntryId: state.dailyEntry?.id,
        );
      } else {
        await _database.saveDayEntry(entry);
      }
      return true;
    } catch (error) {
      state = state.copyWith(error: error);
      return false;
    }
  }

  Future<bool> saveGratitude() async {
    final day = state.day;
    if (day == null) return true;
    try {
      await _database.saveDay(day);
      return true;
    } catch (error) {
      state = state.copyWith(error: error);
      return false;
    }
  }

  Future<void> finishEditing({DateTime? now}) async {
    if (!await saveCurrentEntry()) return;
    if (!await saveGratitude()) return;
    final timestamp = now ?? DateTime.now();
    final todayKey = localDateKey(timestamp);
    if (state.selectedDateKey == todayKey &&
        state.eveningPreference.isEvening(timestamp) &&
        state.checkIn == null) {
      await openMood(todayKey);
    } else {
      state = state.copyWith(
        phase: AppPhase.binder,
        showMoodReminder:
            state.selectedDateKey == todayKey && state.checkIn == null,
      );
    }
  }

  Future<void> openMood(
    String dateKey, {
    DateTime? now,
    bool continueToJournal = false,
  }) async {
    if (!await saveCurrentEntry()) return;
    if (!await saveGratitude()) return;
    _continueToJournalAfterMood = continueToJournal;
    final binderDay = await _database.loadBinderDay(dateKey, create: true);
    state = state.copyWith(
      phase: AppPhase.mood,
      selectedDateKey: dateKey,
      day: binderDay.day,
      entries: binderDay.entries,
      checkIn: binderDay.checkIn,
      clearCheckIn: binderDay.checkIn == null,
      showMoodReminder: false,
      clearError: true,
    );
  }

  void updateMood(double angle, double intensity, {DateTime? now}) {
    final dateKey = state.selectedDateKey;
    if (state.phase != AppPhase.mood || dateKey == null) return;
    final timestamp = now ?? DateTime.now();
    final checkIn = state.checkIn == null
        ? DailyCheckIn.forDate(
            dateKey: dateKey,
            moodAngle: angle,
            moodIntensity: intensity,
            now: timestamp,
          )
        : state.checkIn!.copyWith(
            moodAngle: angle,
            moodIntensity: intensity,
            updatedAt: timestamp.toUtc(),
          );
    state = state.copyWith(checkIn: checkIn, clearError: true);
  }

  Future<bool> saveMood() async {
    final checkIn = state.checkIn;
    if (checkIn == null) return true;
    try {
      await _database.saveCheckIn(checkIn);
      return true;
    } catch (error) {
      state = state.copyWith(error: error);
      return false;
    }
  }

  Future<void> finishMood({DateTime? now}) async {
    if (!await saveMood()) return;
    final timestamp = now ?? DateTime.now();
    final dateKey = state.selectedDateKey ?? localDateKey(timestamp);
    final day = await _database.loadBinderDay(dateKey);
    if (_continueToJournalAfterMood && !day.journalComplete) {
      _continueToJournalAfterMood = false;
      await openDay(dateKey, now: timestamp);
    } else {
      _continueToJournalAfterMood = false;
      state = state.copyWith(phase: AppPhase.binder, showMoodReminder: false);
    }
  }

  Future<void> openBinder() async {
    if (!await saveCurrentEntry()) return;
    if (!await saveGratitude()) return;
    if (!await saveMood()) return;
    state = state.copyWith(phase: AppPhase.binder);
  }

  Future<void> updateEveningPreference(int minutes) async {
    final preference = EveningPreference(
      minutesAfterMidnight: minutes.clamp(0, 1439),
    );
    state = state.copyWith(eveningPreference: preference);
    await _database.saveEveningPreference(preference);
  }

  Future<void> setSmartOrganizationEnabled(bool enabled) async {
    await _database.saveSetting(
      DatabaseService.smartOrganizationSettingKey,
      '$enabled',
    );
    state = state.copyWith(smartOrganizationEnabled: enabled);
  }

  Future<void> setQuietTimeLoggingEnabled(bool enabled) async {
    await _database.saveSetting(
      DatabaseService.quietTimeLoggingSettingKey,
      '$enabled',
    );
    state = state.copyWith(quietTimeLoggingEnabled: enabled);
  }

  Future<void> setPreferredBibleId(String bibleId) async {
    await _database.saveSetting(
      DatabaseService.preferredBibleSettingKey,
      bibleId,
    );
    state = state.copyWith(preferredBibleId: bibleId);
  }
}

final journalControllerProvider =
    StateNotifierProvider<JournalController, JournalAppState>(
      (ref) => JournalController(ref.watch(databaseServiceProvider)),
    );
