import 'dart:io';

import 'package:path/path.dart' as p;

import '../models/journal_entry.dart';
import 'database_service.dart';

class MarkdownExportService {
  const MarkdownExportService(this._database);

  final DatabaseService _database;

  Future<Directory> exportTo(Directory destination) async {
    final db = await _database.database;
    final root = Directory(
      p.join(
        destination.path,
        'Meno Export ${DateTime.now().toLocal().toIso8601String().substring(0, 10)}',
      ),
    );
    await root.create(recursive: true);
    final dayRows = await db.query('journal_days', orderBy: 'date_key ASC');
    for (final row in dayRows) {
      final day = JournalDay.fromMap(row);
      final binder = await _database.loadBinderDay(day.dateKey);
      if (binder.entries.isEmpty &&
          binder.checkIn == null &&
          binder.day.gratitude.trim().isEmpty) {
        continue;
      }
      final year = day.dateKey.substring(0, 4);
      final directory = Directory(p.join(root.path, year));
      await directory.create(recursive: true);
      final content = await _renderDay(binder);
      await File(
        p.join(directory.path, '${day.dateKey}.md'),
      ).writeAsString(content, flush: true);
    }
    return root;
  }

  Future<String> _renderDay(BinderDay binder) async {
    final buffer = StringBuffer('# ${binder.day.dateKey}\n\n');
    final mood = binder.checkIn;
    if (mood != null) {
      buffer
        ..writeln('## Mood')
        ..writeln()
        ..writeln('- Tone: ${mood.moodAngle.toStringAsFixed(3)}')
        ..writeln('- Intensity: ${mood.moodIntensity.toStringAsFixed(3)}')
        ..writeln();
    }
    if (binder.day.gratitude.trim().isNotEmpty) {
      buffer
        ..writeln('## Gratitude')
        ..writeln()
        ..writeln(binder.day.gratitude.trim())
        ..writeln();
    }
    for (final entry in binder.entries) {
      final heading = entry.title.trim().isEmpty
          ? entry.type == DayEntryType.daily
                ? 'Daily Journal'
                : 'Additional Entry'
          : entry.title.trim();
      buffer
        ..writeln('## $heading')
        ..writeln()
        ..writeln(entry.content.trim())
        ..writeln();
      final tags = await _database.tagsForEntry(entry.id);
      if (tags.isNotEmpty) {
        buffer.writeln(
          'Tags: ${tags.map((item) => item.tag.name).join(', ')}\n',
        );
      }
      final quietTime = await _database.quietTimeForEntry(entry.id);
      if (quietTime != null &&
          [
            quietTime.observation,
            quietTime.application,
            quietTime.prayer,
          ].any((value) => value.trim().isNotEmpty)) {
        buffer.writeln('### Quiet Time\n');
        _field(buffer, 'Observation', quietTime.observation);
        _field(buffer, 'Application', quietTime.application);
        _field(buffer, 'Prayer', quietTime.prayer);
      }
      final scriptures = await _database.scripturesForEntry(entry.id);
      if (scriptures.isNotEmpty) {
        buffer.writeln('### Scripture references\n');
        for (final scripture in scriptures) {
          buffer.writeln(
            '- ${scripture.reference} (${scripture.translationAbbreviation})'
            '${scripture.copyright.trim().isEmpty ? '' : ' — ${scripture.copyright.trim()}'}',
          );
        }
        buffer.writeln();
      }
    }
    return buffer.toString();
  }

  void _field(StringBuffer buffer, String label, String value) {
    if (value.trim().isEmpty) return;
    buffer
      ..writeln('**$label**')
      ..writeln()
      ..writeln(value.trim())
      ..writeln();
  }
}
