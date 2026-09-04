import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/journal_entry.dart';
import '../services/bible_service.dart';
import '../services/database_service.dart';
import '../services/embedding_service.dart';
import '../services/keyphrase_service.dart';
import '../services/organization_service.dart';

final databaseServiceProvider = Provider<DatabaseService>((ref) {
  final service = DatabaseService();
  ref.onDispose(service.close);
  return service;
});

final keyphraseExtractorProvider = Provider<KeyphraseExtractor>(
  (ref) => const RakeKeyphraseExtractor(),
);

final taggingServiceProvider = Provider<TaggingService>(
  (ref) => TaggingService(
    ref.watch(databaseServiceProvider),
    ref.watch(keyphraseExtractorProvider),
    ref.watch(embeddingServiceProvider),
  ),
);

final relationshipServiceProvider = Provider<RelationshipService>(
  (ref) => RelationshipService(
    ref.watch(databaseServiceProvider),
    ref.watch(embeddingServiceProvider),
  ),
);

final embeddingServiceProvider = Provider<EmbeddingService>((ref) {
  final service = ArcticEmbeddingService();
  ref.onDispose(service.close);
  return service;
});

final youVersionBibleProvider = Provider<YouVersionBibleProvider>((ref) {
  final provider = YouVersionBibleProvider();
  ref.onDispose(provider.close);
  return provider;
});

class LinkedPassageRequest {
  const LinkedPassageRequest({
    required this.bibleId,
    required this.passageId,
    required this.translationAbbreviation,
    required this.reference,
    required this.copyright,
  });

  factory LinkedPassageRequest.fromReference(ScriptureReference reference) =>
      LinkedPassageRequest(
        bibleId: reference.bibleId,
        passageId: reference.passageId,
        translationAbbreviation: reference.translationAbbreviation,
        reference: reference.reference,
        copyright: reference.copyright,
      );

  final String bibleId;
  final String passageId;
  final String translationAbbreviation;
  final String reference;
  final String copyright;

  String get cacheKey => '$bibleId:$passageId';

  @override
  bool operator ==(Object other) =>
      other is LinkedPassageRequest &&
      other.bibleId == bibleId &&
      other.passageId == passageId;

  @override
  int get hashCode => Object.hash(bibleId, passageId);
}

final _linkedPassageCache = <String, Future<BiblePassage>>{};

final linkedPassageProvider =
    FutureProvider.family<BiblePassage, LinkedPassageRequest>((ref, request) {
      return _linkedPassageCache.putIfAbsent(
        request.cacheKey,
        () => ref
            .read(youVersionBibleProvider)
            .passage(
              BibleVersion(
                id: request.bibleId,
                abbreviation: request.translationAbbreviation,
                title: request.translationAbbreviation,
                copyright: request.copyright,
              ),
              request.passageId,
            ),
      );
    });

void cacheLinkedPassage(BiblePassage passage) {
  _linkedPassageCache['${passage.version.id}:${passage.id}'] = Future.value(
    passage,
  );
}

void retryLinkedPassage(WidgetRef ref, LinkedPassageRequest request) {
  _linkedPassageCache.remove(request.cacheKey);
  ref.invalidate(linkedPassageProvider(request));
}
