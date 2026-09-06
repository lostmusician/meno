import 'package:text_analysis/text_analysis.dart';

abstract interface class KeyphraseExtractor {
  Future<List<KeyphraseCandidate>> extract({
    required String content,
    String title = '',
    List<String> supportingText = const [],
    int limit = 12,
  });
}

class KeyphraseCandidate {
  const KeyphraseCandidate(this.phrase, this.score);
  final String phrase;
  final double score;
}

class RakeKeyphraseExtractor implements KeyphraseExtractor {
  const RakeKeyphraseExtractor();

  static const _journalStopWords = {
    'today',
    'day',
    'felt',
    'feel',
    'feeling',
    'thing',
    'things',
    'really',
    'just',
    'went',
    'got',
    'now',
    'tonight',
    'morning',
    'afternoon',
    'evening',
    'yesterday',
    'tomorrow',
    'journal',
    'entry',
  };

  @override
  Future<List<KeyphraseCandidate>> extract({
    required String content,
    String title = '',
    List<String> supportingText = const [],
    int limit = 12,
  }) async {
    final source = [
      title,
      content,
      ...supportingText,
    ].where((value) => value.trim().isNotEmpty).join('\n');
    if (source.trim().isEmpty || limit <= 0) return const [];

    final document = await TextDocument.analyze(
      sourceText: source,
      analyzer: const _ExtractiveEnglish(),
      nGramRange: NGramRange(1, 3),
    );
    final scores = <String, double>{};
    final lowerTitle = title.toLowerCase();
    final lowerSupporting = supportingText.join('\n').toLowerCase();
    for (final entry in document.keywords.keywordScores.entries) {
      final phrase = _clean(entry.key);
      if (!_isUseful(phrase)) continue;
      final titleBoost = lowerTitle.contains(phrase) ? 1.35 : 1.0;
      final supportingBoost = lowerSupporting.contains(phrase) ? 1.08 : 1.0;
      final lengthBalance = phrase.split(' ').length == 1 ? .82 : 1.0;
      scores[phrase] =
          entry.value * titleBoost * supportingBoost * lengthBalance;
    }
    final titlePhrase = _clean(title);
    if (_isUseful(titlePhrase)) {
      final highestScore = scores.values.fold<double>(
        0,
        (highest, score) => score > highest ? score : highest,
      );
      scores[titlePhrase] = highestScore == 0 ? 1 : highestScore * 1.05;
    }
    final ranked = scores.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final maximum = ranked.firstOrNull?.value ?? 1;
    return ranked
        .take(limit)
        .map(
          (entry) => KeyphraseCandidate(
            _displayPhrase(entry.key, source),
            (entry.value / maximum).clamp(0, 1),
          ),
        )
        .toList();
  }

  static String _clean(String value) => value
      .toLowerCase()
      .replaceAll(RegExp(r"[^a-z0-9' -]"), ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();

  static bool _isUseful(String phrase) {
    if (phrase.length < 3 || phrase.length > 48) return false;
    final words = phrase.split(' ');
    if (words.length > 3) return false;
    if (words.every(_journalStopWords.contains)) return false;
    if (words.any((word) => word.length < 2)) return false;
    return RegExp(r'[a-z]').hasMatch(phrase);
  }

  static String _displayPhrase(String phrase, String source) {
    final match = RegExp(
      RegExp.escape(phrase),
      caseSensitive: false,
    ).firstMatch(source);
    if (match == null) return phrase;
    return source.substring(match.start, match.end).trim();
  }
}

class _ExtractiveEnglish extends English {
  const _ExtractiveEnglish();

  @override
  String? Function(String term) get stemmer => _preserveTerm;

  static String _preserveTerm(String term) => term.toLowerCase();
}
