part of 'discovery_screen.dart';

class MenoSettingsSheet extends ConsumerWidget {
  const MenoSettingsSheet({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final app = ref.watch(journalControllerProvider);
    final embedding = ref.watch(embeddingServiceProvider);
    final discovery = ref.watch(discoveryControllerProvider);
    final journalController = ref.read(journalControllerProvider.notifier);
    final discoveryController = ref.read(discoveryControllerProvider.notifier);
    return SafeArea(
      child: SizedBox(
        height: math.min(MediaQuery.sizeOf(context).height * .82, 680),
        child: ListView(
          scrollCacheExtent: const ScrollCacheExtent.pixels(1200),
          padding: const EdgeInsets.fromLTRB(24, 8, 24, 32),
          children: [
            const Row(
              children: [
                MenoBrandMark(size: 30),
                SizedBox(width: 12),
                Expanded(
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: Text(
                      'Meno settings',
                      style: TextStyle(
                        fontFamily: MenoTheme.serif,
                        fontSize: 28,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 18),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.schedule_rounded),
              title: const Text('Evening begins'),
              subtitle: Text(
                TimeOfDay(
                  hour: app.eveningPreference.hour,
                  minute: app.eveningPreference.minute,
                ).format(context),
              ),
              onTap: () async {
                final selected = await showTimePicker(
                  context: context,
                  initialTime: TimeOfDay(
                    hour: app.eveningPreference.hour,
                    minute: app.eveningPreference.minute,
                  ),
                );
                if (selected != null) {
                  await journalController.updateEveningPreference(
                    selected.hour * 60 + selected.minute,
                  );
                }
              },
            ),
            const Divider(),
            SwitchListTile.adaptive(
              key: const Key('smart-organization-setting'),
              contentPadding: EdgeInsets.zero,
              title: const Text('Smart Organization'),
              subtitle: const Text(
                'Suggest editable tags and connect related entries on this device.',
              ),
              value: app.smartOrganizationEnabled,
              onChanged: (enabled) async {
                await journalController.setSmartOrganizationEnabled(enabled);
                if (!enabled) {
                  discoveryController.cancelIndexing();
                  return;
                }
                try {
                  await embedding.downloadModel();
                } catch (_) {
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text(
                          'Semantic model unavailable. Local keyphrase tags still work.',
                        ),
                      ),
                    );
                  }
                }
                unawaited(discoveryController.organizeBackCatalog());
              },
            ),
            StreamBuilder<EmbeddingStatus>(
              stream: embedding.status,
              builder: (context, snapshot) {
                final status = snapshot.data;
                if (status?.availability != EmbeddingAvailability.downloading) {
                  return const SizedBox.shrink();
                }
                return Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: LinearProgressIndicator(value: status?.progress),
                );
              },
            ),
            FutureBuilder<bool>(
              future: embedding.isAvailable(),
              builder: (context, snapshot) {
                if (snapshot.data != true || app.smartOrganizationEnabled) {
                  return const SizedBox.shrink();
                }
                return Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    onPressed: embedding.deleteModel,
                    icon: const Icon(Icons.delete_outline_rounded),
                    label: const Text('Remove semantic model'),
                  ),
                );
              },
            ),
            if (discovery.isLoading) ...[
              LinearProgressIndicator(
                value: discovery.totalEntries == 0
                    ? null
                    : discovery.indexedEntries / discovery.totalEntries,
              ),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      discovery.totalEntries == 0
                          ? 'Organizing your journal…'
                          : '${discovery.indexedEntries} of ${discovery.totalEntries} entries organized',
                    ),
                  ),
                  TextButton(
                    onPressed: discoveryController.cancelIndexing,
                    child: const Text('Cancel'),
                  ),
                ],
              ),
            ],
            const Divider(),
            SwitchListTile.adaptive(
              key: const Key('quiet-time-logging-setting'),
              contentPadding: EdgeInsets.zero,
              title: const Text('Quiet Time logging'),
              subtitle: const Text(
                'Create Quiet Time entries and attach Scripture when you want it.',
              ),
              value: app.quietTimeLoggingEnabled,
              onChanged: journalController.setQuietTimeLoggingEnabled,
            ),
            if (app.quietTimeLoggingEnabled)
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.menu_book_outlined),
                title: const Text('Preferred Bible'),
                subtitle: const Text(
                  'Choose an available translation in the Scripture reader',
                ),
                trailing: Text(app.preferredBibleId),
              ),
            const Divider(),
            const SizedBox(height: 8),
            Text('WRITING', style: Theme.of(context).textTheme.labelSmall),
            const SizedBox(height: 8),
            Row(
              children: [
                const Expanded(
                  child: ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(Icons.text_fields_rounded),
                    title: Text('Journal text size'),
                    subtitle: Text('Changes the main writing area'),
                  ),
                ),
                SegmentedButton<EditorTextSize>(
                  key: const Key('editor-text-size-setting'),
                  showSelectedIcon: false,
                  segments: [
                    for (final size in EditorTextSize.values)
                      ButtonSegment(
                        value: size,
                        label: Text(size.label.substring(0, 1)),
                        tooltip: '${size.label} · ${size.fontSize.toInt()} pt',
                      ),
                  ],
                  selected: {app.editorTextSize},
                  onSelectionChanged: (selection) =>
                      journalController.setEditorTextSize(selection.first),
                ),
              ],
            ),
            if (Theme.of(context).platform == TargetPlatform.macOS)
              SwitchListTile.adaptive(
                key: const Key('glass-mode-setting'),
                contentPadding: EdgeInsets.zero,
                secondary: const Icon(Icons.blur_on_rounded),
                title: const Text('Glass Mode'),
                subtitle: const Text('Use a softly tinted, translucent window'),
                value: app.glassModeEnabled,
                onChanged: journalController.setGlassModeEnabled,
              ),
            const Divider(),
            const SizedBox(height: 8),
            Text('DATA SAFETY', style: Theme.of(context).textTheme.labelSmall),
            FutureBuilder<String?>(
              future: ref
                  .read(databaseServiceProvider)
                  .setting(DatabaseService.lastExternalBackupSettingKey),
              builder: (context, snapshot) => ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.shield_outlined),
                title: const Text('Create backup'),
                subtitle: Text(
                  snapshot.data == null || snapshot.data!.isEmpty
                      ? 'No external backup recorded yet'
                      : 'Last backup: ${snapshot.data}',
                ),
                onTap: () => _createExternalBackup(context, ref),
              ),
            ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.restore_rounded),
              title: const Text('Restore backup'),
              subtitle: const Text('Validate and replace this journal safely'),
              onTap: () => _restoreBackup(context, ref),
            ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.description_outlined),
              title: const Text('Export readable Markdown'),
              subtitle: const Text('One readable file for each journal day'),
              onTap: () => _exportMarkdown(context, ref),
            ),
            FutureBuilder<File?>(
              future: ref
                  .read(legacyImportServiceProvider)
                  .discoverSottoDatabase(),
              builder: (context, snapshot) {
                final source = snapshot.data;
                if (source == null) return const SizedBox.shrink();
                return ListTile(
                  key: const Key('import-sotto-history'),
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.move_to_inbox_outlined),
                  title: const Text('Import Sotto history'),
                  subtitle: const Text(
                    'Archive both databases, then merge without overwriting',
                  ),
                  onTap: () => _importSotto(context, ref, source),
                );
              },
            ),
            const SizedBox(height: 12),
            Text(
              'Journal analysis stays on this device. Online Bible requests never include journal text.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }
}

Future<void> _createExternalBackup(BuildContext context, WidgetRef ref) async {
  if (!await ref.read(saveCoordinatorProvider.notifier).flushAll()) {
    if (!context.mounted) return;
    _notice(context, 'Fix the current save error before creating a backup.');
    return;
  }
  final date = DateTime.now().toLocal().toIso8601String().substring(0, 10);
  final location = await getSaveLocation(
    suggestedName: 'Meno $date.meno-backup',
    acceptedTypeGroups: const [
      XTypeGroup(label: 'Meno backup', extensions: ['meno-backup']),
    ],
  );
  if (location == null) return;
  try {
    final result = await ref
        .read(backupServiceProvider)
        .createBackup(File(location.path));
    await ref
        .read(databaseServiceProvider)
        .saveSetting(
          DatabaseService.lastExternalBackupSettingKey,
          result.manifest.createdAt.toLocal().toString(),
        );
    if (context.mounted) _notice(context, 'Backup verified and saved.');
  } catch (error) {
    if (context.mounted) _notice(context, 'Backup failed: $error');
  }
}

Future<void> _restoreBackup(BuildContext context, WidgetRef ref) async {
  final source = await openFile(
    acceptedTypeGroups: const [
      XTypeGroup(label: 'Meno backup', extensions: ['meno-backup']),
    ],
  );
  if (source == null || !context.mounted) return;
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Restore this backup?'),
      content: const Text(
        'Meno will preserve a safety snapshot of the current journal, validate '
        'the backup, and then replace the current journal.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, true),
          child: const Text('Restore'),
        ),
      ],
    ),
  );
  if (confirmed != true) return;
  try {
    if (!await ref.read(saveCoordinatorProvider.notifier).flushAll()) {
      throw StateError('Pending changes could not be saved.');
    }
    await ref.read(backupServiceProvider).restore(File(source.path));
    await ref.read(journalControllerProvider.notifier).initialize();
    if (context.mounted) {
      Navigator.maybePop(context);
      _notice(context, 'Backup restored and verified.');
    }
  } catch (error) {
    if (context.mounted) _notice(context, 'Restore failed: $error');
  }
}

Future<void> _exportMarkdown(BuildContext context, WidgetRef ref) async {
  final destination = await getDirectoryPath(
    confirmButtonText: 'Export journal',
  );
  if (destination == null) return;
  try {
    if (!await ref.read(saveCoordinatorProvider.notifier).flushAll()) {
      throw StateError('Pending changes could not be saved.');
    }
    final result = await ref
        .read(markdownExportServiceProvider)
        .exportTo(Directory(destination));
    if (context.mounted) {
      _notice(context, 'Markdown exported to ${result.path}.');
    }
  } catch (error) {
    if (context.mounted) _notice(context, 'Export failed: $error');
  }
}

Future<void> _importSotto(
  BuildContext context,
  WidgetRef ref,
  File source,
) async {
  try {
    if (!await ref.read(saveCoordinatorProvider.notifier).flushAll()) {
      throw StateError('Pending changes could not be saved.');
    }
    final result = await ref
        .read(legacyImportServiceProvider)
        .importSotto(source);
    await ref.read(journalControllerProvider.notifier).initialize();
    if (context.mounted) {
      _notice(
        context,
        result.skippedBecauseAlreadyImported
            ? 'This Sotto database was already imported.'
            : 'Imported ${result.importedEntries} entries. Create a Meno backup next.',
      );
    }
  } catch (error) {
    if (context.mounted) _notice(context, 'Sotto import failed: $error');
  }
}

void _notice(BuildContext context, String message) {
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
}
