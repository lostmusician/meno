part of 'editor_screen.dart';

class _QuietTimeFields extends ConsumerStatefulWidget {
  const _QuietTimeFields({required this.entryId});
  final String entryId;

  @override
  ConsumerState<_QuietTimeFields> createState() => _QuietTimeFieldsState();
}

class _QuietTimeFieldsState extends ConsumerState<_QuietTimeFields> {
  final _observation = TextEditingController();
  final _application = TextEditingController();
  final _prayer = TextEditingController();
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    Future.microtask(_load);
  }

  Future<void> _load() async {
    final reflection = await ref
        .read(databaseServiceProvider)
        .quietTimeForEntry(widget.entryId);
    if (!mounted) return;
    _observation.text = reflection?.observation ?? '';
    _application.text = reflection?.application ?? '';
    _prayer.text = reflection?.prayer ?? '';
    setState(() => _loaded = true);
  }

  void _changed(_) {
    final reflection = QuietTimeReflection(
      entryId: widget.entryId,
      observation: _observation.text,
      application: _application.text,
      prayer: _prayer.text,
    );
    ref
        .read(saveCoordinatorProvider.notifier)
        .schedule(
          'quiet-time:${widget.entryId}',
          () => ref.read(databaseServiceProvider).saveQuietTime(reflection),
        );
  }

  @override
  void dispose() {
    _observation.dispose();
    _application.dispose();
    _prayer.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_loaded) return const LinearProgressIndicator();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 28),
        const Divider(),
        const SizedBox(height: 14),
        Text(
          'QUIET TIME',
          style: TextStyle(
            fontSize: 11,
            letterSpacing: 1.05,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
        _ReflectionField(
          label: 'Observation',
          hint: 'What stands out in this passage?',
          controller: _observation,
          onChanged: _changed,
        ),
        _ReflectionField(
          label: 'Application',
          hint: 'How might this shape today?',
          controller: _application,
          onChanged: _changed,
        ),
        _ReflectionField(
          label: 'Prayer',
          hint: 'Respond in your own words…',
          controller: _prayer,
          onChanged: _changed,
        ),
      ],
    );
  }
}

class _ReflectionField extends StatelessWidget {
  const _ReflectionField({
    required this.label,
    required this.hint,
    required this.controller,
    required this.onChanged,
  });
  final String label;
  final String hint;
  final TextEditingController controller;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 14),
    child: TextField(
      key: Key('quiet-time-${label.toLowerCase()}'),
      controller: controller,
      onChanged: onChanged,
      inputFormatters: const [SmartBulletTextInputFormatter()],
      minLines: 2,
      maxLines: 6,
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        border: const OutlineInputBorder(),
      ),
    ),
  );
}

class _ScriptureAttachments extends ConsumerStatefulWidget {
  const _ScriptureAttachments({
    required this.entryId,
    required this.revision,
    required this.onOpenScripture,
  });
  final String entryId;
  final int revision;
  final Future<void> Function() onOpenScripture;

  @override
  ConsumerState<_ScriptureAttachments> createState() =>
      _ScriptureAttachmentsState();
}

class _ScriptureAttachmentsState extends ConsumerState<_ScriptureAttachments> {
  late Future<List<ScriptureReference>> _future;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  @override
  void didUpdateWidget(covariant _ScriptureAttachments oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.entryId != widget.entryId ||
        oldWidget.revision != widget.revision) {
      _reload();
    }
  }

  void _reload() {
    _future = ref
        .read(databaseServiceProvider)
        .scripturesForEntry(widget.entryId);
  }

  @override
  Widget build(BuildContext context) {
    final quietTimeLogging = ref.watch(
      journalControllerProvider.select(
        (state) => state.quietTimeLoggingEnabled,
      ),
    );
    if (!quietTimeLogging) return const SizedBox.shrink();
    return FutureBuilder<List<ScriptureReference>>(
      future: _future,
      builder: (context, snapshot) {
        final references = snapshot.data ?? const [];
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (references.isNotEmpty) ...[
              const SizedBox(height: 18),
              for (final reference in references)
                _LinkedScriptureBlock(
                  reference: reference,
                  onRemove: () async {
                    await ref
                        .read(databaseServiceProvider)
                        .deleteScripture(reference.id);
                    setState(_reload);
                  },
                ),
            ],
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                key: const Key('attach-scripture'),
                onPressed: () async {
                  await widget.onOpenScripture();
                  if (mounted) setState(_reload);
                },
                icon: const Icon(Icons.add),
                label: const Text('Attach Scripture'),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _LinkedScriptureBlock extends ConsumerWidget {
  const _LinkedScriptureBlock({
    required this.reference,
    required this.onRemove,
  });

  final ScriptureReference reference;
  final Future<void> Function() onRemove;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = Theme.of(context).colorScheme;
    final request = LinkedPassageRequest.fromReference(reference);
    final passage = ref.watch(linkedPassageProvider(request));
    return Padding(
      key: ValueKey('linked-scripture-${reference.id}'),
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  '${reference.reference} · '
                  '${reference.translationAbbreviation}',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: colors.onSurfaceVariant,
                  ),
                ),
              ),
              IconButton(
                tooltip: 'Remove verse',
                visualDensity: VisualDensity.compact,
                iconSize: 16,
                color: colors.onSurfaceVariant,
                onPressed: onRemove,
                icon: const Icon(Icons.close),
              ),
            ],
          ),
          passage.when(
            data: (value) => Text(
              value.content,
              key: const Key('linked-scripture-text'),
              style: TextStyle(
                fontFamily: MenoTheme.serif,
                fontSize: 16,
                height: 1.5,
                color: colors.onSurfaceVariant.withValues(alpha: .88),
              ),
            ),
            error: (_, _) => Row(
              children: [
                Expanded(
                  child: Text(
                    'Verse text is unavailable. Check your connection.',
                    style: TextStyle(
                      fontSize: 13,
                      color: colors.onSurfaceVariant,
                    ),
                  ),
                ),
                TextButton(
                  key: const Key('retry-linked-scripture'),
                  onPressed: () => retryLinkedPassage(ref, request),
                  child: const Text('Retry'),
                ),
              ],
            ),
            loading: () => const Padding(
              padding: EdgeInsets.symmetric(vertical: 8),
              child: LinearProgressIndicator(minHeight: 2),
            ),
          ),
          if (reference.copyright.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              reference.copyright,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 10,
                color: colors.onSurfaceVariant.withValues(alpha: .72),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
