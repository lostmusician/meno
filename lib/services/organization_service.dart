import 'dart:convert';
import 'dart:math' as math;

import 'package:crypto/crypto.dart';

import '../models/journal_entry.dart';
import 'database_service.dart';
import 'embedding_service.dart';
import 'keyphrase_service.dart';

class TaggingService {
  TaggingService(this._database, this._extractor, this._embedding);

  final DatabaseService _database;
  final KeyphraseExtractor _extractor;
  final EmbeddingService _embedding;

  Future<JournalTag> renameTag(String tagId, String name) =>
      _database.renameTag(tagId, name);

  Future<void> mergeTags(String sourceTagId, String targetTagId) =>
      _database.mergeTags(sourceTagId, targetTagId);

  Future<List<EntryTag>> organizeEntry(DayEntry entry) async {
    if (entry.isEmpty) {
      await _database.replaceGeneratedTags(entry.id, const []);
      return _database.tagsForEntry(entry.id);
    }
    final day = await _database.journalDay(entry.dateKey);
    final tags = await _database.allTags();
    final frequency = await _database.tagUsageCounts();
    final entries = await _database.allNonEmptyEntries();
    final candidates = await _extractor.extract(
      content: entry.content,
      title: entry.title,
      gratitude: entry.type == DayEntryType.daily ? day?.gratitude ?? '' : '',
      corpusFrequency: frequency,
      corpusSize: math.max(entries.length, 1),
    );
    final canonical = await _canonicalize(candidates, tags);
    await _database.replaceGeneratedTags(
      entry.id,
      canonical
          .map((candidate) => (candidate.phrase, candidate.score))
          .toList(),
    );
    return _database.tagsForEntry(entry.id);
  }

  Future<List<KeyphraseCandidate>> _canonicalize(
    List<KeyphraseCandidate> candidates,
    List<JournalTag> existingTags,
  ) async {
    if (candidates.isEmpty || existingTags.isEmpty) return candidates;
    try {
      if (!await _embedding.isAvailable()) return candidates;
      final tagVectors = <JournalTag, List<double>>{};
      for (final tag in existingTags) {
        tagVectors[tag] = await _embedding.embed(tag.name);
      }
      final canonical = <KeyphraseCandidate>[];
      for (final candidate in candidates) {
        final normalized = normalizeTagName(candidate.phrase);
        final exact = existingTags
            .where((tag) => tag.normalizedName == normalized)
            .firstOrNull;
        if (exact != null) {
          canonical.add(KeyphraseCandidate(exact.name, candidate.score));
          continue;
        }
        final vector = await _embedding.embed(candidate.phrase);
        JournalTag? closest;
        var closestScore = .0;
        for (final tag in existingTags) {
          final similarity = cosineSimilarity(vector, tagVectors[tag]!);
          if (similarity > closestScore) {
            closest = tag;
            closestScore = similarity;
          }
        }
        canonical.add(
          KeyphraseCandidate(
            closestScore >= .9 ? closest!.name : candidate.phrase,
            candidate.score,
          ),
        );
      }
      return canonical;
    } catch (_) {
      return candidates;
    }
  }

  Future<void> organizeBackCatalog({
    bool Function()? isCancelled,
    void Function(int completed, int total)? onProgress,
  }) async {
    final entries = await _database.allNonEmptyEntries();
    for (var index = 0; index < entries.length; index++) {
      if (isCancelled?.call() ?? false) return;
      await organizeEntry(entries[index]);
      onProgress?.call(index + 1, entries.length);
      await Future<void>.delayed(Duration.zero);
    }
  }
}

class RelationshipService {
  RelationshipService(this._database, this._embedding);

  final DatabaseService _database;
  final EmbeddingService _embedding;

  Future<List<EntryRelationship>> rebuildForEntry(String entryId) async {
    final entries = await _database.allNonEmptyEntries();
    final source = entries.where((entry) => entry.id == entryId).firstOrNull;
    if (source == null) return const [];
    final sourceTags = await _database.tagsForEntry(entryId);
    final shared = <String, Set<String>>{};
    for (final candidate in await _database.sharedTagCandidates(entryId)) {
      shared.putIfAbsent(candidate.entryId, () => {}).add(candidate.tagName);
    }
    final scores = <String, double>{};
    final reasons = <String, List<String>>{};
    for (final candidate in shared.entries) {
      scores[candidate.key] =
          .2 * candidate.value.length / math.max(sourceTags.length, 1);
      reasons[candidate.key] = candidate.value
          .map((tag) => 'Shared tag: $tag')
          .toList();
    }
    for (final candidate in await _database.sharedScriptureCandidates(
      entryId,
    )) {
      scores[candidate.entryId] = (scores[candidate.entryId] ?? 0) + .15;
      reasons
          .putIfAbsent(candidate.entryId, () => [])
          .add('Shared Scripture: ${candidate.reference}');
    }

    var usedEmbeddings = false;
    try {
      if (await _embedding.isAvailable()) {
        usedEmbeddings = true;
        final sourceVectors = await _embeddingsFor(source);
        for (final candidate in entries) {
          if (candidate.id == entryId) continue;
          final candidateVectors = await _embeddingsFor(candidate);
          final wholeSimilarity = cosineSimilarity(
            sourceVectors.first,
            candidateVectors.first,
          );
          var chunkMaximum = wholeSimilarity;
          for (final left in sourceVectors) {
            for (final right in candidateVectors) {
              chunkMaximum = math.max(
                chunkMaximum,
                cosineSimilarity(left, right),
              );
            }
          }
          final similarity = .65 * wholeSimilarity + .35 * chunkMaximum;
          if (similarity < .55) continue;
          scores[candidate.id] = (scores[candidate.id] ?? 0) + .8 * similarity;
          reasons.putIfAbsent(candidate.id, () => []).add('Similar theme');
        }
      }
    } catch (_) {
      // Keyword and shared-tag discovery remain available if local inference fails.
      usedEmbeddings = false;
    }

    final relationships =
        scores.entries
            .map(
              (candidate) => EntryRelationship(
                sourceEntryId: entryId,
                targetEntryId: candidate.key,
                score: candidate.value.clamp(0, 1),
                reasons: reasons[candidate.key] ?? const [],
              ),
            )
            .toList()
          ..sort((a, b) => b.score.compareTo(a.score));
    await _database.saveRelationships(
      entryId,
      relationships,
      modelId: usedEmbeddings ? _embedding.modelId : 'shared-tags-v1',
    );
    return relationships.take(8).toList();
  }

  Future<List<List<double>>> _embeddingsFor(DayEntry entry) async {
    final day = entry.type == DayEntryType.daily
        ? await _database.journalDay(entry.dateKey)
        : null;
    final quietTime = entry.purpose == EntryPurpose.quietTime
        ? await _database.quietTimeForEntry(entry.id)
        : null;
    final scriptures = await _database.scripturesForEntry(entry.id);
    final authoredParts = [
      entry.title,
      entry.content,
      day?.gratitude ?? '',
      quietTime?.observation ?? '',
      quietTime?.application ?? '',
      quietTime?.prayer ?? '',
    ].where((part) => part.trim().isNotEmpty).toList();
    final text = [
      ...authoredParts,
      ...scriptures.map((scripture) => 'Scripture: ${scripture.reference}'),
    ].join('\n\n');
    final contentHash = sha256.convert(utf8.encode(text)).toString();
    final cached = await _database.embeddingForEntry(
      entry.id,
      _embedding.modelId,
    );
    if (cached?.contentHash == contentHash &&
        cached!.vector.length % _embedding.dimensions == 0) {
      return [
        for (
          var offset = 0;
          offset < cached.vector.length;
          offset += _embedding.dimensions
        )
          cached.vector.sublist(offset, offset + _embedding.dimensions),
      ];
    }

    final whole = await _embedding.embed(text);
    final paragraphs = authoredParts
        .expand((part) => part.split(RegExp(r'\n\s*\n')))
        .map((paragraph) => paragraph.trim())
        .where((paragraph) => paragraph.length >= 24)
        .take(6);
    final chunks = <List<double>>[];
    for (final paragraph in paragraphs) {
      chunks.add(await _embedding.embed(paragraph));
    }
    final representations = [whole, ...chunks];
    await _database.saveEmbedding(
      entryId: entry.id,
      modelId: _embedding.modelId,
      contentHash: contentHash,
      vector: representations.expand((vector) => vector).toList(),
    );
    return representations;
  }

  Future<void> rebuildAll({
    bool Function()? isCancelled,
    void Function(int completed, int total)? onProgress,
  }) async {
    final entries = await _database.allNonEmptyEntries();
    for (var index = 0; index < entries.length; index++) {
      if (isCancelled?.call() ?? false) return;
      await rebuildForEntry(entries[index].id);
      onProgress?.call(index + 1, entries.length);
    }
  }
}
