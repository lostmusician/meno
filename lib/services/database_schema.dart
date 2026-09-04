import 'package:sqflite/sqflite.dart';

const databaseSchemaVersion = 1;
const eveningSettingKey = 'evening_minutes';
const smartOrganizationSettingKey = 'smart_organization_enabled';
const quietTimeLoggingSettingKey = 'quiet_time_logging_enabled';
const preferredBibleSettingKey = 'preferred_bible_id';

Future<void> createDatabaseSchema(Database db) async {
  await db.execute('''
    CREATE TABLE daily_checkins (
      date_key TEXT PRIMARY KEY,
      mood_angle REAL NOT NULL,
      mood_intensity REAL NOT NULL,
      created_at TEXT NOT NULL,
      updated_at TEXT NOT NULL
    )
  ''');
  await db.execute('''
    CREATE TABLE journal_days (
      date_key TEXT PRIMARY KEY,
      gratitude TEXT NOT NULL DEFAULT '',
      created_at TEXT NOT NULL,
      updated_at TEXT NOT NULL
    )
  ''');
  await db.execute('''
    CREATE TABLE day_entries (
      id TEXT PRIMARY KEY,
      date_key TEXT NOT NULL,
      entry_type TEXT NOT NULL CHECK(entry_type IN ('daily', 'additional')),
      entry_purpose TEXT NOT NULL DEFAULT 'freeform',
      title TEXT NOT NULL DEFAULT '',
      content TEXT NOT NULL DEFAULT '',
      created_at TEXT NOT NULL,
      updated_at TEXT NOT NULL,
      FOREIGN KEY(date_key) REFERENCES journal_days(date_key) ON DELETE CASCADE
    )
  ''');
  await db.execute('''
    CREATE UNIQUE INDEX one_daily_entry_per_day
    ON day_entries(date_key) WHERE entry_type = 'daily'
  ''');
  await db.execute('''
    CREATE INDEX day_entries_date_order
    ON day_entries(date_key, entry_type, created_at DESC, id DESC)
  ''');
  await db.execute('''
    CREATE TABLE app_settings (
      setting_key TEXT PRIMARY KEY,
      setting_value TEXT NOT NULL
    )
  ''');
  await db.insert('app_settings', {
    'setting_key': eveningSettingKey,
    'setting_value': '1080',
  });
  await db.insert('app_settings', {
    'setting_key': smartOrganizationSettingKey,
    'setting_value': 'false',
  });
  await db.insert('app_settings', {
    'setting_key': quietTimeLoggingSettingKey,
    'setting_value': 'false',
  });
  await db.insert('app_settings', {
    'setting_key': preferredBibleSettingKey,
    'setting_value': 'NIV',
  });
  await db.execute('''
    CREATE TABLE tags (
      id TEXT PRIMARY KEY,
      name TEXT NOT NULL,
      normalized_name TEXT NOT NULL UNIQUE,
      created_at TEXT NOT NULL,
      updated_at TEXT NOT NULL
    )
  ''');
  await db.execute('''
    CREATE TABLE entry_tags (
      entry_id TEXT NOT NULL,
      tag_id TEXT NOT NULL,
      source TEXT NOT NULL CHECK(source IN ('manual', 'generated')),
      confidence REAL,
      created_at TEXT NOT NULL,
      PRIMARY KEY(entry_id, tag_id),
      FOREIGN KEY(entry_id) REFERENCES day_entries(id) ON DELETE CASCADE,
      FOREIGN KEY(tag_id) REFERENCES tags(id) ON DELETE CASCADE
    )
  ''');
  await db.execute(
    'CREATE INDEX entry_tags_tag ON entry_tags(tag_id, entry_id)',
  );
  await db.execute('''
    CREATE TABLE entry_embeddings (
      entry_id TEXT NOT NULL,
      model_id TEXT NOT NULL,
      content_hash TEXT NOT NULL,
      dimensions INTEGER NOT NULL,
      vector_blob BLOB NOT NULL,
      updated_at TEXT NOT NULL,
      PRIMARY KEY(entry_id, model_id),
      FOREIGN KEY(entry_id) REFERENCES day_entries(id) ON DELETE CASCADE
    )
  ''');
  await db.execute('''
    CREATE TABLE entry_relationships (
      source_entry_id TEXT NOT NULL,
      target_entry_id TEXT NOT NULL,
      score REAL NOT NULL,
      reasons TEXT NOT NULL DEFAULT '',
      model_id TEXT NOT NULL,
      updated_at TEXT NOT NULL,
      PRIMARY KEY(source_entry_id, target_entry_id),
      FOREIGN KEY(source_entry_id) REFERENCES day_entries(id) ON DELETE CASCADE,
      FOREIGN KEY(target_entry_id) REFERENCES day_entries(id) ON DELETE CASCADE
    )
  ''');
  await db.execute(
    'CREATE INDEX relationships_source_score '
    'ON entry_relationships(source_entry_id, score DESC)',
  );
  await db.execute('''
    CREATE TABLE entry_scriptures (
      id TEXT PRIMARY KEY,
      entry_id TEXT NOT NULL,
      bible_id TEXT NOT NULL,
      translation_abbreviation TEXT NOT NULL,
      passage_id TEXT NOT NULL,
      reference TEXT NOT NULL,
      copyright TEXT NOT NULL DEFAULT '',
      created_at TEXT NOT NULL,
      FOREIGN KEY(entry_id) REFERENCES day_entries(id) ON DELETE CASCADE
    )
  ''');
  await db.execute(
    'CREATE INDEX scriptures_entry ON entry_scriptures(entry_id, created_at)',
  );
  await db.execute('''
    CREATE TABLE quiet_time_reflections (
      entry_id TEXT PRIMARY KEY,
      observation TEXT NOT NULL DEFAULT '',
      application TEXT NOT NULL DEFAULT '',
      prayer TEXT NOT NULL DEFAULT '',
      updated_at TEXT NOT NULL,
      FOREIGN KEY(entry_id) REFERENCES day_entries(id) ON DELETE CASCADE
    )
  ''');
  await db.execute('''
    CREATE VIRTUAL TABLE entry_search USING fts5(
      entry_id UNINDEXED,
      date_key UNINDEXED,
      title,
      content,
      gratitude,
      tags,
      quiet_time,
      tokenize = 'unicode61 remove_diacritics 2'
    )
  ''');
}
