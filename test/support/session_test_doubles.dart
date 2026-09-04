import 'package:meno/models/journal_entry.dart';
import 'package:meno/services/database_service.dart';

class FakeDatabaseService extends DatabaseService {
  final Map<String, JournalDay> days = {};
  final Map<String, DayEntry> entries = {};
  final Map<String, DailyCheckIn> checkIns = {};
  final Map<String, JournalTag> tags = {};
  final Map<String, List<EntryTag>> entryTags = {};
  final Map<String, List<EntryRelationship>> relationships = {};
  final Map<String, List<ScriptureReference>> scriptures = {};
  final Map<String, QuietTimeReflection> quietTimes = {};
  EveningPreference preference = const EveningPreference();
  final Map<String, String> settings = {
    DatabaseService.smartOrganizationSettingKey: 'false',
    DatabaseService.quietTimeLoggingSettingKey: 'false',
    DatabaseService.preferredBibleSettingKey: 'NIV',
  };
  bool failEntrySaves = false;
  int saveDayEntryCallCount = 0;

  @override
  Future<JournalDay> ensureDay(String dateKey, {DateTime? now}) async =>
      days.putIfAbsent(dateKey, () => JournalDay.empty(dateKey, now: now));

  @override
  Future<JournalDay?> journalDay(String dateKey) async => days[dateKey];

  @override
  Future<void> saveDay(JournalDay day) async {
    days[day.dateKey] = day;
  }

  @override
  Future<List<DayEntry>> entriesForDay(String dateKey) async {
    final values =
        entries.values.where((entry) => entry.dateKey == dateKey).toList()
          ..sort((a, b) {
            if (a.type != b.type) return a.type == DayEntryType.daily ? -1 : 1;
            return b.createdAt.compareTo(a.createdAt);
          });
    return values;
  }

  @override
  Future<void> saveDayEntry(DayEntry entry) async {
    saveDayEntryCallCount += 1;
    if (failEntrySaves) throw StateError('entry save failed');
    await ensureDay(entry.dateKey, now: entry.createdAt);
    if (entry.type == DayEntryType.daily &&
        entries.values.any(
          (existing) =>
              existing.id != entry.id &&
              existing.dateKey == entry.dateKey &&
              existing.type == DayEntryType.daily,
        )) {
      throw StateError('daily entry already exists');
    }
    entries[entry.id] = entry;
  }

  @override
  Future<void> deleteDayEntry(String id) async {
    entries.remove(id);
  }

  @override
  Future<DailyCheckIn?> checkInForDate(String dateKey) async =>
      checkIns[dateKey];

  @override
  Future<void> saveCheckIn(DailyCheckIn checkIn) async {
    await ensureDay(checkIn.dateKey, now: checkIn.createdAt);
    checkIns[checkIn.dateKey] = checkIn;
  }

  @override
  Future<BinderDay> loadBinderDay(String dateKey, {bool create = false}) async {
    final day = create
        ? await ensureDay(dateKey)
        : days[dateKey] ?? JournalDay.empty(dateKey);
    return BinderDay(
      day: day,
      entries: await entriesForDay(dateKey),
      checkIn: checkIns[dateKey],
    );
  }

  @override
  Future<List<BinderDay>> binderPage({
    BinderCursor? cursor,
    int limit = 20,
  }) async {
    final keys = days.keys.where((key) {
      if (cursor != null && key.compareTo(cursor.dateKey) >= 0) return false;
      final day = days[key]!;
      final hasEntry = entries.values.any(
        (entry) => entry.dateKey == key && !entry.isEmpty,
      );
      return day.gratitude.trim().isNotEmpty ||
          hasEntry ||
          checkIns.containsKey(key);
    }).toList()..sort((a, b) => b.compareTo(a));
    return Future.wait(keys.take(limit).map(loadBinderDay));
  }

  @override
  Future<EveningPreference> eveningPreference() async => preference;

  @override
  Future<void> saveEveningPreference(EveningPreference value) async {
    preference = value;
  }

  @override
  Future<String?> setting(String key) async => settings[key];

  @override
  Future<void> saveSetting(String key, String value) async {
    settings[key] = value;
  }

  @override
  Future<List<JournalTag>> allTags() async => tags.values.toList();

  @override
  Future<Map<String, int>> tagUsageCounts() async => {
    for (final tag in tags.values)
      tag.normalizedName: entryTags.values
          .expand((values) => values)
          .where((value) => value.tag.id == tag.id)
          .length,
  };

  @override
  Future<List<SharedTagCandidate>> sharedTagCandidates(String entryId) async {
    final sourceIds = (entryTags[entryId] ?? const [])
        .map((value) => value.tag.id)
        .toSet();
    return [
      for (final candidate in entryTags.entries)
        if (candidate.key != entryId)
          for (final value in candidate.value)
            if (sourceIds.contains(value.tag.id))
              (entryId: candidate.key, tagName: value.tag.name),
    ];
  }

  @override
  Future<List<SharedScriptureCandidate>> sharedScriptureCandidates(
    String entryId,
  ) async {
    final source = scriptures[entryId] ?? const [];
    return [
      for (final candidate in scriptures.entries)
        if (candidate.key != entryId)
          for (final value in candidate.value)
            for (final sourceValue in source)
              if (value.bibleId == sourceValue.bibleId &&
                  value.passageId == sourceValue.passageId)
                (entryId: candidate.key, reference: sourceValue.reference),
    ];
  }

  @override
  Future<List<EntryTag>> tagsForEntry(String entryId) async =>
      entryTags[entryId] ?? const [];

  @override
  Future<JournalTag> ensureTag(String name, {DateTime? now}) async {
    final normalized = normalizeTagName(name);
    return tags.values.firstWhere(
      (tag) => tag.normalizedName == normalized,
      orElse: () {
        final tag = JournalTag.create(name, now: now);
        tags[tag.id] = tag;
        return tag;
      },
    );
  }

  @override
  Future<void> attachTag({
    required String entryId,
    required JournalTag tag,
    required EntryTagSource source,
    double? confidence,
  }) async {
    final values = entryTags.putIfAbsent(entryId, () => []);
    values.removeWhere((value) => value.tag.id == tag.id);
    values.add(
      EntryTag(
        entryId: entryId,
        tag: tag,
        source: source,
        confidence: confidence,
      ),
    );
  }

  @override
  Future<void> detachTag(String entryId, String tagId) async {
    entryTags[entryId]?.removeWhere((value) => value.tag.id == tagId);
  }

  @override
  Future<List<EntryRelationship>> relationshipsForEntry(
    String entryId, {
    int limit = 8,
  }) async => (relationships[entryId] ?? const []).take(limit).toList();

  @override
  Future<List<ScriptureReference>> scripturesForEntry(String entryId) async =>
      scriptures[entryId] ?? const [];

  @override
  Future<void> saveScripture(ScriptureReference reference) async {
    final values = scriptures.putIfAbsent(reference.entryId, () => []);
    values.removeWhere((value) => value.id == reference.id);
    values.add(reference);
  }

  @override
  Future<QuietTimeReflection?> quietTimeForEntry(String entryId) async =>
      quietTimes[entryId];

  @override
  Future<void> saveQuietTime(QuietTimeReflection reflection) async {
    quietTimes[reflection.entryId] = reflection;
  }

  @override
  Future<List<JournalSearchResult>> searchEntries(
    JournalSearchQuery query, {
    int limit = 50,
  }) async {
    final needle = query.text.toLowerCase();
    return entries.values
        .where((entry) => !entry.isEmpty)
        .where(
          (entry) =>
              needle.isEmpty ||
              entry.title.toLowerCase().contains(needle) ||
              entry.content.toLowerCase().contains(needle),
        )
        .where(
          (entry) => query.purpose == null || entry.purpose == query.purpose,
        )
        .where((entry) {
          final ids = (entryTags[entry.id] ?? const [])
              .map((value) => value.tag.id)
              .toSet();
          return query.tagIds.every(ids.contains);
        })
        .take(limit)
        .map(
          (entry) => JournalSearchResult(
            entry: entry,
            tags: entryTags[entry.id] ?? const [],
          ),
        )
        .toList();
  }

  @override
  Future<void> close() async {}
}
