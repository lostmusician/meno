import 'package:uuid/uuid.dart';

const _uuid = Uuid();

enum AppPhase { loading, mood, journal, binder }

enum BinderZoom { days, weeks, months }

enum DayEntryType { daily, additional }

enum EntryPurpose { freeform, quietTime }

enum EntryTagSource { manual, generated }

class EveningPreference {
  const EveningPreference({this.minutesAfterMidnight = 18 * 60});

  final int minutesAfterMidnight;
  int get hour => minutesAfterMidnight ~/ 60;
  int get minute => minutesAfterMidnight % 60;

  bool isEvening(DateTime localTime) =>
      localTime.hour * 60 + localTime.minute >= minutesAfterMidnight;
}

class DailyCheckIn {
  const DailyCheckIn({
    required this.dateKey,
    required this.moodAngle,
    required this.moodIntensity,
    required this.createdAt,
    required this.updatedAt,
  });

  factory DailyCheckIn.forDate({
    required String dateKey,
    required double moodAngle,
    required double moodIntensity,
    DateTime? now,
  }) {
    final timestamp = (now ?? DateTime.now()).toUtc();
    return DailyCheckIn(
      dateKey: dateKey,
      moodAngle: moodAngle.clamp(0, 1),
      moodIntensity: moodIntensity.clamp(0, 1),
      createdAt: timestamp,
      updatedAt: timestamp,
    );
  }

  factory DailyCheckIn.fromMap(Map<String, Object?> map) => DailyCheckIn(
    dateKey: map['date_key']! as String,
    moodAngle: (map['mood_angle']! as num).toDouble(),
    moodIntensity: (map['mood_intensity']! as num).toDouble(),
    createdAt: DateTime.parse(map['created_at']! as String),
    updatedAt: DateTime.parse(map['updated_at']! as String),
  );

  final String dateKey;
  final double moodAngle;
  final double moodIntensity;
  final DateTime createdAt;
  final DateTime updatedAt;

  DailyCheckIn copyWith({
    double? moodAngle,
    double? moodIntensity,
    DateTime? updatedAt,
  }) => DailyCheckIn(
    dateKey: dateKey,
    moodAngle: (moodAngle ?? this.moodAngle).clamp(0, 1),
    moodIntensity: (moodIntensity ?? this.moodIntensity).clamp(0, 1),
    createdAt: createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
  );

  Map<String, Object?> toMap() => {
    'date_key': dateKey,
    'mood_angle': moodAngle,
    'mood_intensity': moodIntensity,
    'created_at': createdAt.toIso8601String(),
    'updated_at': updatedAt.toIso8601String(),
  };
}

class JournalDay {
  const JournalDay({
    required this.dateKey,
    required this.gratitude,
    required this.createdAt,
    required this.updatedAt,
  });

  factory JournalDay.empty(String dateKey, {DateTime? now}) {
    final timestamp = (now ?? DateTime.now()).toUtc();
    return JournalDay(
      dateKey: dateKey,
      gratitude: '',
      createdAt: timestamp,
      updatedAt: timestamp,
    );
  }

  factory JournalDay.fromMap(Map<String, Object?> map) => JournalDay(
    dateKey: map['date_key']! as String,
    gratitude: (map['gratitude'] as String?) ?? '',
    createdAt: DateTime.parse(map['created_at']! as String),
    updatedAt: DateTime.parse(map['updated_at']! as String),
  );

  final String dateKey;
  final String gratitude;
  final DateTime createdAt;
  final DateTime updatedAt;

  JournalDay copyWith({String? gratitude, DateTime? updatedAt}) => JournalDay(
    dateKey: dateKey,
    gratitude: gratitude ?? this.gratitude,
    createdAt: createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
  );

  Map<String, Object?> toMap() => {
    'date_key': dateKey,
    'gratitude': gratitude,
    'created_at': createdAt.toIso8601String(),
    'updated_at': updatedAt.toIso8601String(),
  };
}

class DayEntry {
  const DayEntry({
    required this.id,
    required this.dateKey,
    required this.type,
    this.purpose = EntryPurpose.freeform,
    required this.title,
    required this.content,
    required this.createdAt,
    required this.updatedAt,
  });

  factory DayEntry.empty({
    required String dateKey,
    required DayEntryType type,
    EntryPurpose purpose = EntryPurpose.freeform,
    DateTime? now,
  }) {
    final timestamp = (now ?? DateTime.now()).toUtc();
    return DayEntry(
      id: _uuid.v4(),
      dateKey: dateKey,
      type: type,
      purpose: purpose,
      title: '',
      content: '',
      createdAt: timestamp,
      updatedAt: timestamp,
    );
  }

  factory DayEntry.fromMap(Map<String, Object?> map) => DayEntry(
    id: map['id']! as String,
    dateKey: map['date_key']! as String,
    type: DayEntryType.values.byName(map['entry_type']! as String),
    purpose: EntryPurpose.values.byName(
      (map['entry_purpose'] as String?) ?? EntryPurpose.freeform.name,
    ),
    title: (map['title'] as String?) ?? '',
    content: (map['content'] as String?) ?? '',
    createdAt: DateTime.parse(map['created_at']! as String),
    updatedAt: DateTime.parse(map['updated_at']! as String),
  );

  final String id;
  final String dateKey;
  final DayEntryType type;
  final EntryPurpose purpose;
  final String title;
  final String content;
  final DateTime createdAt;
  final DateTime updatedAt;

  bool get isEmpty => title.trim().isEmpty && content.trim().isEmpty;
  int get wordCount {
    final value = content.trim();
    return value.isEmpty ? 0 : value.split(RegExp(r'\s+')).length;
  }

  DayEntry copyWith({
    String? title,
    String? content,
    EntryPurpose? purpose,
    DateTime? updatedAt,
  }) => DayEntry(
    id: id,
    dateKey: dateKey,
    type: type,
    purpose: purpose ?? this.purpose,
    title: title ?? this.title,
    content: content ?? this.content,
    createdAt: createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
  );

  Map<String, Object?> toMap() => {
    'id': id,
    'date_key': dateKey,
    'entry_type': type.name,
    'entry_purpose': purpose.name,
    'title': title,
    'content': content,
    'created_at': createdAt.toIso8601String(),
    'updated_at': updatedAt.toIso8601String(),
  };
}

class JournalTag {
  const JournalTag({
    required this.id,
    required this.name,
    required this.normalizedName,
    required this.createdAt,
    required this.updatedAt,
  });

  factory JournalTag.create(String name, {DateTime? now}) {
    final timestamp = (now ?? DateTime.now()).toUtc();
    return JournalTag(
      id: _uuid.v4(),
      name: name.trim(),
      normalizedName: normalizeTagName(name),
      createdAt: timestamp,
      updatedAt: timestamp,
    );
  }

  factory JournalTag.fromMap(Map<String, Object?> map) => JournalTag(
    id: map['id']! as String,
    name: map['name']! as String,
    normalizedName: map['normalized_name']! as String,
    createdAt: DateTime.parse(map['created_at']! as String),
    updatedAt: DateTime.parse(map['updated_at']! as String),
  );

  final String id;
  final String name;
  final String normalizedName;
  final DateTime createdAt;
  final DateTime updatedAt;

  JournalTag copyWith({
    String? name,
    String? normalizedName,
    DateTime? updatedAt,
  }) => JournalTag(
    id: id,
    name: name ?? this.name,
    normalizedName: normalizedName ?? this.normalizedName,
    createdAt: createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
  );

  Map<String, Object?> toMap() => {
    'id': id,
    'name': name,
    'normalized_name': normalizedName,
    'created_at': createdAt.toIso8601String(),
    'updated_at': updatedAt.toIso8601String(),
  };
}

class EntryTag {
  const EntryTag({
    required this.entryId,
    required this.tag,
    required this.source,
    this.confidence,
  });

  final String entryId;
  final JournalTag tag;
  final EntryTagSource source;
  final double? confidence;
}

class EntryRelationship {
  const EntryRelationship({
    required this.sourceEntryId,
    required this.targetEntryId,
    required this.score,
    required this.reasons,
  });

  final String sourceEntryId;
  final String targetEntryId;
  final double score;
  final List<String> reasons;
}

class ScriptureReference {
  const ScriptureReference({
    required this.id,
    required this.entryId,
    required this.bibleId,
    required this.translationAbbreviation,
    required this.passageId,
    required this.reference,
    required this.copyright,
  });

  factory ScriptureReference.fromMap(Map<String, Object?> map) =>
      ScriptureReference(
        id: map['id']! as String,
        entryId: map['entry_id']! as String,
        bibleId: map['bible_id']! as String,
        translationAbbreviation: map['translation_abbreviation']! as String,
        passageId: map['passage_id']! as String,
        reference: map['reference']! as String,
        copyright: (map['copyright'] as String?) ?? '',
      );

  final String id;
  final String entryId;
  final String bibleId;
  final String translationAbbreviation;
  final String passageId;
  final String reference;
  final String copyright;
}

class BibleVersion {
  const BibleVersion({
    required this.id,
    required this.abbreviation,
    required this.title,
    required this.copyright,
  });

  final String id;
  final String abbreviation;
  final String title;
  final String copyright;
}

class BiblePassage {
  const BiblePassage({
    required this.id,
    required this.reference,
    required this.content,
    required this.version,
  });

  final String id;
  final String reference;
  final String content;
  final BibleVersion version;
}

class QuietTimeReflection {
  const QuietTimeReflection({
    required this.entryId,
    this.observation = '',
    this.application = '',
    this.prayer = '',
  });

  factory QuietTimeReflection.fromMap(Map<String, Object?> map) =>
      QuietTimeReflection(
        entryId: map['entry_id']! as String,
        observation: (map['observation'] as String?) ?? '',
        application: (map['application'] as String?) ?? '',
        prayer: (map['prayer'] as String?) ?? '',
      );

  final String entryId;
  final String observation;
  final String application;
  final String prayer;

  QuietTimeReflection copyWith({
    String? observation,
    String? application,
    String? prayer,
  }) => QuietTimeReflection(
    entryId: entryId,
    observation: observation ?? this.observation,
    application: application ?? this.application,
    prayer: prayer ?? this.prayer,
  );
}

class JournalSearchQuery {
  const JournalSearchQuery({
    this.text = '',
    this.tagIds = const [],
    this.purpose,
    this.scriptureBook,
    this.fromDateKey,
    this.toDateKey,
  });

  final String text;
  final List<String> tagIds;
  final EntryPurpose? purpose;
  final String? scriptureBook;
  final String? fromDateKey;
  final String? toDateKey;
}

class JournalSearchResult {
  const JournalSearchResult({required this.entry, required this.tags});
  final DayEntry entry;
  final List<EntryTag> tags;
}

String normalizeTagName(String value) => value
    .trim()
    .toLowerCase()
    .replaceAll(RegExp(r'[^a-z0-9\s-]'), '')
    .replaceAll(RegExp(r'\s+'), ' ');

class BinderDay {
  const BinderDay({
    required this.day,
    required this.entries,
    required this.checkIn,
  });

  final JournalDay day;
  final List<DayEntry> entries;
  final DailyCheckIn? checkIn;

  DayEntry? get dailyEntry =>
      entries.where((entry) => entry.type == DayEntryType.daily).firstOrNull;
  List<DayEntry> get additionalEntries =>
      entries.where((entry) => entry.type == DayEntryType.additional).toList();
  bool get journalComplete => dailyEntry?.content.trim().isNotEmpty ?? false;
  bool get isComplete => journalComplete && checkIn != null;
}

class BinderCursor {
  const BinderCursor(this.dateKey);
  final String dateKey;
}

String localDateKey(DateTime date) {
  final local = date.toLocal();
  return '${local.year.toString().padLeft(4, '0')}-'
      '${local.month.toString().padLeft(2, '0')}-'
      '${local.day.toString().padLeft(2, '0')}';
}

DateTime localDateFromKey(String dateKey) {
  final parts = dateKey.split('-').map(int.parse).toList();
  return DateTime(parts[0], parts[1], parts[2]);
}
