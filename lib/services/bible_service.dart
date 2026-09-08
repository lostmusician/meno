import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/journal_entry.dart';

class BibleBook {
  const BibleBook(this.id, this.name);
  final String id;
  final String name;
}

abstract interface class BibleProvider {
  Future<List<BibleVersion>> versions();
  Future<List<BibleBook>> books(BibleVersion version);
  Future<List<int>> chapters(BibleVersion version, BibleBook book);
  Future<List<BiblePassage>> chapterVerses(
    BibleVersion version,
    BibleBook book,
    int chapter,
  );
  Future<BiblePassage> passage(BibleVersion version, String passageId);
}

class YouVersionBibleProvider implements BibleProvider {
  YouVersionBibleProvider({String? appKey, http.Client? client})
    : appKey = appKey ?? const String.fromEnvironment('YOUVERSION_APP_KEY'),
      _client = client ?? http.Client();

  final String appKey;
  final http.Client _client;
  static final _base = Uri.parse('https://api.youversion.com/v1/');
  static const supportedAbbreviations = ['ESV', 'NIV', 'ERV', 'NKJV'];
  static const _supportedVersionIds = {
    'ESV': '59',
    'NIV': '111',
    'ERV': '406',
    'NKJV': '114',
  };

  bool get isConfigured => appKey.isNotEmpty;

  Map<String, String> get _headers {
    if (appKey.isEmpty) {
      throw StateError(
        'YouVersion access has not been configured for this build.',
      );
    }
    return {'X-YVP-App-Key': appKey, 'Accept': 'application/json'};
  }

  @override
  Future<List<BibleVersion>> versions() async {
    final json = await _get('bibles?language_ranges%5B%5D=en%2A&page_size=99');
    final versions = (json['data'] as List<dynamic>? ?? const [])
        .cast<Map<String, dynamic>>()
        .map(_versionFromJson)
        .toList();
    final byAbbreviation = {
      for (final version in versions)
        version.abbreviation.trim().toUpperCase(): version,
    };

    // Some app keys can fetch an approved Bible by ID even when the collection
    // endpoint omits it. Fall back to the canonical IDs only when discovery
    // found none of the product-supported translations.
    if (!supportedAbbreviations.any(byAbbreviation.containsKey)) {
      final directVersions = await Future.wait(
        _supportedVersionIds.entries.map(_versionByIdOrNull),
      );
      for (final version in directVersions.nonNulls) {
        byAbbreviation[version.abbreviation.trim().toUpperCase()] = version;
      }
    }

    return [
      for (final abbreviation in supportedAbbreviations)
        ?byAbbreviation[abbreviation],
    ];
  }

  BibleVersion _versionFromJson(Map<String, dynamic> item) => BibleVersion(
    id: '${item['id']}',
    abbreviation: '${item['localized_abbreviation'] ?? item['abbreviation']}',
    title: '${item['localized_title'] ?? item['title']}',
    copyright: '${item['copyright'] ?? ''}',
  );

  Future<BibleVersion?> _versionByIdOrNull(
    MapEntry<String, String> entry,
  ) async {
    try {
      final detail = await _get('bibles/${entry.value}');
      final data = detail['data'] is Map<String, dynamic>
          ? detail['data']! as Map<String, dynamic>
          : detail;
      final version = _versionFromJson(data);
      return version.abbreviation.trim().toUpperCase() == entry.key
          ? version
          : null;
    } catch (_) {
      // An unavailable version is expected when its license is absent.
      return null;
    }
  }

  @override
  Future<List<BibleBook>> books(BibleVersion version) async {
    final json = await _get('bibles/${version.id}/books');
    return (json['data'] as List<dynamic>? ??
            json['books'] as List<dynamic>? ??
            const [])
        .cast<Map<String, dynamic>>()
        .map(
          (item) => BibleBook(
            '${item['usfm'] ?? item['id']}',
            '${item['localized_title'] ?? item['title'] ?? item['name']}',
          ),
        )
        .toList();
  }

  @override
  Future<List<int>> chapters(BibleVersion version, BibleBook book) async {
    final json = await _get('bibles/${version.id}/books/${book.id}/chapters');
    final rows =
        (json['data'] as List<dynamic>? ??
                json['chapters'] as List<dynamic>? ??
                const [])
            .cast<Map<String, dynamic>>();
    return rows
        .map((item) {
          final raw =
              '${item['number'] ?? item['chapter_number'] ?? item['id']}';
          return int.tryParse(raw) ??
              int.tryParse(RegExp(r'(\d+)$').firstMatch(raw)?.group(1) ?? '');
        })
        .whereType<int>()
        .toList();
  }

  @override
  Future<BiblePassage> passage(BibleVersion version, String passageId) async {
    final json = await _get(
      'bibles/${version.id}/passages/${Uri.encodeComponent(passageId)}?format=text&include_headings=false&include_notes=false',
    );
    final data = json['data'] is Map<String, dynamic>
        ? json['data']! as Map<String, dynamic>
        : json;
    return BiblePassage(
      id: '${data['id']}',
      reference: '${data['reference']}',
      content: '${data['content']}',
      version: version,
    );
  }

  @override
  Future<List<BiblePassage>> chapterVerses(
    BibleVersion version,
    BibleBook book,
    int chapter,
  ) async {
    final json = await _get(
      'bibles/${version.id}/passages/${book.id}.$chapter'
      '?format=html&include_headings=false&include_notes=false',
    );
    final data = json['data'] is Map<String, dynamic>
        ? json['data']! as Map<String, dynamic>
        : json;
    return _versesFromHtml(
      '${data['content'] ?? ''}',
      version: version,
      book: book,
      chapter: chapter,
    );
  }

  List<BiblePassage> _versesFromHtml(
    String html, {
    required BibleVersion version,
    required BibleBook book,
    required int chapter,
  }) {
    final marker = RegExp(
      r'''<span\b[^>]*class=["'][^"']*\byv-v\b[^"']*["'][^>]*>''',
      caseSensitive: false,
    );
    final markers = marker.allMatches(html).toList();
    final passages = <BiblePassage>[];
    for (var index = 0; index < markers.length; index++) {
      final current = markers[index];
      final verseMatch = RegExp(
        r'''\bv=["']?(\d+)''',
        caseSensitive: false,
      ).firstMatch(current.group(0)!);
      final verse = int.tryParse(verseMatch?.group(1) ?? '');
      if (verse == null) continue;
      final end = index + 1 < markers.length
          ? markers[index + 1].start
          : html.length;
      final content = _plainTextFromHtml(html.substring(current.end, end));
      if (content.isEmpty) continue;
      passages.add(
        BiblePassage(
          id: '${book.id}.$chapter.$verse',
          reference: '${book.name} $chapter:$verse',
          content: content,
          version: version,
        ),
      );
    }
    return passages;
  }

  String _plainTextFromHtml(String value) {
    var text = value
        .replaceAll(
          RegExp(
            r'''<span\b[^>]*class=["'][^"']*\byv-vlbl\b[^"']*["'][^>]*>.*?</span>''',
            caseSensitive: false,
            dotAll: true,
          ),
          '',
        )
        .replaceAll(RegExp(r'<br\s*/?>', caseSensitive: false), '\n')
        .replaceAll(RegExp(r'</(?:p|div|li)>', caseSensitive: false), '\n')
        .replaceAll(RegExp(r'<[^>]+>'), '');
    text = text.replaceAllMapped(
      RegExp(r'&#(\d+);'),
      (match) => String.fromCharCode(int.parse(match.group(1)!)),
    );
    text = text.replaceAllMapped(
      RegExp(r'&#x([0-9a-f]+);', caseSensitive: false),
      (match) => String.fromCharCode(int.parse(match.group(1)!, radix: 16)),
    );
    const entities = {
      '&nbsp;': ' ',
      '&amp;': '&',
      '&quot;': '"',
      '&apos;': "'",
      '&#39;': "'",
      '&lt;': '<',
      '&gt;': '>',
    };
    for (final entry in entities.entries) {
      text = text.replaceAll(entry.key, entry.value);
    }
    return text.replaceAll(RegExp(r'\s+'), ' ').trim();
  }

  Future<Map<String, dynamic>> _get(String path) async {
    final response = await _client
        .get(_base.resolve(path), headers: _headers)
        .timeout(const Duration(seconds: 15));
    if (response.statusCode == 429) {
      final retry = response.headers['retry-after'];
      throw BibleRateLimitException(retry == null ? null : int.tryParse(retry));
    }
    if (response.statusCode == 401 || response.statusCode == 403) {
      throw StateError(
        'This Bible version is not licensed to the configured app.',
      );
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      final detail = _responseDetail(response.body);
      throw http.ClientException(
        'YouVersion request failed (${response.statusCode})'
        '${detail.isEmpty ? '.' : ': $detail'}',
        response.request?.url,
      );
    }
    return jsonDecode(response.body) as Map<String, dynamic>;
  }

  void close() => _client.close();

  String _responseDetail(String body) {
    final trimmed = body.trim();
    if (trimmed.isEmpty) return '';
    try {
      final decoded = jsonDecode(trimmed);
      if (decoded case {'message': final Object message}) return '$message';
      if (decoded case {'detail': final Object detail}) return '$detail';
      if (decoded case {'error': final Object error}) return '$error';
    } catch (_) {
      // Fall through to a bounded plain-text response.
    }
    return trimmed.length <= 240 ? trimmed : '${trimmed.substring(0, 240)}…';
  }
}

class BibleRateLimitException implements Exception {
  const BibleRateLimitException(this.retryAfterSeconds);
  final int? retryAfterSeconds;
}
