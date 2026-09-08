import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter_onnxruntime/flutter_onnxruntime.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

enum EmbeddingAvailability {
  notDownloaded,
  downloading,
  ready,
  unavailable,
  failed,
}

class EmbeddingStatus {
  const EmbeddingStatus(this.availability, {this.progress = 0, this.error});
  final EmbeddingAvailability availability;
  final double progress;
  final Object? error;
}

abstract interface class EmbeddingService {
  String get modelId;
  int get dimensions;
  Stream<EmbeddingStatus> get status;
  Future<bool> isAvailable();
  Future<void> downloadModel();
  Future<List<double>> embed(String text, {bool isQuery = false});
  Future<void> deleteModel();
  Future<void> close();
}

double cosineSimilarity(List<double> left, List<double> right) {
  if (left.length != right.length || left.isEmpty) return 0;
  var product = 0.0;
  for (var index = 0; index < left.length; index++) {
    product += left[index] * right[index];
  }
  return product.clamp(-1, 1);
}

class ArcticEmbeddingService implements EmbeddingService {
  ArcticEmbeddingService({http.Client? client, Directory? modelDirectory})
    : _client = client ?? http.Client(),
      _modelDirectory = modelDirectory;

  static const _modelUrl =
      'https://huggingface.co/Snowflake/snowflake-arctic-embed-xs/resolve/main/onnx/model_int8.onnx';
  static const _vocabUrl =
      'https://huggingface.co/Snowflake/snowflake-arctic-embed-xs/resolve/main/vocab.txt';
  static const _modelSha256 =
      'e6aa5e656466a73d7c3111e9a3378bd13e5b93af30eaac2b3f13fd56692589a1';
  static const _queryPrefix =
      'Represent this sentence for searching relevant passages: ';

  final http.Client _client;
  final Directory? _modelDirectory;
  final _status = StreamController<EmbeddingStatus>.broadcast();
  OrtSession? _session;
  _WordPieceTokenizer? _tokenizer;

  @override
  String get modelId => 'snowflake-arctic-embed-xs-int8-v1';

  @override
  int get dimensions => 384;

  @override
  Stream<EmbeddingStatus> get status => _status.stream;

  Future<Directory> get _directory async {
    if (_modelDirectory case final directory?) return directory;
    final support = await getApplicationSupportDirectory();
    return Directory(p.join(support.path, 'models', modelId));
  }

  Future<File> get _modelFile async =>
      File(p.join((await _directory).path, 'model.onnx'));
  Future<File> get _vocabFile async =>
      File(p.join((await _directory).path, 'vocab.txt'));

  @override
  Future<bool> isAvailable() async =>
      await (await _modelFile).exists() && await (await _vocabFile).exists();

  @override
  Future<void> downloadModel() async {
    if (await isAvailable()) {
      _status.add(
        const EmbeddingStatus(EmbeddingAvailability.ready, progress: 1),
      );
      return;
    }
    final directory = await _directory;
    await directory.create(recursive: true);
    _status.add(const EmbeddingStatus(EmbeddingAvailability.downloading));
    try {
      await _download(Uri.parse(_modelUrl), await _modelFile, .92);
      final digest = sha256
          .convert(await (await _modelFile).readAsBytes())
          .toString();
      if (digest != _modelSha256) {
        await (await _modelFile).delete();
        throw StateError(
          'The downloaded semantic model failed checksum validation.',
        );
      }
      await _download(Uri.parse(_vocabUrl), await _vocabFile, 1);
      _status.add(
        const EmbeddingStatus(EmbeddingAvailability.ready, progress: 1),
      );
    } catch (error) {
      _status.add(EmbeddingStatus(EmbeddingAvailability.failed, error: error));
      rethrow;
    }
  }

  Future<void> _download(
    Uri uri,
    File destination,
    double finalProgress,
  ) async {
    final temporary = File('${destination.path}.download');
    final request = http.Request('GET', uri);
    final response = await _client.send(request);
    if (response.statusCode != 200) {
      throw HttpException(
        'Model download failed (${response.statusCode})',
        uri: uri,
      );
    }
    final sink = temporary.openWrite();
    var received = 0;
    final total = response.contentLength ?? 0;
    await for (final chunk in response.stream) {
      sink.add(chunk);
      received += chunk.length;
      if (total > 0) {
        _status.add(
          EmbeddingStatus(
            EmbeddingAvailability.downloading,
            progress: (received / total * finalProgress).clamp(
              0,
              finalProgress,
            ),
          ),
        );
      }
    }
    await sink.close();
    if (await destination.exists()) await destination.delete();
    await temporary.rename(destination.path);
  }

  Future<void> _load() async {
    if (_session != null && _tokenizer != null) return;
    if (!await isAvailable()) {
      throw StateError('Semantic model is not downloaded.');
    }
    _tokenizer = _WordPieceTokenizer(
      await (await _vocabFile).readAsLines(),
      maxLength: 512,
    );
    _session = await OnnxRuntime().createSession((await _modelFile).path);
  }

  @override
  Future<List<double>> embed(String text, {bool isQuery = false}) async {
    await _load();
    final tokens = _tokenizer!.encode('${isQuery ? _queryPrefix : ''}$text');
    final inputIds = await OrtValue.fromList(Int64List.fromList(tokens.ids), [
      1,
      tokens.ids.length,
    ]);
    final attention = await OrtValue.fromList(Int64List.fromList(tokens.mask), [
      1,
      tokens.mask.length,
    ]);
    final tokenTypes = await OrtValue.fromList(
      Int64List.fromList(tokens.types),
      [1, tokens.types.length],
    );
    try {
      final inputs = <String, OrtValue>{
        'input_ids': inputIds,
        'attention_mask': attention,
      };
      if (_session!.inputNames.contains('token_type_ids')) {
        inputs['token_type_ids'] = tokenTypes;
      }
      final outputs = await _session!.run(inputs);
      final output = outputs.values.first;
      final flattened = (await output.asFlattenedList())
          .cast<num>()
          .map((value) => value.toDouble())
          .toList();
      final dimensions = output.shape.last;
      final cls = flattened.take(dimensions).toList();
      final norm = math.sqrt(
        cls.fold<double>(0, (sum, value) => sum + value * value),
      );
      if (norm == 0) return List<double>.filled(dimensions, 0);
      return cls.map((value) => value / norm).toList();
    } finally {
      await inputIds.dispose();
      await attention.dispose();
      await tokenTypes.dispose();
    }
  }

  @override
  Future<void> deleteModel() async {
    await _session?.close();
    _session = null;
    _tokenizer = null;
    final directory = await _directory;
    if (await directory.exists()) await directory.delete(recursive: true);
    _status.add(const EmbeddingStatus(EmbeddingAvailability.notDownloaded));
  }

  @override
  Future<void> close() async {
    await _session?.close();
    _client.close();
    await _status.close();
  }
}

class _EncodedTokens {
  const _EncodedTokens(this.ids, this.mask, this.types);
  final List<int> ids;
  final List<int> mask;
  final List<int> types;
}

class _WordPieceTokenizer {
  _WordPieceTokenizer(List<String> vocabulary, {required this.maxLength})
    : _vocabulary = {
        for (var index = 0; index < vocabulary.length; index++)
          vocabulary[index].trim(): index,
      };

  final Map<String, int> _vocabulary;
  final int maxLength;

  _EncodedTokens encode(String text) {
    final tokens = <String>['[CLS]'];
    final words = text
        .toLowerCase()
        .replaceAllMapped(
          RegExp(r'''([!"#$%&'()*+,\-./:;<=>?@\[\\\]^_`{|}~])'''),
          (match) => ' ${match[1]} ',
        )
        .split(RegExp(r'\s+'))
        .where((word) => word.isNotEmpty);
    for (final word in words) {
      if (tokens.length >= maxLength - 1) break;
      tokens.addAll(_pieces(word).take(maxLength - 1 - tokens.length));
    }
    tokens.add('[SEP]');
    final ids = tokens
        .map((token) => _vocabulary[token] ?? _vocabulary['[UNK]'] ?? 100)
        .toList();
    return _EncodedTokens(
      ids,
      List<int>.filled(ids.length, 1),
      List<int>.filled(ids.length, 0),
    );
  }

  Iterable<String> _pieces(String word) sync* {
    if (_vocabulary.containsKey(word)) {
      yield word;
      return;
    }
    var start = 0;
    final pieces = <String>[];
    while (start < word.length) {
      String? found;
      var end = word.length;
      while (end > start) {
        final value = '${start == 0 ? '' : '##'}${word.substring(start, end)}';
        if (_vocabulary.containsKey(value)) {
          found = value;
          break;
        }
        end--;
      }
      if (found == null) {
        yield '[UNK]';
        return;
      }
      pieces.add(found);
      start = end;
    }
    yield* pieces;
  }
}
