part of 'editor_screen.dart';

class _EntryWheel extends StatefulWidget {
  const _EntryWheel({
    required this.entries,
    required this.selectedEntryId,
    required this.writingFocus,
    required this.onSelected,
    required this.onAdd,
    required this.onAddQuietTime,
    required this.quietTimeLogging,
    required this.onFinish,
  });

  final List<DayEntry> entries;
  final String selectedEntryId;
  final FocusNode writingFocus;
  final Future<void> Function(String) onSelected;
  final Future<void> Function() onAdd;
  final Future<void> Function() onAddQuietTime;
  final bool quietTimeLogging;
  final Future<void> Function() onFinish;

  @override
  State<_EntryWheel> createState() => _EntryWheelState();
}

class _EntryWheelState extends State<_EntryWheel> {
  static const _itemExtent = 42.0;

  late FixedExtentScrollController _scrollController;
  bool _hovering = false;
  late int _visualIndex;
  bool _selectionInFlight = false;
  int? _queuedSelection;

  int get _selectedIndex {
    final index = widget.entries.indexWhere(
      (entry) => entry.id == widget.selectedEntryId,
    );
    return index < 0 ? 0 : index;
  }

  @override
  void initState() {
    super.initState();
    _visualIndex = _selectedIndex;
    _scrollController = FixedExtentScrollController(initialItem: _visualIndex);
  }

  @override
  void didUpdateWidget(covariant _EntryWheel oldWidget) {
    super.didUpdateWidget(oldWidget);
    final selectedIndex = _selectedIndex.clamp(0, widget.entries.length - 1);
    if (selectedIndex == _visualIndex &&
        oldWidget.entries.length == widget.entries.length) {
      return;
    }
    _visualIndex = selectedIndex;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scrollController.hasClients) return;
      if (_scrollController.selectedItem != selectedIndex) {
        _scrollController.jumpToItem(selectedIndex);
      }
      setState(() {});
    });
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _commitVisualSelection() async {
    final index = _visualIndex.clamp(0, widget.entries.length - 1);
    if (widget.entries[index].id == widget.selectedEntryId) return;
    if (_selectionInFlight) {
      _queuedSelection = index;
      return;
    }
    _selectionInFlight = true;
    await widget.onSelected(widget.entries[index].id);
    if (!mounted) return;
    _selectionInFlight = false;
    final queued = _queuedSelection;
    _queuedSelection = null;
    if (queued != null && queued != index) {
      _visualIndex = queued.clamp(0, widget.entries.length - 1);
      await _commitVisualSelection();
    }
  }

  Future<void> _moveTo(int index) async {
    final target = index.clamp(0, widget.entries.length - 1);
    if (target == _visualIndex) return;
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    if (reduceMotion) {
      _scrollController.jumpToItem(target);
      setState(() => _visualIndex = target);
    } else {
      await _scrollController.animateToItem(
        target,
        duration: MenoTheme.quickAnimation,
        curve: Curves.easeOutCubic,
      );
    }
    await _commitVisualSelection();
  }

  Key? _positionKey(int index) {
    if (index == _visualIndex) return const Key('entry-wheel-center');
    if (index == _visualIndex - 1) return const Key('entry-wheel-previous');
    if (index == _visualIndex + 1) return const Key('entry-wheel-next');
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final safeIndex = _selectedIndex;
    final selected = widget.entries[safeIndex];
    final compact = MediaQuery.sizeOf(context).width < 600;
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    final highContrast = MediaQuery.highContrastOf(context);
    final duration = reduceMotion ? Duration.zero : MenoTheme.quickAnimation;

    return MouseRegion(
      onEnter: (_) => setState(() => _hovering = true),
      onExit: (_) => setState(() => _hovering = false),
      child: AnimatedBuilder(
        animation: widget.writingFocus,
        builder: (context, child) {
          final faded = widget.writingFocus.hasFocus && !_hovering;
          return AnimatedOpacity(
            duration: duration,
            opacity: highContrast
                ? 1
                : faded
                ? compact
                      ? .72
                      : .34
                : 1,
            child: child,
          );
        },
        child: SizedBox(
          key: const Key('entry-wheel-panel'),
          width: compact ? 220 : 284,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                height: 40,
                child: Row(
                  children: [
                    const Expanded(
                      child: Padding(
                        padding: EdgeInsets.only(left: 12),
                        child: Text(
                          'ENTRIES',
                          style: TextStyle(fontSize: 9, letterSpacing: 1.1),
                        ),
                      ),
                    ),
                    _NewEntryMenu(
                      key: const Key('new-entry'),
                      onAdd: widget.onAdd,
                      onAddQuietTime: widget.quietTimeLogging
                          ? widget.onAddQuietTime
                          : null,
                    ),
                    TextButton(
                      key: const Key('finish-journal'),
                      onPressed: widget.onFinish,
                      style: TextButton.styleFrom(
                        visualDensity: VisualDensity.compact,
                        minimumSize: const Size(48, 40),
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                      ),
                      child: const Text('Home'),
                    ),
                  ],
                ),
              ),
              Semantics(
                container: true,
                label:
                    'Current entry, ${safeIndex + 1} of ${widget.entries.length}',
                value: _entryLabel(selected),
                increasedValue: safeIndex < widget.entries.length - 1
                    ? _entryLabel(widget.entries[safeIndex + 1])
                    : null,
                decreasedValue: safeIndex > 0
                    ? _entryLabel(widget.entries[safeIndex - 1])
                    : null,
                onIncrease: safeIndex < widget.entries.length - 1
                    ? () => _moveTo(safeIndex + 1)
                    : null,
                onDecrease: safeIndex > 0 ? () => _moveTo(safeIndex - 1) : null,
                child: ExcludeSemantics(
                  child: ShaderMask(
                    shaderCallback: (bounds) => const LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Color(0x80FFFFFF),
                        Colors.white,
                        Colors.white,
                        Color(0x80FFFFFF),
                      ],
                      stops: [0, .32, .68, 1],
                    ).createShader(bounds),
                    blendMode: BlendMode.dstIn,
                    child: SizedBox(
                      height: _itemExtent * 3,
                      child: NotificationListener<ScrollNotification>(
                        onNotification: (notification) {
                          if (notification is ScrollEndNotification) {
                            unawaited(_commitVisualSelection());
                          }
                          return false;
                        },
                        child: ListWheelScrollView.useDelegate(
                          key: const Key('entry-wheel'),
                          controller: _scrollController,
                          itemExtent: _itemExtent,
                          physics: const FixedExtentScrollPhysics(),
                          diameterRatio: 2.7,
                          perspective: .002,
                          squeeze: .92,
                          overAndUnderCenterOpacity: 1,
                          onSelectedItemChanged: (index) {
                            if (_visualIndex != index) {
                              setState(() => _visualIndex = index);
                            }
                          },
                          childDelegate: ListWheelChildBuilderDelegate(
                            childCount: widget.entries.length,
                            builder: (context, index) {
                              if (index < 0 || index >= widget.entries.length) {
                                return null;
                              }
                              final entry = widget.entries[index];
                              final isCentered = index == _visualIndex;
                              return AnimatedOpacity(
                                key: _positionKey(index),
                                duration: duration,
                                opacity: isCentered ? 1 : .62,
                                child: AnimatedScale(
                                  duration: duration,
                                  scale: isCentered ? 1 : .92,
                                  child: Padding(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 7,
                                      vertical: 3,
                                    ),
                                    child: DecoratedBox(
                                      decoration: BoxDecoration(
                                        borderRadius: BorderRadius.circular(10),
                                        boxShadow: [
                                          BoxShadow(
                                            color: Colors.black.withValues(
                                              alpha: isCentered ? .09 : .04,
                                            ),
                                            blurRadius: isCentered ? 12 : 7,
                                            offset: const Offset(0, 4),
                                          ),
                                        ],
                                      ),
                                      child: ClipRRect(
                                        borderRadius: BorderRadius.circular(10),
                                        child: BackdropFilter(
                                          filter: ui.ImageFilter.blur(
                                            sigmaX: 9,
                                            sigmaY: 9,
                                          ),
                                          child: DecoratedBox(
                                            decoration: BoxDecoration(
                                              gradient: LinearGradient(
                                                begin: Alignment.topLeft,
                                                end: Alignment.bottomRight,
                                                colors: highContrast
                                                    ? const [
                                                        MenoTheme.paper,
                                                        MenoTheme.paper,
                                                      ]
                                                    : isCentered
                                                    ? const [
                                                        Color(0xB8FFFFFF),
                                                        Color(0x7AF6F0E6),
                                                      ]
                                                    : const [
                                                        Color(0x8CFFFFFF),
                                                        Color(0x52F6F0E6),
                                                      ],
                                              ),
                                              border: Border.all(
                                                color: highContrast
                                                    ? const Color(0x994F4B56)
                                                    : const Color(0x8AFFFFFF),
                                                width: .75,
                                              ),
                                            ),
                                            child: InkWell(
                                              key: Key(
                                                'entry-slip-${entry.id}',
                                              ),
                                              onTap: () => _moveTo(index),
                                              child: Padding(
                                                padding:
                                                    const EdgeInsets.symmetric(
                                                      horizontal: 10,
                                                    ),
                                                child: Row(
                                                  children: [
                                                    SizedBox(
                                                      width: 58,
                                                      child: Text(
                                                        entry.type ==
                                                                DayEntryType
                                                                    .daily
                                                            ? 'DAILY'
                                                            : _entryTime(entry),
                                                        maxLines: 1,
                                                        overflow:
                                                            TextOverflow.fade,
                                                        softWrap: false,
                                                        style: const TextStyle(
                                                          fontSize: 8,
                                                          letterSpacing: .65,
                                                        ),
                                                      ),
                                                    ),
                                                    const SizedBox(width: 7),
                                                    Expanded(
                                                      child: Text(
                                                        _entryExcerpt(entry),
                                                        maxLines: 1,
                                                        overflow: TextOverflow
                                                            .ellipsis,
                                                        style: TextStyle(
                                                          fontSize: 11,
                                                          fontWeight: isCentered
                                                              ? FontWeight.w600
                                                              : FontWeight.w400,
                                                        ),
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                              ),
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              );
                            },
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _NewEntryMenu extends StatelessWidget {
  const _NewEntryMenu({
    required this.onAdd,
    required this.onAddQuietTime,
    super.key,
  });

  final Future<void> Function() onAdd;
  final Future<void> Function()? onAddQuietTime;

  @override
  Widget build(BuildContext context) => MenuAnchor(
    menuChildren: [
      MenuItemButton(
        key: const Key('new-journal-entry'),
        onPressed: onAdd,
        child: const Text('Journal entry'),
      ),
      if (onAddQuietTime != null)
        MenuItemButton(
          key: const Key('new-quiet-time'),
          onPressed: onAddQuietTime,
          child: const Text('Quiet Time'),
        ),
    ],
    builder: (context, controller, child) => TextButton(
      onPressed: onAddQuietTime == null
          ? onAdd
          : () => controller.isOpen ? controller.close() : controller.open(),
      style: TextButton.styleFrom(
        visualDensity: VisualDensity.compact,
        minimumSize: const Size(44, 40),
        padding: const EdgeInsets.symmetric(horizontal: 8),
      ),
      child: const Text('New'),
    ),
  );
}

String _entryLabel(DayEntry entry) {
  if (entry.type == DayEntryType.daily) return 'Daily Journal';
  if (entry.title.trim().isNotEmpty) return entry.title.trim();
  return _entryTime(entry);
}

String _entryExcerpt(DayEntry entry) {
  if (entry.title.trim().isNotEmpty) return entry.title.trim();
  if (entry.content.trim().isNotEmpty) return entry.content.trim();
  return 'Untitled entry';
}

String _entryTime(DayEntry entry) {
  final time = entry.createdAt.toLocal();
  final hour = time.hour == 0
      ? 12
      : time.hour > 12
      ? time.hour - 12
      : time.hour;
  final minute = time.minute.toString().padLeft(2, '0');
  return '$hour:$minute ${time.hour >= 12 ? 'PM' : 'AM'}';
}

String _friendlyDate(String? dateKey) {
  if (dateKey == null) return '';
  final date = localDateFromKey(dateKey);
  const months = [
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
  ];
  return '${months[date.month - 1]} ${date.day}, ${date.year}';
}
