import 'dart:convert';
import 'dart:math' as math;

import 'package:crypto/crypto.dart';

import '../models/journal_entry.dart';
import 'database_service.dart';
import 'embedding_service.dart';
import 'keyphrase_service.dart';

class TaggingService {
  TaggingService(this._database, this._extractor, this._embedding);

  static const _candidateLimit = 12;
  static const _tagLimit = 3;
  static const _semanticReuseThreshold = .90;
  static const _semanticDiversityThreshold = .88;

  final DatabaseService _database;
  final KeyphraseExtractor _extractor;
  final EmbeddingService _embedding;

  Future<JournalTag> renameTag(String tagId, String name) =>
      _database.renameTag(tagId, name);

  Future<void> mergeTags(String sourceTagId, String targetTagId) =>
      _database.mergeTags(sourceTagId, targetTagId);

  Future<List<EntryTag>> organizeEntry(
    DayEntry entry, {
    bool Function()? shouldCommit,
  }) async {
    if (entry.isEmpty) {
      if (shouldCommit?.call() ?? true) {
        await _database.replaceGeneratedTags(entry.id, const []);
      }
      return _database.tagsForEntry(entry.id);
    }
    final document = await _documentFor(entry);
    final entries = await _database.allNonEmptyEntries();
    final candidates = await _extractor.extract(
      content: entry.content,
      title: entry.title,
      supportingText: document.supportingText,
      limit: _candidateLimit,
    );
    final ranked = await _rankCandidates(candidates, document, entries);
    final canonical = await _canonicalize(ranked, await _database.allTags());
    if (!(shouldCommit?.call() ?? true)) {
      return _database.tagsForEntry(entry.id);
    }
    await _database.replaceGeneratedTags(
      entry.id,
      canonical
          .map((candidate) => (candidate.candidate.phrase, candidate.score))
          .toList(),
    );
    return _database.tagsForEntry(entry.id);
  }

  Future<_TaggingDocument> _documentFor(DayEntry entry) async {
    final day = entry.type == DayEntryType.daily
        ? await _database.journalDay(entry.dateKey)
        : null;
    final quietTime = entry.purpose == EntryPurpose.quietTime
        ? await _database.quietTimeForEntry(entry.id)
        : null;
    final supportingText = [
      day?.gratitude ?? '',
      quietTime?.observation ?? '',
      quietTime?.application ?? '',
      quietTime?.prayer ?? '',
    ].where((text) => text.trim().isNotEmpty).toList();
    final sections = [
      if (entry.title.trim().isNotEmpty) 'Title: ${entry.title.trim()}',
      if (entry.content.trim().isNotEmpty) 'Journal: ${entry.content.trim()}',
      if ((day?.gratitude ?? '').trim().isNotEmpty)
        'Gratitude: ${day!.gratitude.trim()}',
      if ((quietTime?.observation ?? '').trim().isNotEmpty)
        'Observation: ${quietTime!.observation.trim()}',
      if ((quietTime?.application ?? '').trim().isNotEmpty)
        'Application: ${quietTime!.application.trim()}',
      if ((quietTime?.prayer ?? '').trim().isNotEmpty)
        'Prayer: ${quietTime!.prayer.trim()}',
    ];
    return _TaggingDocument(
      title: entry.title,
      supportingText: supportingText,
      semanticText: sections.join('\n\n'),
    );
  }

  Future<List<_RankedCandidate>> _rankCandidates(
    List<KeyphraseCandidate> candidates,
    _TaggingDocument document,
    List<DayEntry> corpus,
  ) async {
    if (candidates.isEmpty) return const [];
    final contextSignals = {
      for (final candidate in candidates)
        candidate.phrase: _contextSignal(candidate.phrase, document, corpus),
    };
    try {
      if (!await _embedding.isAvailable()) {
        return _fallbackCandidates(candidates, document, contextSignals);
      }
      final documentVector = await _embedding.embed(document.semanticText);
      final ranked = <_RankedCandidate>[];
      for (final candidate in candidates) {
        final vector = await _embedding.embed(candidate.phrase, isQuery: true);
        final semantic = cosineSimilarity(
          documentVector,
          vector,
        ).clamp(0.0, 1.0);
        final score =
            .70 * semantic +
            .20 * candidate.score +
            .10 * contextSignals[candidate.phrase]!;
        ranked.add(
          _RankedCandidate(candidate: candidate, score: score, vector: vector),
        );
      }
      ranked.sort((left, right) => right.score.compareTo(left.score));
      final bestScore = ranked.first.score;
      final minimumScore = math.max(.50, bestScore - .20);
      return _diverseCandidates(
        ranked.where((candidate) => candidate.score >= minimumScore),
      );
    } catch (_) {
      return _fallbackCandidates(candidates, document, contextSignals);
    }
  }

  List<_RankedCandidate> _fallbackCandidates(
    List<KeyphraseCandidate> candidates,
    _TaggingDocument document,
    Map<String, double> contextSignals,
  ) {
    final ranked =
        candidates
            .where(
              (candidate) =>
                  candidate.score >= .60 &&
                  (_containsPhrase(document.title, candidate.phrase) ||
                      candidate.phrase.trim().split(RegExp(r'\s+')).length > 1),
            )
            .map(
              (candidate) => _RankedCandidate(
                candidate: candidate,
                score:
                    .85 * candidate.score +
                    .15 * contextSignals[candidate.phrase]!,
              ),
            )
            .toList()
          ..sort((left, right) => right.score.compareTo(left.score));
    return _diverseCandidates(ranked);
  }

  List<_RankedCandidate> _diverseCandidates(Iterable<_RankedCandidate> ranked) {
    final selected = <_RankedCandidate>[];
    for (final candidate in ranked) {
      final redundant = selected.any((existing) {
        if (_phrasesOverlap(
          existing.candidate.phrase,
          candidate.candidate.phrase,
        )) {
          return true;
        }
        final left = existing.vector;
        final right = candidate.vector;
        return left != null &&
            right != null &&
            cosineSimilarity(left, right) >= _semanticDiversityThreshold;
      });
      if (!redundant) selected.add(candidate);
      if (selected.length == _tagLimit) break;
    }
    return selected;
  }

  double _contextSignal(
    String phrase,
    _TaggingDocument document,
    List<DayEntry> corpus,
  ) {
    final sourceSignal = _containsPhrase(document.title, phrase)
        ? 1.0
        : document.supportingText.any((text) => _containsPhrase(text, phrase))
        ? .70
        : .55;
    final corpusSize = math.max(corpus.length, 1);
    final documentFrequency = corpus
        .where(
          (entry) =>
              _containsPhrase('${entry.title}\n${entry.content}', phrase),
        )
        .length;
    final rarity =
        (math.log((corpusSize + 1) / (documentFrequency + 1)) + 1) /
        (math.log(corpusSize + 1) + 1);
    return (.60 * sourceSignal + .40 * rarity).clamp(0, 1);
  }

  bool _containsPhrase(String source, String phrase) {
    final normalizedSource = ' ${normalizeTagName(source)} ';
    final normalizedPhrase = normalizeTagName(phrase);
    return normalizedPhrase.isNotEmpty &&
        normalizedSource.contains(' $normalizedPhrase ');
  }

  bool _phrasesOverlap(String left, String right) {
    final leftWords = normalizeTagName(left).split(' ').toSet();
    final rightWords = normalizeTagName(right).split(' ').toSet();
    return leftWords.containsAll(rightWords) ||
        rightWords.containsAll(leftWords);
  }

  Future<List<_RankedCandidate>> _canonicalize(
    List<_RankedCandidate> candidates,
    List<JournalTag> existingTags,
  ) async {
    if (candidates.isEmpty || existingTags.isEmpty) return candidates;
    try {
      if (!await _embedding.isAvailable() ||
          candidates.every((candidate) => candidate.vector == null)) {
        return candidates;
      }
      final tagVectors = <JournalTag, List<double>>{};
      for (final tag in existingTags) {
        tagVectors[tag] = await _embedding.embed(tag.name);
      }
      final canonical = <_RankedCandidate>[];
      final usedNames = <String>{};
      for (final candidate in candidates) {
        final normalized = normalizeTagName(candidate.candidate.phrase);
        final exact = existingTags
            .where((tag) => tag.normalizedName == normalized)
            .firstOrNull;
        if (exact != null) {
          if (usedNames.add(exact.normalizedName)) {
            canonical.add(candidate.withPhrase(exact.name));
          }
          continue;
        }
        JournalTag? closest;
        var closestScore = .0;
        for (final tag in existingTags) {
          final similarity = cosineSimilarity(
            candidate.vector!,
            tagVectors[tag]!,
          );
          if (similarity > closestScore) {
            closest = tag;
            closestScore = similarity;
          }
        }
        final phrase = closestScore >= _semanticReuseThreshold
            ? closest!.name
            : candidate.candidate.phrase;
        if (usedNames.add(normalizeTagName(phrase))) {
          canonical.add(candidate.withPhrase(phrase));
        }
      }
      return canonical;
    } catch (_) {
      return candidates;
    }
  }
}

class _TaggingDocument {
  const _TaggingDocument({
    required this.title,
    required this.supportingText,
    required this.semanticText,
  });

  final String title;
  final List<String> supportingText;
  final String semanticText;
}

class _RankedCandidate {
  const _RankedCandidate({
    required this.candidate,
    required this.score,
    this.vector,
  });

  final KeyphraseCandidate candidate;
  final double score;
  final List<double>? vector;

  _RankedCandidate withPhrase(String phrase) => _RankedCandidate(
    candidate: KeyphraseCandidate(phrase, candidate.score),
    score: score,
    vector: vector,
  );
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
