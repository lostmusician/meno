import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:meno/models/journal_entry.dart';
import 'package:meno/providers/discovery_controller.dart';
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
        supportingText: const ['Helpful neighbors'],
      );
      expect(results, isNotEmpty);
      expect(results.length, lessThanOrEqualTo(12));
      expect(results.first.phrase.toLowerCase(), 'community garden');
      expect(
        results.map((result) => result.phrase.toLowerCase()),
        isNot(contains('today')),
      );
      expect(results.first.score, inInclusiveRange(0, 1));
    });

    test('semantic relevance outranks repeated incidental wording', () async {
      final database = DatabaseService(
        factory: databaseFactoryFfi,
        databasePath: inMemoryDatabasePath,
      );
      addTearDown(database.close);
      final entry = _entry(
        'topic',
        'The weekly meeting came up several times, but the meaningful part of '
            'the day was deciding to make a career transition.',
      );
      await database.saveDayEntry(entry);
      final service = TaggingService(
        database,
        const _CandidateExtractor([
          KeyphraseCandidate('weekly meeting', 1),
          KeyphraseCandidate('career transition', .65),
        ]),
        _VectorEmbeddingService(
          (text, isQuery) =>
              isQuery && text.toLowerCase().contains('weekly meeting')
              ? const [0, 1, 0]
              : const [1, 0, 0],
        ),
      );

      final tags = await service.organizeEntry(entry);

      expect(tags.first.tag.normalizedName, 'career transition');
      expect(
        tags.map((tag) => tag.tag.normalizedName),
        isNot(contains('weekly meeting')),
      );
    });

    test('uses authored supporting fields but excludes Scripture', () async {
      final database = DatabaseService(
        factory: databaseFactoryFfi,
        databasePath: inMemoryDatabasePath,
      );
      addTearDown(database.close);
      final entry = _entry(
        'authored-fields',
        'I want to respond with care.',
        purpose: EntryPurpose.quietTime,
        type: DayEntryType.daily,
      );
      await database.saveDay(
        JournalDay.empty(
          entry.dateKey,
        ).copyWith(gratitude: 'A thoughtful conversation'),
      );
      await database.saveDayEntry(entry);
      await database.saveQuietTime(
        QuietTimeReflection(
          entryId: entry.id,
          observation: 'Patient listening creates room for honesty.',
          application: 'Ask one gentle question.',
          prayer: 'Help me listen without rushing.',
        ),
      );
      await database.saveScripture(
        ScriptureReference(
          id: 'scripture',
          entryId: entry.id,
          bibleId: '111',
          translationAbbreviation: 'NIV',
          passageId: 'JHN.3.16',
          reference: 'John 3:16',
          copyright: 'Fixture attribution',
        ),
      );
      final extractor = _CapturingExtractor();
      final service = TaggingService(
        database,
        extractor,
        const _UnavailableEmbeddingService(),
      );

      await service.organizeEntry(entry);

      expect(
        extractor.supportingText,
        containsAll(<String>[
          'A thoughtful conversation',
          'Patient listening creates room for honesty.',
          'Ask one gentle question.',
          'Help me listen without rushing.',
        ]),
      );
      expect(extractor.supportingText.join(' '), isNot(contains('John 3:16')));
      expect(
        (await database.tagsForEntry(entry.id)).single.tag.normalizedName,
        'patient listening',
      );
    });

    test('semantic selection is diverse and limited to three tags', () async {
      final database = DatabaseService(
        factory: databaseFactoryFfi,
        databasePath: inMemoryDatabasePath,
      );
      addTearDown(database.close);
      final entry = _entry(
        'diverse',
        'The community garden grew through helpful neighbors and patient '
            'planning rather than morning coffee.',
      );
      await database.saveDayEntry(entry);
      final service = TaggingService(
        database,
        const _CandidateExtractor([
          KeyphraseCandidate('community garden', .95),
          KeyphraseCandidate('garden', .90),
          KeyphraseCandidate('helpful neighbors', .85),
          KeyphraseCandidate('patient planning', .80),
          KeyphraseCandidate('morning coffee', .95),
        ]),
        _VectorEmbeddingService((text, isQuery) {
          final lower = text.toLowerCase();
          if (!isQuery) return const [1, 0, 0];
          if (lower.contains('community garden') || lower == 'garden') {
            return const [1, 0, 0];
          }
          if (lower.contains('helpful neighbors')) return const [.8, .6, 0];
          if (lower.contains('patient planning')) return const [.8, 0, .6];
          return const [0, 1, 0];
        }),
      );

      final tags = await service.organizeEntry(entry);
      final names = tags.map((tag) => tag.tag.normalizedName).toList();

      expect(names, hasLength(3));
      expect(
        names,
        containsAll(<String>[
          'community garden',
          'helpful neighbors',
          'patient planning',
        ]),
      );
      expect(names, isNot(contains('garden')));
      expect(names, isNot(contains('morning coffee')));
    });

    test('corpus rarity breaks otherwise equal semantic scores', () async {
      final database = DatabaseService(
        factory: databaseFactoryFfi,
        databasePath: inMemoryDatabasePath,
      );
      addTearDown(database.close);
      for (var index = 0; index < 4; index++) {
        await database.saveDayEntry(
          _entry('common-$index', 'Another weekly meeting was recorded.'),
        );
      }
      final entry = _entry(
        'rarity',
        'The weekly meeting helped me discover creative courage.',
      );
      await database.saveDayEntry(entry);
      final service = TaggingService(
        database,
        const _CandidateExtractor([
          KeyphraseCandidate('weekly meeting', .8),
          KeyphraseCandidate('creative courage', .8),
        ]),
        _VectorEmbeddingService((text, isQuery) {
          if (!isQuery) return const [1, 0, 0];
          return text.toLowerCase().contains('weekly meeting')
              ? const [.8, .6, 0]
              : const [.8, -.6, 0];
        }),
      );

      final tags = await service.organizeEntry(entry);

      expect(tags.first.tag.normalizedName, 'creative courage');
      expect(tags.first.confidence, greaterThan(tags.last.confidence!));
    });

    test('fallback emits only defensible extractive tags', () async {
      final database = DatabaseService(
        factory: databaseFactoryFfi,
        databasePath: inMemoryDatabasePath,
      );
      addTearDown(database.close);
      final entry = _entry(
        'fallback',
        'A meeting led to careful project planning and a weak phrase.',
        title: 'Purpose',
      );
      await database.saveDayEntry(entry);
      final service = TaggingService(
        database,
        const _CandidateExtractor([
          KeyphraseCandidate('meeting', 1),
          KeyphraseCandidate('project planning', .65),
          KeyphraseCandidate('weak phrase', .50),
          KeyphraseCandidate('Purpose', .70),
        ]),
        const _UnavailableEmbeddingService(),
      );

      final tags = await service.organizeEntry(entry);
      final names = tags.map((tag) => tag.tag.normalizedName);

      expect(names, containsAll(<String>['purpose', 'project planning']));
      expect(names, isNot(contains('meeting')));
      expect(names, isNot(contains('weak phrase')));
      expect(tags.length, lessThanOrEqualTo(3));
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

    test('weak semantic matches do not replace extractive labels', () async {
      final database = DatabaseService(
        factory: databaseFactoryFfi,
        databasePath: inMemoryDatabasePath,
      );
      addTearDown(database.close);
      final entry = _entry(
        'weak-reuse',
        'I am considering a career transition.',
      );
      await database.saveDayEntry(entry);
      await database.ensureTag('Gardening');
      final service = TaggingService(
        database,
        const _CandidateExtractor([
          KeyphraseCandidate('career transition', .9),
        ]),
        _VectorEmbeddingService((text, isQuery) {
          if (text.toLowerCase() == 'gardening') return const [0, 1, 0];
          return const [1, 0, 0];
        }),
      );

      final tags = await service.organizeEntry(entry);

      expect(tags.single.tag.normalizedName, 'career transition');
    });

    test(
      'organization is serialized and stale results do not commit',
      () async {
        final database = DatabaseService(
          factory: databaseFactoryFfi,
          databasePath: inMemoryDatabasePath,
        );
        addTearDown(database.close);
        final embedding = _BlockingEmbeddingService();
        final tagging = TaggingService(
          database,
          const _ContentExtractor(),
          embedding,
        );
        final controller = DiscoveryController(
          database,
          tagging,
          RelationshipService(database, embedding),
        );
        addTearDown(controller.dispose);
        final oldEntry = _entry('latest', 'old topic');
        await database.saveDayEntry(oldEntry);

        final oldRun = controller.organizeEntry(oldEntry);
        await embedding.started.future;
        final newEntry = _entry('latest', 'new topic');
        await database.saveDayEntry(newEntry);
        final newRun = controller.organizeEntry(newEntry);
        embedding.release();
        await Future.wait([oldRun, newRun]);

        final tags = await database.tagsForEntry(newEntry.id);
        expect(tags.map((tag) => tag.tag.normalizedName), ['new topic']);
        expect(embedding.maximumConcurrentCalls, 1);
      },
    );
  });
}

DayEntry _entry(
  String id,
  String content, {
  EntryPurpose purpose = EntryPurpose.freeform,
  String title = '',
  String dateKey = '2026-09-01',
  DayEntryType? type,
}) => DayEntry(
  id: id,
  dateKey: dateKey,
  type:
      type ??
      (id == 'one' || id == 'quiet' || id == 'source' || id == 'legacy'
          ? DayEntryType.daily
          : DayEntryType.additional),
  purpose: purpose,
  title: title,
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

class _VectorEmbeddingService implements EmbeddingService {
  _VectorEmbeddingService(this.vectorFor);

  final List<double> Function(String text, bool isQuery) vectorFor;

  @override
  int get dimensions => 3;

  @override
  String get modelId => 'vector-fixture';

  @override
  Stream<EmbeddingStatus> get status => const Stream.empty();

  @override
  Future<void> close() async {}

  @override
  Future<void> deleteModel() async {}

  @override
  Future<void> downloadModel() async {}

  @override
  Future<List<double>> embed(String text, {bool isQuery = false}) async =>
      vectorFor(text, isQuery);

  @override
  Future<bool> isAvailable() async => true;
}

class _UnavailableEmbeddingService implements EmbeddingService {
  const _UnavailableEmbeddingService();

  @override
  int get dimensions => 3;

  @override
  String get modelId => 'unavailable-fixture';

  @override
  Stream<EmbeddingStatus> get status => const Stream.empty();

  @override
  Future<void> close() async {}

  @override
  Future<void> deleteModel() async {}

  @override
  Future<void> downloadModel() async {}

  @override
  Future<List<double>> embed(String text, {bool isQuery = false}) =>
      throw StateError('Embedding model unavailable');

  @override
  Future<bool> isAvailable() async => false;
}

class _BlockingEmbeddingService implements EmbeddingService {
  final started = Completer<void>();
  final _gate = Completer<void>();
  int _activeCalls = 0;
  int maximumConcurrentCalls = 0;

  void release() {
    if (!_gate.isCompleted) _gate.complete();
  }

  @override
  int get dimensions => 3;

  @override
  String get modelId => 'blocking-fixture';

  @override
  Stream<EmbeddingStatus> get status => const Stream.empty();

  @override
  Future<void> close() async {}

  @override
  Future<void> deleteModel() async {}

  @override
  Future<void> downloadModel() async {}

  @override
  Future<List<double>> embed(String text, {bool isQuery = false}) async {
    _activeCalls++;
    if (_activeCalls > maximumConcurrentCalls) {
      maximumConcurrentCalls = _activeCalls;
    }
    if (!started.isCompleted) started.complete();
    await _gate.future;
    _activeCalls--;
    return const [1, 0, 0];
  }

  @override
  Future<bool> isAvailable() async => true;
}

class _CandidateExtractor implements KeyphraseExtractor {
  const _CandidateExtractor(this.candidates);

  final List<KeyphraseCandidate> candidates;

  @override
  Future<List<KeyphraseCandidate>> extract({
    required String content,
    String title = '',
    List<String> supportingText = const [],
    int limit = 12,
  }) async => candidates.take(limit).toList();
}

class _CapturingExtractor implements KeyphraseExtractor {
  List<String> supportingText = const [];

  @override
  Future<List<KeyphraseCandidate>> extract({
    required String content,
    String title = '',
    List<String> supportingText = const [],
    int limit = 12,
  }) async {
    this.supportingText = List.of(supportingText);
    return const [KeyphraseCandidate('patient listening', .9)];
  }
}

class _ContentExtractor implements KeyphraseExtractor {
  const _ContentExtractor();

  @override
  Future<List<KeyphraseCandidate>> extract({
    required String content,
    String title = '',
    List<String> supportingText = const [],
    int limit = 12,
  }) async => [KeyphraseCandidate(content, 1)];
}

class _FixtureExtractor implements KeyphraseExtractor {
  const _FixtureExtractor();

  @override
  Future<List<KeyphraseCandidate>> extract({
    required String content,
    String title = '',
    List<String> supportingText = const [],
    int limit = 12,
  }) async => const [KeyphraseCandidate('Supplication', .9)];
}
