part of 'discovery_screen.dart';

class _ConnectionsPane extends StatelessWidget {
  const _ConnectionsPane({
    required this.days,
    required this.relationships,
    required this.entryTags,
    required this.tags,
    required this.selectedTags,
    required this.windowDays,
    required this.onWindowChanged,
    required this.onTagChanged,
    required this.onOpen,
  });

  final List<BinderDay> days;
  final Map<String, List<EntryRelationship>> relationships;
  final Map<String, List<EntryTag>> entryTags;
  final List<JournalTag> tags;
  final Set<String> selectedTags;
  final int? windowDays;
  final ValueChanged<int?> onWindowChanged;
  final void Function(String, bool) onTagChanged;
  final ValueChanged<DayEntry> onOpen;

  @override
  Widget build(BuildContext context) {
    final newestDate = days.firstOrNull == null
        ? null
        : localDateFromKey(days.first.day.dateKey);
    final cutoff = newestDate == null || windowDays == null
        ? null
        : newestDate.subtract(Duration(days: windowDays!));
    final entries = days
        .expand((day) => day.entries)
        .where((entry) => !entry.isEmpty)
        .where(
          (entry) =>
              cutoff == null ||
              !localDateFromKey(entry.dateKey).isBefore(cutoff),
        )
        .where((entry) {
          final ids = (entryTags[entry.id] ?? const [])
              .map((entryTag) => entryTag.tag.id)
              .toSet();
          return selectedTags.every(ids.contains);
        })
        .take(40)
        .toList();
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
          child: Wrap(
            spacing: 7,
            runSpacing: 7,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              DropdownButton<int?>(
                value: windowDays,
                items: const [
                  DropdownMenuItem(value: 30, child: Text('Last 30 days')),
                  DropdownMenuItem(value: 90, child: Text('Last 90 days')),
                  DropdownMenuItem(value: null, child: Text('All dates')),
                ],
                onChanged: onWindowChanged,
              ),
              for (final tag in tags)
                FilterChip(
                  label: Text(tag.name),
                  selected: selectedTags.contains(tag.id),
                  onSelected: (selected) => onTagChanged(tag.id, selected),
                ),
            ],
          ),
        ),
        Expanded(
          child: entries.isEmpty
              ? const Center(child: Text('No connections match these filters.'))
              : Padding(
                  padding: const EdgeInsets.all(20),
                  child: CustomPaint(
                    key: const Key('connections-graph'),
                    painter: _ConnectionsPainter(
                      entries,
                      relationships,
                      Theme.of(context).colorScheme,
                    ),
                    child: const SizedBox.expand(),
                  ),
                ),
        ),
        if (entries.isNotEmpty)
          SizedBox(
            height: 150,
            child: ListView.separated(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
              scrollDirection: Axis.horizontal,
              itemCount: entries.length,
              separatorBuilder: (_, _) => const SizedBox(width: 8),
              itemBuilder: (context, index) => ActionChip(
                label: Text(
                  entries[index].title.trim().isEmpty
                      ? entries[index].dateKey
                      : entries[index].title,
                ),
                onPressed: () => onOpen(entries[index]),
              ),
            ),
          ),
      ],
    );
  }
}

class _ConnectionsPainter extends CustomPainter {
  _ConnectionsPainter(this.entries, this.relationships, this.colors);
  final List<DayEntry> entries;
  final Map<String, List<EntryRelationship>> relationships;
  final ColorScheme colors;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final radius = math.min(size.width, size.height) * .38;
    final points = <String, Offset>{};
    for (var index = 0; index < entries.length; index++) {
      final angle = -math.pi / 2 + index / entries.length * math.pi * 2;
      points[entries[index].id] =
          center + Offset(math.cos(angle), math.sin(angle)) * radius;
    }
    final edgePaint = Paint()
      ..color = colors.primary.withValues(alpha: .22)
      ..strokeWidth = 1.3;
    for (final entry in entries) {
      for (final relationship in (relationships[entry.id] ?? const []).take(
        3,
      )) {
        final from = points[entry.id];
        final to = points[relationship.targetEntryId];
        if (from != null && to != null) canvas.drawLine(from, to, edgePaint);
      }
    }
    final nodePaint = Paint()..color = colors.primaryContainer;
    for (final point in points.values) {
      canvas.drawCircle(point, 6, nodePaint);
    }
  }

  @override
  bool shouldRepaint(covariant _ConnectionsPainter oldDelegate) =>
      oldDelegate.entries != entries ||
      oldDelegate.relationships != relationships;
}
