import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show ScrollCacheExtent;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/journal_entry.dart';
import '../providers/journal_providers.dart';
import '../services/embedding_service.dart';
import '../services/database_service.dart';
import 'brand_assets.dart';
import 'theme_primitives.dart';

part 'discovery_settings.dart';
part 'discovery_connections.dart';

class DiscoverySheet extends ConsumerStatefulWidget {
  const DiscoverySheet({this.initialEntryId, super.key});
  final String? initialEntryId;

  @override
  ConsumerState<DiscoverySheet> createState() => _DiscoverySheetState();
}

class _DiscoverySheetState extends ConsumerState<DiscoverySheet>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs;
  final _query = TextEditingController();
  final _selectedTags = <String>{};
  EntryPurpose? _purpose;
  String? _scriptureBook;
  String? _fromDateKey;
  String? _toDateKey;
  int? _graphWindowDays = 90;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 2, vsync: this);
    Future.microtask(_search);
  }

  @override
  void dispose() {
    _tabs.dispose();
    _query.dispose();
    super.dispose();
  }

  Future<void> _search() => ref
      .read(discoveryControllerProvider.notifier)
      .search(
        JournalSearchQuery(
          text: _query.text,
          tagIds: _selectedTags.toList(),
          purpose: _purpose,
          scriptureBook: _scriptureBook,
          fromDateKey: _fromDateKey,
          toDateKey: _toDateKey,
        ),
      );

  @override
  Widget build(BuildContext context) {
    final discovery = ref.watch(discoveryControllerProvider);
    final binder = ref.watch(binderControllerProvider);
    return SafeArea(
      child: SizedBox(
        height: MediaQuery.sizeOf(context).height * .88,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 12, 8),
              child: Row(
                children: [
                  const Expanded(
                    child: Text(
                      'Find a thread',
                      style: TextStyle(
                        fontFamily: MenoTheme.serif,
                        fontSize: 27,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Close',
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
            ),
            TabBar(
              controller: _tabs,
              tabs: const [
                Tab(text: 'Search & related'),
                Tab(text: 'Connections'),
              ],
            ),
            Expanded(
              child: TabBarView(
                controller: _tabs,
                children: [
                  _SearchPane(
                    query: _query,
                    discovery: discovery,
                    initialEntryId: widget.initialEntryId,
                    selectedTags: _selectedTags,
                    purpose: _purpose,
                    onPurposeChanged: (value) {
                      setState(() => _purpose = value);
                      _search();
                    },
                    onTagChanged: (id, selected) {
                      setState(() {
                        if (selected) {
                          _selectedTags.add(id);
                        } else {
                          _selectedTags.remove(id);
                        }
                      });
                      _search();
                    },
                    onSearch: _search,
                    onAdvancedFilters: _showAdvancedFilters,
                    advancedFilterCount: [
                      _scriptureBook,
                      _fromDateKey,
                      _toDateKey,
                    ].whereType<String>().length,
                    onOpen: _openEntry,
                    onAddTag: _addTag,
                    onRenameTag: _renameTag,
                    onRemoveTag: (entryId, tagId) => ref
                        .read(discoveryControllerProvider.notifier)
                        .removeTag(entryId, tagId),
                  ),
                  _ConnectionsPane(
                    days: binder.days,
                    relationships: discovery.relationships,
                    entryTags: discovery.entryTags,
                    tags: discovery.tags,
                    selectedTags: _selectedTags,
                    windowDays: _graphWindowDays,
                    onWindowChanged: (value) =>
                        setState(() => _graphWindowDays = value),
                    onTagChanged: (id, selected) {
                      setState(() {
                        if (selected) {
                          _selectedTags.add(id);
                        } else {
                          _selectedTags.remove(id);
                        }
                      });
                    },
                    onOpen: _openEntry,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _openEntry(DayEntry entry) async {
    Navigator.pop(context);
    final controller = ref.read(journalControllerProvider.notifier);
    await controller.openDay(entry.dateKey);
    await controller.selectEntry(entry.id);
  }

  Future<void> _addTag(DayEntry entry) async {
    final controller = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Add a tag'),
        content: TextField(
          controller: controller,
          autofocus: true,
          textCapitalization: TextCapitalization.words,
          decoration: const InputDecoration(hintText: 'Family, prayer, work…'),
          onSubmitted: (value) => Navigator.pop(context, value),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text),
            child: const Text('Add'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (name != null && name.trim().isNotEmpty) {
      await ref
          .read(discoveryControllerProvider.notifier)
          .addManualTag(entry.id, name);
    }
  }

  Future<void> _showAdvancedFilters() async {
    final scripture = TextEditingController(text: _scriptureBook ?? '');
    final from = TextEditingController(text: _fromDateKey ?? '');
    final to = TextEditingController(text: _toDateKey ?? '');
    final apply = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Date & Scripture filters'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: scripture,
              textCapitalization: TextCapitalization.characters,
              decoration: const InputDecoration(
                labelText: 'Scripture book code',
                hintText: 'JHN, PSA, ROM…',
              ),
            ),
            TextField(
              controller: from,
              keyboardType: TextInputType.datetime,
              decoration: const InputDecoration(
                labelText: 'From date',
                hintText: 'YYYY-MM-DD',
              ),
            ),
            TextField(
              controller: to,
              keyboardType: TextInputType.datetime,
              decoration: const InputDecoration(
                labelText: 'To date',
                hintText: 'YYYY-MM-DD',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Clear'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Apply'),
          ),
        ],
      ),
    );
    final scriptureValue = scripture.text.trim();
    final fromValue = from.text.trim();
    final toValue = to.text.trim();
    scripture.dispose();
    from.dispose();
    to.dispose();
    if (!mounted || apply == null) return;
    setState(() {
      _scriptureBook = apply && scriptureValue.isNotEmpty
          ? scriptureValue.toUpperCase()
          : null;
      _fromDateKey = apply && fromValue.isNotEmpty ? fromValue : null;
      _toDateKey = apply && toValue.isNotEmpty ? toValue : null;
    });
    await _search();
  }

  Future<void> _renameTag(JournalTag tag) async {
    final controller = TextEditingController(text: tag.name);
    final name = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Rename tag'),
        content: TextField(
          controller: controller,
          autofocus: true,
          textCapitalization: TextCapitalization.words,
          onSubmitted: (value) => Navigator.pop(context, value),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text),
            child: const Text('Rename'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (name != null && name.trim().isNotEmpty && name.trim() != tag.name) {
      await ref
          .read(discoveryControllerProvider.notifier)
          .renameTag(tag.id, name);
      await _search();
    }
  }
}

class _SearchPane extends StatelessWidget {
  const _SearchPane({
    required this.query,
    required this.discovery,
    required this.initialEntryId,
    required this.selectedTags,
    required this.purpose,
    required this.onPurposeChanged,
    required this.onTagChanged,
    required this.onSearch,
    required this.onAdvancedFilters,
    required this.advancedFilterCount,
    required this.onOpen,
    required this.onAddTag,
    required this.onRenameTag,
    required this.onRemoveTag,
  });

  final TextEditingController query;
  final DiscoveryState discovery;
  final String? initialEntryId;
  final Set<String> selectedTags;
  final EntryPurpose? purpose;
  final ValueChanged<EntryPurpose?> onPurposeChanged;
  final void Function(String, bool) onTagChanged;
  final VoidCallback onSearch;
  final VoidCallback onAdvancedFilters;
  final int advancedFilterCount;
  final ValueChanged<DayEntry> onOpen;
  final ValueChanged<DayEntry> onAddTag;
  final ValueChanged<JournalTag> onRenameTag;
  final void Function(String, String) onRemoveTag;

  @override
  Widget build(BuildContext context) {
    final relatedIds = {
      for (final relationship
          in discovery.relationships[initialEntryId] ?? const [])
        relationship.targetEntryId,
    };
    final results = initialEntryId == null
        ? discovery.results
        : [
            ...discovery.results.where(
              (result) => relatedIds.contains(result.entry.id),
            ),
            ...discovery.results.where(
              (result) => !relatedIds.contains(result.entry.id),
            ),
          ];
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 32),
      children: [
        SearchBar(
          key: const Key('journal-search'),
          controller: query,
          hintText: 'Search your writing',
          leading: const Icon(Icons.search),
          trailing: [
            IconButton(
              onPressed: onSearch,
              icon: const Icon(Icons.arrow_forward),
            ),
          ],
          onSubmitted: (_) => onSearch(),
        ),
        const SizedBox(height: 12),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: onAdvancedFilters,
            icon: const Icon(Icons.tune_rounded),
            label: Text(
              advancedFilterCount == 0
                  ? 'Date & Scripture'
                  : 'Date & Scripture ($advancedFilterCount)',
            ),
          ),
        ),
        Wrap(
          spacing: 7,
          runSpacing: 7,
          children: [
            FilterChip(
              label: const Text('Quiet Time'),
              selected: purpose == EntryPurpose.quietTime,
              onSelected: (selected) =>
                  onPurposeChanged(selected ? EntryPurpose.quietTime : null),
            ),
            for (final tag in discovery.tags)
              FilterChip(
                label: Text(tag.name),
                selected: selectedTags.contains(tag.id),
                onSelected: (selected) => onTagChanged(tag.id, selected),
              ),
          ],
        ),
        if (discovery.isLoading) ...[
          const SizedBox(height: 12),
          const LinearProgressIndicator(),
        ],
        if (initialEntryId != null && relatedIds.isNotEmpty) ...[
          const SizedBox(height: 22),
          Text(
            'Related entries',
            style: Theme.of(context).textTheme.titleMedium,
          ),
        ],
        const SizedBox(height: 10),
        for (final result in results)
          Card(
            child: ListTile(
              onTap: () => onOpen(result.entry),
              title: Text(
                result.entry.title.trim().isEmpty
                    ? result.entry.dateKey
                    : result.entry.title,
              ),
              subtitle: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    result.entry.content.trim().isEmpty
                        ? 'A quiet page.'
                        : result.entry.content.trim(),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (result.tags.isNotEmpty)
                    Wrap(
                      spacing: 5,
                      children: [
                        for (final entryTag in result.tags.take(5))
                          InputChip(
                            visualDensity: VisualDensity.compact,
                            label: Text(entryTag.tag.name),
                            tooltip: 'Edit ${entryTag.tag.name}',
                            onPressed: () => onRenameTag(entryTag.tag),
                            onDeleted: () =>
                                onRemoveTag(result.entry.id, entryTag.tag.id),
                          ),
                      ],
                    ),
                ],
              ),
              trailing: IconButton(
                tooltip: 'Add tag',
                onPressed: () => onAddTag(result.entry),
                icon: const Icon(Icons.new_label_outlined),
              ),
            ),
          ),
        if (!discovery.isLoading && results.isEmpty)
          const Padding(
            padding: EdgeInsets.only(top: 40),
            child: Center(child: Text('No matching entries yet.')),
          ),
      ],
    );
  }
}
