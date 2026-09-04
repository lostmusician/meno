import 'package:flutter_test/flutter_test.dart';
import 'package:meno/models/journal_entry.dart';
import 'package:meno/services/database_service.dart';
import 'package:meno/services/embedding_service.dart';
import 'package:meno/services/keyphrase_service.dart';
import 'package:meno/services/organization_service.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  setUpAll(sqfliteFfiInit);

  group('schema version 4', () {
    late DatabaseService database;
    setUp(() {
      database = DatabaseService(
        factory: databaseFactoryFfi,
        databasePath: inMemoryDatabasePath,
      );
    });
    tearDown(() => database.close());

    test('keeps manual tags while replacing generated tags', () async {
      final entry = _entry('one', 'Prayer walk by the river');
      await database.saveDayEntry(entry);
      final manual = await database.ensureTag('Prayer');
      await database.attachTag(
        entryId: entry.id,
        tag: manual,
        source: EntryTagSource.manual,
      );

      await database.replaceGeneratedTags(entry.id, const [
        ('prayer', .9),
        ('river walk', .8),
      ]);
      await database.replaceGeneratedTags(entry.id, const [
        ('quiet water', .7),
      ]);

      final tags = await database.tagsForEntry(entry.id);
      expect(
        tags.where((tag) => tag.tag.normalizedName == 'prayer').single.source,
        EntryTagSource.manual,
      );
      expect(
        tags.map((tag) => tag.tag.normalizedName),
        containsAll(<String>['prayer', 'quiet water']),
      );
      expect(
        tags.map((tag) => tag.tag.normalizedName),
        isNot(contains('river walk')),
      );

      final renamed = await database.renameTag(manual.id, 'Prayer life');
      final quiet = (await database.allTags()).firstWhere(
        (tag) => tag.normalizedName == 'quiet water',
      );
      await database.mergeTags(quiet.id, renamed.id);
      final merged = await database.tagsForEntry(entry.id);
      expect(merged, hasLength(1));
      expect(merged.single.tag.name, 'Prayer life');
      expect(merged.single.source, EntryTagSource.manual);
    });

    test(
      'indexes text, tags, quiet time, dates, and Scripture books',
      () async {
        final entry = _entry(
          'quiet',
          'I found patient hope.',
          purpose: EntryPurpose.quietTime,
        );
        await database.saveDay(
          JournalDay.empty(entry.dateKey).copyWith(gratitude: 'Morning light'),
        );
        await database.saveDayEntry(entry);
        final tag = await database.ensureTag('Patience');
        await database.attachTag(
          entryId: entry.id,
          tag: tag,
          source: EntryTagSource.manual,
        );
        await database.saveQuietTime(
          QuietTimeReflection(
            entryId: entry.id,
            observation: 'Love is patient.',
            application: 'Listen before answering.',
            prayer: 'Help me be gentle.',
          ),
        );
        await database.saveScripture(
          ScriptureReference(
            id: 'verse',
            entryId: entry.id,
            bibleId: 'BSB',
            translationAbbreviation: 'BSB',
            passageId: 'JHN.3.16',
            reference: 'John 3:16',
            copyright: 'Public domain',
          ),
        );

        expect(
          (await database.searchEntries(
            const JournalSearchQuery(text: 'gentle'),
          )).single.entry.id,
          entry.id,
        );
        expect(
          await database.searchEntries(
            JournalSearchQuery(
              tagIds: [tag.id],
              purpose: EntryPurpose.quietTime,
              scriptureBook: 'JHN',
              fromDateKey: entry.dateKey,
              toDateKey: entry.dateKey,
            ),
          ),
          hasLength(1),
        );
      },
    );

    test('stores embeddings and caps relationships at eight', () async {
      final source = _entry('source', 'source');
      await database.saveDayEntry(source);
      for (var index = 0; index < 10; index++) {
        await database.saveDayEntry(_entry('target-$index', 'target $index'));
      }
      await database.saveEmbedding(
        entryId: source.id,
        modelId: 'fixture-v1',
        contentHash: 'hash',
        vector: const [.25, .5, .75],
      );
      await database.saveRelationships(source.id, [
        for (var index = 0; index < 10; index++)
          EntryRelationship(
            sourceEntryId: source.id,
            targetEntryId: 'target-$index',
            score: index / 10,
            reasons: const ['fixture'],
          ),
      ]);

      final embedding = await database.embeddingForEntry(
        source.id,
        'fixture-v1',
      );
      expect(embedding?.contentHash, 'hash');
      expect(embedding?.vector, closeToList(const [.25, .5, .75]));
      expect(await database.relationshipsForEntry(source.id), hasLength(8));
    });
  });

  group('organization services', () {
    test('RAKE filters generic journal language and limits labels', () async {
      final results = await const RakeKeyphraseExtractor().extract(
        title: 'Community garden',
        content:
            'Today I felt good. The community garden brought neighbors together. '
            'Our community garden needs patient planning.',
        gratitude: 'Helpful neighbors',
        corpusFrequency: const {'community garden': 1},
        corpusSize: 20,
      );
      expect(results, isNotEmpty);
      expect(results.length, lessThanOrEqualTo(5));
      expect(
        results.map((result) => result.phrase.toLowerCase()),
        isNot(contains('today')),
      );
      expect(results.first.score, inInclusiveRange(0, 1));
    });

    test(
      'semantic relationships cache deterministic normalized vectors',
      () async {
        final database = DatabaseService(
          factory: databaseFactoryFfi,
          databasePath: inMemoryDatabasePath,
        );
        addTearDown(database.close);
        final source = _entry('a', 'church community and prayer');
        final similar = _entry('b', 'prayer with my community');
        final unrelated = _entry('c', 'debugging a compiler');
        for (final entry in [source, similar, unrelated]) {
          await database.saveDayEntry(entry);
        }
        final service = RelationshipService(
          database,
          _FixtureEmbeddingService(),
        );

        final relationships = await service.rebuildForEntry(source.id);

        expect(relationships.first.targetEntryId, similar.id);
        expect(relationships.first.reasons, contains('Similar theme'));
        expect(
          (await database.embeddingForEntry(
            source.id,
            'fixture-embedding',
          ))?.vector.length,
          6,
        );
      },
    );

    test('semantic canonicalization reuses a close existing tag', () async {
      final database = DatabaseService(
        factory: databaseFactoryFfi,
        databasePath: inMemoryDatabasePath,
      );
      addTearDown(database.close);
      final entry = _entry('one', 'A quiet prayer.');
      await database.saveDayEntry(entry);
      await database.ensureTag('Prayer');
      final service = TaggingService(
        database,
        const _FixtureExtractor(),
        _FixtureEmbeddingService(),
      );

      await service.organizeEntry(entry);

      expect((await database.tagsForEntry(entry.id)).single.tag.name, 'Prayer');
    });
  });
}

DayEntry _entry(
  String id,
  String content, {
  EntryPurpose purpose = EntryPurpose.freeform,
}) => DayEntry(
  id: id,
  dateKey: '2026-09-01',
  type: id == 'one' || id == 'quiet' || id == 'source' || id == 'legacy'
      ? DayEntryType.daily
      : DayEntryType.additional,
  purpose: purpose,
  title: '',
  content: content,
  createdAt: DateTime(2026, 9, 1).toUtc(),
  updatedAt: DateTime(2026, 9, 1).toUtc(),
);

Matcher closeToList(List<double> expected) => pairwiseCompare<double, double>(
  expected,
  (actual, value) => (actual - value).abs() < .0001,
  'approximately equal',
);

class _FixtureEmbeddingService implements EmbeddingService {
  @override
  String get modelId => 'fixture-embedding';

  @override
  int get dimensions => 3;

  @override
  Stream<EmbeddingStatus> get status => const Stream.empty();

  @override
  Future<bool> isAvailable() async => true;

  @override
  Future<void> downloadModel() async {}

  @override
  Future<List<double>> embed(String text, {bool isQuery = false}) async {
    final lower = text.toLowerCase();
    if (lower.contains('prayer') ||
        lower.contains('church') ||
        lower.contains('supplication')) {
      return const [1, 0, 0];
    }
    return const [0, 0, 1];
  }

  @override
  Future<void> deleteModel() async {}

  @override
  Future<void> close() async {}
}

class _FixtureExtractor implements KeyphraseExtractor {
  const _FixtureExtractor();

  @override
  Future<List<KeyphraseCandidate>> extract({
    required String content,
    String title = '',
    String gratitude = '',
    Map<String, int> corpusFrequency = const {},
    int corpusSize = 1,
    int limit = 5,
  }) async => const [KeyphraseCandidate('Supplication', .9)];
}
