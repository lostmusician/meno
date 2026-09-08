import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:archive/archive_io.dart';
import 'package:crypto/crypto.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path/path.dart' as p;

import 'database_service.dart';

class BackupValidationException implements Exception {
  const BackupValidationException(this.message);

  final String message;

  @override
  String toString() => message;
}

class MenoBackupManifest {
  const MenoBackupManifest({
    required this.createdAt,
    required this.appVersion,
    required this.schemaVersion,
    required this.databaseSha256,
    required this.recordCounts,
  });

  factory MenoBackupManifest.fromJson(Map<String, Object?> json) {
    if (json['format'] != 'meno-backup' || json['format_version'] != 1) {
      throw const BackupValidationException(
        'This is not a supported Meno backup.',
      );
    }
    final counts = json['record_counts'];
    if (counts is! Map) {
      throw const BackupValidationException(
        'The backup manifest is incomplete.',
      );
    }
    return MenoBackupManifest(
      createdAt: DateTime.parse(json['created_at']! as String).toUtc(),
      appVersion: json['app_version']! as String,
      schemaVersion: json['schema_version']! as int,
      databaseSha256: json['database_sha256']! as String,
      recordCounts: {
        for (final entry in counts.entries)
          entry.key as String: (entry.value as num).toInt(),
      },
    );
  }

  final DateTime createdAt;
  final String appVersion;
  final int schemaVersion;
  final String databaseSha256;
  final Map<String, int> recordCounts;

  Map<String, Object?> toJson() => {
    'format': 'meno-backup',
    'format_version': 1,
    'created_at': createdAt.toIso8601String(),
    'app_version': appVersion,
    'schema_version': schemaVersion,
    'database_sha256': databaseSha256,
    'record_counts': recordCounts,
  };
}

class BackupResult {
  const BackupResult({required this.file, required this.manifest});

  final File file;
  final MenoBackupManifest manifest;
}

class BackupService {
  BackupService(this._database);

  final DatabaseService _database;

  Future<BackupResult> createBackup(
    File destination, {
    String? appVersion,
  }) async {
    if (!destination.path.toLowerCase().endsWith('.meno-backup')) {
      destination = File('${destination.path}.meno-backup');
    }
    final temporary = await Directory.systemTemp.createTemp('meno-backup-');
    try {
      final databaseFile = await _database.createConsistentCopy(
        File(p.join(temporary.path, 'journal.sqlite')),
      );
      final databaseBytes = await databaseFile.readAsBytes();
      final package = appVersion == null
          ? await PackageInfo.fromPlatform()
          : null;
      final manifest = MenoBackupManifest(
        createdAt: DateTime.now().toUtc(),
        appVersion: appVersion ?? '${package!.version}+${package.buildNumber}',
        schemaVersion: DatabaseService.schemaVersion,
        databaseSha256: sha256.convert(databaseBytes).toString(),
        recordCounts: await _database.recordCounts(),
      );
      final manifestBytes = utf8.encode(
        const JsonEncoder.withIndent('  ').convert(manifest.toJson()),
      );
      final archive = Archive()
        ..addFile(
          ArchiveFile('manifest.json', manifestBytes.length, manifestBytes),
        )
        ..addFile(
          ArchiveFile('journal.sqlite', databaseBytes.length, databaseBytes),
        );
      final encoded = ZipEncoder().encode(archive);
      if (encoded == null) {
        throw const BackupValidationException(
          'Meno could not encode the backup.',
        );
      }
      await destination.parent.create(recursive: true);
      final partial = File('${destination.path}.partial');
      if (await partial.exists()) await partial.delete();
      await partial.writeAsBytes(encoded, flush: true);
      if (await destination.exists()) await destination.delete();
      await partial.rename(destination.path);
      return BackupResult(file: destination, manifest: manifest);
    } finally {
      await temporary.delete(recursive: true);
    }
  }

  Future<MenoBackupManifest> inspect(File source) async {
    final decoded = ZipDecoder().decodeBytes(
      await source.readAsBytes(),
      verify: true,
    );
    final manifestFile = decoded.files
        .where((file) => file.name == 'manifest.json')
        .firstOrNull;
    final databaseFile = decoded.files
        .where((file) => file.name == 'journal.sqlite')
        .firstOrNull;
    if (manifestFile == null ||
        databaseFile == null ||
        decoded.files.length != 2) {
      throw const BackupValidationException(
        'The backup archive is incomplete.',
      );
    }
    final manifest = MenoBackupManifest.fromJson(
      jsonDecode(utf8.decode(manifestFile.content as List<int>))
          as Map<String, Object?>,
    );
    if (manifest.schemaVersion > DatabaseService.schemaVersion) {
      throw UnsupportedDatabaseVersionException(
        manifest.schemaVersion,
        DatabaseService.schemaVersion,
      );
    }
    final actualHash = sha256
        .convert(databaseFile.content as List<int>)
        .toString();
    if (actualHash != manifest.databaseSha256) {
      throw const BackupValidationException(
        'The backup checksum does not match.',
      );
    }
    return manifest;
  }

  Future<MenoBackupManifest> restore(File source) async {
    final manifest = await inspect(source);
    final decoded = ZipDecoder().decodeBytes(
      await source.readAsBytes(),
      verify: true,
    );
    final databaseBytes =
        decoded.files
                .singleWhere((file) => file.name == 'journal.sqlite')
                .content
            as List<int>;
    final temporary = await Directory.systemTemp.createTemp('meno-restore-');
    try {
      final staged = File(p.join(temporary.path, 'journal.sqlite'));
      await staged.writeAsBytes(databaseBytes, flush: true);
      final actualCounts = await _database.validateCandidateDatabase(staged);
      for (final entry in manifest.recordCounts.entries) {
        if (actualCounts[entry.key] != entry.value) {
          throw const BackupValidationException(
            'The backup record counts do not match its manifest.',
          );
        }
      }
      await _database.restoreFromDatabaseFile(staged);
      return manifest;
    } finally {
      await temporary.delete(recursive: true);
    }
  }
}
