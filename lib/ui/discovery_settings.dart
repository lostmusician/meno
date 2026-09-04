part of 'discovery_screen.dart';

class MenoSettingsSheet extends ConsumerWidget {
  const MenoSettingsSheet({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final app = ref.watch(journalControllerProvider);
    final embedding = ref.watch(embeddingServiceProvider);
    final discovery = ref.watch(discoveryControllerProvider);
    return SafeArea(
      child: SizedBox(
        height: math.min(MediaQuery.sizeOf(context).height * .82, 680),
        child: ListView(
          padding: const EdgeInsets.fromLTRB(24, 8, 24, 32),
          children: [
            const Text(
              'Meno settings',
              style: TextStyle(
                fontFamily: MenoTheme.serif,
                fontSize: 28,
                fontWeight: FontWeight.w600,
              ),
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
                  await ref
                      .read(journalControllerProvider.notifier)
                      .updateEveningPreference(
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
                await ref
                    .read(journalControllerProvider.notifier)
                    .setSmartOrganizationEnabled(enabled);
                if (!enabled) {
                  ref
                      .read(discoveryControllerProvider.notifier)
                      .cancelIndexing();
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
                unawaited(
                  ref
                      .read(discoveryControllerProvider.notifier)
                      .organizeBackCatalog(),
                );
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
                    onPressed: ref
                        .read(discoveryControllerProvider.notifier)
                        .cancelIndexing,
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
              onChanged: (enabled) => ref
                  .read(journalControllerProvider.notifier)
                  .setQuietTimeLoggingEnabled(enabled),
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
