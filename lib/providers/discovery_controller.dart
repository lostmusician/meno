import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/journal_entry.dart';
import '../services/database_service.dart';
import '../services/organization_service.dart';
import 'service_providers.dart';

class DiscoveryState {
  const DiscoveryState({
    this.tags = const [],
    this.results = const [],
    this.entryTags = const {},
    this.relationships = const {},
    this.isLoading = false,
    this.indexedEntries = 0,
    this.totalEntries = 0,
    this.error,
  });

  final List<JournalTag> tags;
  final List<JournalSearchResult> results;
  final Map<String, List<EntryTag>> entryTags;
  final Map<String, List<EntryRelationship>> relationships;
  final bool isLoading;
  final int indexedEntries;
  final int totalEntries;
  final Object? error;

  DiscoveryState copyWith({
    List<JournalTag>? tags,
    List<JournalSearchResult>? results,
    Map<String, List<EntryTag>>? entryTags,
    Map<String, List<EntryRelationship>>? relationships,
    bool? isLoading,
    int? indexedEntries,
    int? totalEntries,
    Object? error,
    bool clearError = false,
  }) => DiscoveryState(
    tags: tags ?? this.tags,
    results: results ?? this.results,
    entryTags: entryTags ?? this.entryTags,
    relationships: relationships ?? this.relationships,
    isLoading: isLoading ?? this.isLoading,
    indexedEntries: indexedEntries ?? this.indexedEntries,
    totalEntries: totalEntries ?? this.totalEntries,
    error: clearError ? null : error ?? this.error,
  );
}

class DiscoveryController extends StateNotifier<DiscoveryState> {
  DiscoveryController(this._database, this._tagging, this._relationships)
    : super(const DiscoveryState());

  final DatabaseService _database;
  final TaggingService _tagging;
  final RelationshipService _relationships;
  bool _cancelled = false;

  Future<void> loadForDays(List<BinderDay> days) async {
    try {
      final tags = await _database.allTags();
      final entryTags = Map<String, List<EntryTag>>.from(state.entryTags);
      final relationships = Map<String, List<EntryRelationship>>.from(
        state.relationships,
      );
      for (final day in days) {
        for (final entry in day.entries) {
          entryTags[entry.id] = await _database.tagsForEntry(entry.id);
          relationships[entry.id] = await _database.relationshipsForEntry(
            entry.id,
          );
        }
      }
      state = state.copyWith(
        tags: tags,
        entryTags: entryTags,
        relationships: relationships,
        clearError: true,
      );
    } catch (error) {
      state = state.copyWith(error: error);
    }
  }

  Future<void> search(JournalSearchQuery query) async {
    state = state.copyWith(isLoading: true, clearError: true);
    try {
      final results = await _database.searchEntries(query);
      state = state.copyWith(results: results, isLoading: false);
    } catch (error) {
      state = state.copyWith(isLoading: false, error: error);
    }
  }

  Future<void> addManualTag(String entryId, String name) async {
    final tag = await _database.ensureTag(name);
    await _database.attachTag(
      entryId: entryId,
      tag: tag,
      source: EntryTagSource.manual,
    );
    await _reloadEntry(entryId);
  }

  Future<void> removeTag(String entryId, String tagId) async {
    await _database.detachTag(entryId, tagId);
    await _reloadEntry(entryId);
  }

  Future<void> renameTag(String tagId, String name) async {
    await _tagging.renameTag(tagId, name);
    await _reloadKnownTags();
  }

  Future<void> mergeTags(String sourceTagId, String targetTagId) async {
    await _tagging.mergeTags(sourceTagId, targetTagId);
    await _reloadKnownTags();
  }

  Future<void> _reloadKnownTags() async {
    final entryTags = <String, List<EntryTag>>{};
    for (final entryId in state.entryTags.keys) {
      entryTags[entryId] = await _database.tagsForEntry(entryId);
    }
    state = state.copyWith(
      tags: await _database.allTags(),
      entryTags: entryTags,
    );
  }

  Future<void> organizeEntry(DayEntry entry) async {
    await _tagging.organizeEntry(entry);
    await _relationships.rebuildForEntry(entry.id);
    await _reloadEntry(entry.id);
  }

  Future<void> organizeBackCatalog() async {
    _cancelled = false;
    state = state.copyWith(
      isLoading: true,
      indexedEntries: 0,
      clearError: true,
    );
    try {
      await _tagging.organizeBackCatalog(
        isCancelled: () => _cancelled,
        onProgress: (completed, total) {
          state = state.copyWith(
            indexedEntries: completed,
            totalEntries: total,
          );
        },
      );
      if (!_cancelled) {
        await _relationships.rebuildAll(isCancelled: () => _cancelled);
      }
      state = state.copyWith(tags: await _database.allTags(), isLoading: false);
    } catch (error) {
      state = state.copyWith(isLoading: false, error: error);
    }
  }

  void cancelIndexing() => _cancelled = true;

  Future<void> _reloadEntry(String entryId) async {
    state = state.copyWith(
      tags: await _database.allTags(),
      entryTags: {
        ...state.entryTags,
        entryId: await _database.tagsForEntry(entryId),
      },
      relationships: {
        ...state.relationships,
        entryId: await _database.relationshipsForEntry(entryId),
      },
    );
  }
}

final discoveryControllerProvider =
    StateNotifierProvider<DiscoveryController, DiscoveryState>(
      (ref) => DiscoveryController(
        ref.watch(databaseServiceProvider),
        ref.watch(taggingServiceProvider),
        ref.watch(relationshipServiceProvider),
      ),
    );
