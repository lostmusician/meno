part of 'binder_screen.dart';

class _BinderRail extends StatelessWidget {
  const _BinderRail({
    required this.items,
    required this.zoom,
    required this.position,
    required this.selectedIndex,
    required this.pitch,
    required this.compact,
    required this.onSelect,
    super.key,
  });

  final List<_BinderItem> items;
  final BinderZoom zoom;
  final double position;
  final int selectedIndex;
  final double pitch;
  final bool compact;
  final ValueChanged<int> onSelect;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final previewWidth = constraints.maxWidth * (compact ? .84 : .72);
      final previewLeft = (constraints.maxWidth - previewWidth) / 2;
      final previewRight = previewLeft + previewWidth;
      final visibleSlots = ((previewLeft / pitch).ceil() + 2).clamp(3, 9);
      final strips = <Widget>[];
      for (var index = 0; index < items.length; index++) {
        final relative = index - position;
        final distance = relative.abs();
        if (distance < .48 || distance > visibleSlots) continue;
        final older = relative > 0;
        final left = older
            ? previewLeft - distance * pitch - 22
            : previewRight + distance * pitch - 22;
        strips.add(
          Positioned(
            left: left,
            top: 18 + math.min(distance, 6) * 5,
            bottom: 30 + math.min(distance, 6) * 5,
            width: 44,
            child: _PaperEdge(
              item: items[index],
              opacity: (1 - distance * .075).clamp(.32, .88),
              onPressed: () => onSelect(index),
            ),
          ),
        );
      }
      return Stack(
        clipBehavior: Clip.none,
        children: [
          ...strips,
          Positioned(
            left: previewLeft,
            width: previewWidth,
            top: 0,
            bottom: 0,
            child: AnimatedSwitcher(
              duration: MediaQuery.disableAnimationsOf(context)
                  ? Duration.zero
                  : const Duration(milliseconds: 150),
              transitionBuilder: (child, animation) => FadeTransition(
                opacity: animation,
                child: SlideTransition(
                  position: Tween<Offset>(
                    begin: const Offset(.018, 0),
                    end: Offset.zero,
                  ).animate(animation),
                  child: child,
                ),
              ),
              child: _BinderSheet(
                key: ValueKey(
                  '${zoom.name}-${items[selectedIndex].anchorDateKey}',
                ),
                item: items[selectedIndex],
                zoom: zoom,
              ),
            ),
          ),
        ],
      );
    },
  );
}

class _PaperEdge extends StatelessWidget {
  const _PaperEdge({
    required this.item,
    required this.opacity,
    required this.onPressed,
  });

  final _BinderItem item;
  final double opacity;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final mood = _averageMood(item.days);
    final accent = mood == null
        ? const Color(0xFFB8B8AD)
        : MoodPalette.colorFor(mood.$1, mood.$2);
    return Semantics(
      button: true,
      label: 'Open ${item.label}',
      child: Tooltip(
        message: item.label,
        child: InkWell(
          key: Key('binder-strip-${item.anchorDateKey}'),
          onTap: onPressed,
          borderRadius: BorderRadius.circular(11),
          child: Center(
            child: Opacity(
              opacity: opacity,
              child: Container(
                width: 18,
                decoration: BoxDecoration(
                  color: Color.alphaBlend(
                    accent.withValues(alpha: .18),
                    const Color(0xD9FFFCF5),
                  ),
                  borderRadius: BorderRadius.circular(9),
                  border: Border.all(
                    color: accent.withValues(alpha: .68),
                    width: 1.5,
                  ),
                  boxShadow: const [
                    BoxShadow(
                      color: Color(0x21000000),
                      blurRadius: 9,
                      offset: Offset(0, 5),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _MoodReminder extends StatelessWidget {
  const _MoodReminder({required this.onPressed});
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(20, 0, 20, 10),
    child: Material(
      color: const Color(0xFFE4DFC9),
      borderRadius: BorderRadius.circular(16),
      child: ListTile(
        key: const Key('mood-reminder'),
        title: const Text('Your mood can wait until this evening.'),
        trailing: TextButton(
          onPressed: onPressed,
          child: const Text('Add now'),
        ),
      ),
    ),
  );
}

class _BinderSheet extends ConsumerWidget {
  const _BinderSheet({required this.item, required this.zoom, super.key});
  final _BinderItem item;
  final BinderZoom zoom;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final primary = item.days.first;
    final mood = _averageMood(item.days);
    final accent = mood == null
        ? const Color(0xFFB8B8AD)
        : MoodPalette.colorFor(mood.$1, mood.$2);
    final daily = primary.dailyEntry;
    final excerpt = daily?.content.trim() ?? '';
    final additionalCount = item.days.fold<int>(
      0,
      (sum, day) => sum + day.additionalEntries.length,
    );
    final gratitudeCount = item.days
        .where((day) => day.day.gratitude.trim().isNotEmpty)
        .length;
    final discovery = ref.watch(discoveryControllerProvider);
    final itemEntryIds = item.days
        .expand((day) => day.entries)
        .map((entry) => entry.id)
        .toSet();
    final tags = <String>{
      for (final entryId in itemEntryIds)
        for (final entryTag in discovery.entryTags[entryId] ?? const [])
          entryTag.tag.name,
    }.take(3).toList();
    final relatedCount = <String>{
      for (final entryId in itemEntryIds)
        for (final relationship in discovery.relationships[entryId] ?? const [])
          relationship.targetEntryId,
    }.difference(itemEntryIds).length;
    final highContrast = MediaQuery.highContrastOf(context);
    return Semantics(
      label: '${item.label}, ${item.days.length} recorded days',
      child: Container(
        key: Key('binder-sheet-${item.anchorDateKey}'),
        margin: const EdgeInsets.fromLTRB(8, 18, 8, 30),
        padding: const EdgeInsets.all(28),
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          color: highContrast
              ? MenoTheme.paper
              : Color.alphaBlend(
                  accent.withValues(alpha: .12),
                  MenoSurfaces.of(context).glassMode
                      ? MenoSurfaces.of(context).elevated
                      : const Color(0xD9FFFCF5),
                ),
          borderRadius: BorderRadius.circular(28),
          border: highContrast
              ? Border.all(color: accent, width: 3)
              : Border.all(color: accent.withValues(alpha: .48), width: 1.4),
          boxShadow: [
            BoxShadow(
              color: accent.withValues(alpha: .16),
              blurRadius: 34,
              spreadRadius: 2,
            ),
            const BoxShadow(
              color: Color(0x26000000),
              blurRadius: 24,
              offset: Offset(0, 12),
            ),
          ],
        ),
        child: BackdropFilter(
          filter: ImageFilter.blur(
            sigmaX: highContrast ? 0 : 14,
            sigmaY: highContrast ? 0 : 14,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                item.label,
                style: const TextStyle(
                  fontFamily: MenoTheme.serif,
                  fontSize: 27,
                  fontWeight: FontWeight.w600,
                ),
              ),
              if (tags.isNotEmpty) ...[
                const SizedBox(height: 10),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    for (final tag in tags)
                      Chip(
                        visualDensity: VisualDensity.compact,
                        side: BorderSide(color: accent.withValues(alpha: .45)),
                        backgroundColor: accent.withValues(alpha: .11),
                        label: Text(tag),
                      ),
                    if (relatedCount > 0)
                      ActionChip(
                        visualDensity: VisualDensity.compact,
                        avatar: const Icon(Icons.link_rounded, size: 16),
                        label: Text('$relatedCount related'),
                        onPressed: () => showModalBottomSheet<void>(
                          context: context,
                          isScrollControlled: true,
                          showDragHandle: true,
                          builder: (context) =>
                              DiscoverySheet(initialEntryId: daily?.id),
                        ),
                      ),
                  ],
                ),
              ],
              const SizedBox(height: 18),
              if (zoom == BinderZoom.days) ...[
                Expanded(
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      final veryShort = constraints.maxHeight < 150;
                      final short = constraints.maxHeight < 420;
                      final excerptWidget = Text(
                        excerpt.isEmpty ? 'A quiet page.' : excerpt,
                        maxLines: veryShort
                            ? 2
                            : short
                            ? 4
                            : 8,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontFamily: MenoTheme.serif,
                          fontSize: 21,
                          height: 1.5,
                        ),
                      );
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          if (short)
                            Expanded(child: excerptWidget)
                          else
                            excerptWidget,
                          if (!veryShort &&
                              primary.day.gratitude.trim().isNotEmpty) ...[
                            SizedBox(height: short ? 16 : 26),
                            const Text(
                              'GRATEFUL FOR',
                              style: TextStyle(
                                fontSize: 11,
                                letterSpacing: 1.1,
                              ),
                            ),
                            SizedBox(height: short ? 4 : 8),
                            Text(
                              primary.day.gratitude,
                              maxLines: short ? 1 : 3,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontStyle: FontStyle.italic,
                              ),
                            ),
                          ],
                          if (!short && additionalCount > 0) ...[
                            const SizedBox(height: 24),
                            Text(
                              '$additionalCount additional ${additionalCount == 1 ? 'entry' : 'entries'}',
                            ),
                            const SizedBox(height: 6),
                            Text(
                              primary.additionalEntries
                                  .map((entry) => _entryTime(entry.createdAt))
                                  .join('  ·  '),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: Theme.of(
                                  context,
                                ).colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ],
                      );
                    },
                  ),
                ),
                const SizedBox(height: 18),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    FilledButton.tonal(
                      key: const Key('edit-journal'),
                      onPressed: () => ref
                          .read(journalControllerProvider.notifier)
                          .openDay(primary.day.dateKey),
                      child: const Text('Edit journal'),
                    ),
                    TextButton(
                      key: const Key('add-entry'),
                      onPressed: () => ref
                          .read(journalControllerProvider.notifier)
                          .openDay(primary.day.dateKey, createAdditional: true),
                      child: const Text('Add entry'),
                    ),
                    TextButton(
                      key: const Key('edit-mood'),
                      onPressed: () => ref
                          .read(journalControllerProvider.notifier)
                          .openMood(primary.day.dateKey),
                      child: const Text('Edit mood'),
                    ),
                  ],
                ),
              ] else ...[
                Expanded(
                  child: Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 76,
                          height: 76,
                          decoration: BoxDecoration(
                            color: accent,
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(height: 20),
                        Text(
                          '${item.days.length} recorded ${item.days.length == 1 ? 'day' : 'days'}',
                          style: const TextStyle(fontSize: 18),
                        ),
                        const SizedBox(height: 8),
                        Text('$additionalCount additional entries'),
                        const SizedBox(height: 8),
                        Text(
                          '$gratitudeCount with gratitude',
                          style: TextStyle(
                            color: Theme.of(
                              context,
                            ).colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _BinderItem {
  const _BinderItem({required this.label, required this.days});
  final String label;
  final List<BinderDay> days;
  String get anchorDateKey => days.first.day.dateKey;
}

(double, double)? _averageMood(List<BinderDay> days) {
  final moods = days
      .map((day) => day.checkIn)
      .whereType<DailyCheckIn>()
      .toList();
  if (moods.isEmpty) return null;
  final x = moods.fold<double>(
    0,
    (sum, mood) => sum + math.cos(mood.moodAngle * math.pi * 2),
  );
  final y = moods.fold<double>(
    0,
    (sum, mood) => sum + math.sin(mood.moodAngle * math.pi * 2),
  );
  return (
    ((math.atan2(y, x) / (math.pi * 2)) + 1) % 1,
    moods.fold<double>(0, (sum, mood) => sum + mood.moodIntensity) /
        moods.length,
  );
}

String _friendlyDate(String dateKey) {
  final date = localDateFromKey(dateKey);
  return '${_monthName(date.month)} ${date.day}, ${date.year}';
}

String _weekLabel(DateTime date) {
  final monday = date.subtract(Duration(days: date.weekday - DateTime.monday));
  return 'Week of ${_monthName(monday.month)} ${monday.day}';
}

String _entryTime(DateTime value) {
  final time = value.toLocal();
  final hour = time.hour % 12 == 0 ? 12 : time.hour % 12;
  final minute = time.minute.toString().padLeft(2, '0');
  return '$hour:$minute ${time.hour < 12 ? 'AM' : 'PM'}';
}

String _monthName(int month) => const [
  'January',
  'February',
  'March',
  'April',
  'May',
  'June',
  'July',
  'August',
  'September',
  'October',
  'November',
  'December',
][month - 1];
