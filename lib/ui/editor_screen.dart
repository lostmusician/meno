import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../models/journal_entry.dart';
import '../providers/journal_providers.dart';
import 'binder_screen.dart';
import 'mood_dial.dart';
import 'scripture_screen.dart';
import 'theme_primitives.dart';

part 'editor_journal_canvas.dart';
part 'editor_quiet_time.dart';
part 'editor_entry_wheel.dart';

class EditorScreen extends ConsumerStatefulWidget {
  const EditorScreen({this.autoInitialize = true, super.key});

  final bool autoInitialize;

  @override
  ConsumerState<EditorScreen> createState() => _EditorScreenState();
}

class _EditorScreenState extends ConsumerState<EditorScreen>
    with WidgetsBindingObserver {
  final _titleController = TextEditingController();
  final _contentController = TextEditingController();
  final _gratitudeController = TextEditingController();
  late final FocusNode _writingFocus;
  Timer? _entryDebounce;
  Timer? _gratitudeDebounce;
  Timer? _moodDebounce;
  String? _loadedEntryId;
  String? _loadedDateKey;
  int _scriptureRevision = 0;
  bool _scripturePanelOpen = false;

  @override
  void initState() {
    super.initState();
    _writingFocus = FocusNode(onKeyEvent: _handleWritingKey);
    WidgetsBinding.instance.addObserver(this);
    if (widget.autoInitialize) {
      Future.microtask(
        () => ref.read(journalControllerProvider.notifier).initialize(),
      );
    }
  }

  KeyEventResult _handleWritingKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent || !HardwareKeyboard.instance.isAltPressed) {
      return KeyEventResult.ignored;
    }
    final delta = switch (event.logicalKey) {
      LogicalKeyboardKey.arrowUp => -1,
      LogicalKeyboardKey.arrowDown => 1,
      _ => 0,
    };
    if (delta == 0) return KeyEventResult.ignored;
    final state = ref.read(journalControllerProvider);
    final index = state.entries.indexWhere(
      (entry) => entry.id == state.selectedEntryId,
    );
    final next = (index + delta).clamp(0, state.entries.length - 1);
    if (next != index) unawaited(_selectEntry(state.entries[next].id));
    return KeyEventResult.handled;
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _entryDebounce?.cancel();
    _gratitudeDebounce?.cancel();
    _moodDebounce?.cancel();
    _titleController.dispose();
    _contentController.dispose();
    _gratitudeController.dispose();
    _writingFocus.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) return;
    final current = ref.read(journalControllerProvider);
    if (current.phase == AppPhase.binder) {
      ref.read(journalControllerProvider.notifier).initialize();
    }
  }

  void _syncControllers(JournalAppState state) {
    final entry = state.selectedEntry;
    if (entry != null && _loadedEntryId != entry.id) {
      _loadedEntryId = entry.id;
      _titleController.text = entry.title;
      _contentController.value = TextEditingValue(
        text: entry.content,
        selection: TextSelection.collapsed(offset: entry.content.length),
      );
    }
    if (state.day != null && _loadedDateKey != state.day!.dateKey) {
      _loadedDateKey = state.day!.dateKey;
      _gratitudeController.text = state.day!.gratitude;
    }
  }

  void _onEntryChanged() {
    final controller = ref.read(journalControllerProvider.notifier);
    controller.updateEntry(
      title: _titleController.text,
      content: _contentController.text,
    );
    _entryDebounce?.cancel();
    _entryDebounce = Timer(MenoTheme.saveDebounce, () async {
      if (!await controller.saveCurrentEntry()) return;
      final current = ref.read(journalControllerProvider);
      final entry = current.selectedEntry;
      if (current.smartOrganizationEnabled && entry != null && !entry.isEmpty) {
        await ref
            .read(discoveryControllerProvider.notifier)
            .organizeEntry(entry);
      }
    });
  }

  void _onGratitudeChanged(String value) {
    final controller = ref.read(journalControllerProvider.notifier);
    controller.updateGratitude(value);
    _gratitudeDebounce?.cancel();
    _gratitudeDebounce = Timer(
      MenoTheme.saveDebounce,
      controller.saveGratitude,
    );
  }

  void _onMoodChanged(double angle, double intensity) {
    final controller = ref.read(journalControllerProvider.notifier);
    controller.updateMood(angle, intensity);
    _moodDebounce?.cancel();
    _moodDebounce = Timer(MenoTheme.saveDebounce, controller.saveMood);
  }

  Future<void> _selectEntry(String entryId) async {
    _entryDebounce?.cancel();
    await ref.read(journalControllerProvider.notifier).selectEntry(entryId);
    if (mounted) _writingFocus.requestFocus();
  }

  bool _usesDesktopScripturePanel(BuildContext context) =>
      switch (Theme.of(context).platform) {
        TargetPlatform.macOS ||
        TargetPlatform.windows ||
        TargetPlatform.linux => true,
        _ => false,
      };

  Future<void> _openScripture() async {
    if (_usesDesktopScripturePanel(context)) {
      setState(() => _scripturePanelOpen = true);
      return;
    }
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      clipBehavior: Clip.antiAlias,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (sheetContext) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: .92,
        minChildSize: .48,
        maxChildSize: .97,
        snap: true,
        snapSizes: const [.72, .92],
        builder: (context, scrollController) => ScriptureWorkspace(
          scrollController: scrollController,
          onClose: () => Navigator.pop(sheetContext),
          onAdd: (selection) async {
            await _saveScriptureSelection(selection);
            if (sheetContext.mounted) Navigator.pop(sheetContext);
          },
        ),
      ),
    );
  }

  Future<void> _saveScriptureSelection(ScriptureSelection selection) async {
    if (!mounted) return;
    final entry = ref.read(journalControllerProvider).selectedEntry;
    if (entry == null) return;
    final passage = selection.passage;
    await ref
        .read(databaseServiceProvider)
        .saveScripture(
          ScriptureReference(
            id: const Uuid().v4(),
            entryId: entry.id,
            bibleId: passage.version.id,
            translationAbbreviation: passage.version.abbreviation,
            passageId: passage.id,
            reference: passage.reference,
            copyright: passage.version.copyright,
          ),
        );
    cacheLinkedPassage(passage);
    setState(() => _scriptureRevision += 1);
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(journalControllerProvider);
    _syncControllers(state);
    return Material(
      color: Colors.transparent,
      child: AnimatedSwitcher(
        duration: MediaQuery.disableAnimationsOf(context)
            ? Duration.zero
            : const Duration(milliseconds: 320),
        child: switch (state.phase) {
          AppPhase.loading => const _LoadingView(key: ValueKey('loading')),
          AppPhase.mood => _MoodView(
            key: const ValueKey('mood'),
            state: state,
            onChanged: _onMoodChanged,
            onFinish: () async {
              _moodDebounce?.cancel();
              await ref.read(journalControllerProvider.notifier).finishMood();
            },
            onBinder: ref.read(journalControllerProvider.notifier).openBinder,
          ),
          AppPhase.journal => _JournalSplitView(
            key: const ValueKey('journal'),
            scriptureOpen: _scripturePanelOpen,
            onCloseScripture: () => setState(() => _scripturePanelOpen = false),
            onAddScripture: _saveScriptureSelection,
            journal: _JournalView(
              key: const ValueKey('journal-body'),
              state: state,
              titleController: _titleController,
              contentController: _contentController,
              gratitudeController: _gratitudeController,
              scriptureRevision: _scriptureRevision,
              writingFocus: _writingFocus,
              onEntryChanged: _onEntryChanged,
              onGratitudeChanged: _onGratitudeChanged,
              onSelectEntry: _selectEntry,
              onAddEntry: () async {
                _entryDebounce?.cancel();
                await ref.read(journalControllerProvider.notifier).addEntry();
                if (mounted) _writingFocus.requestFocus();
              },
              onAddQuietTime: () async {
                _entryDebounce?.cancel();
                await ref
                    .read(journalControllerProvider.notifier)
                    .addQuietTime();
                if (mounted) _writingFocus.requestFocus();
              },
              onOpenScripture: _openScripture,
              onFinish: () async {
                _entryDebounce?.cancel();
                _gratitudeDebounce?.cancel();
                await ref
                    .read(journalControllerProvider.notifier)
                    .finishEditing();
              },
            ),
          ),
          AppPhase.binder => const BinderScreen(key: ValueKey('binder')),
        },
      ),
    );
  }
}

class _JournalSplitView extends StatefulWidget {
  const _JournalSplitView({
    required this.journal,
    required this.scriptureOpen,
    required this.onCloseScripture,
    required this.onAddScripture,
    super.key,
  });

  final Widget journal;
  final bool scriptureOpen;
  final VoidCallback onCloseScripture;
  final Future<void> Function(ScriptureSelection) onAddScripture;

  @override
  State<_JournalSplitView> createState() => _JournalSplitViewState();
}

class _JournalSplitViewState extends State<_JournalSplitView> {
  late bool _showPanelContent = widget.scriptureOpen;

  @override
  void didUpdateWidget(covariant _JournalSplitView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.scriptureOpen && !_showPanelContent) {
      setState(() => _showPanelContent = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    return LayoutBuilder(
      builder: (context, constraints) {
        final panelWidth = math.min(
          520.0,
          math.max(320.0, constraints.maxWidth * .42),
        );
        return Row(
          children: [
            Expanded(child: widget.journal),
            TweenAnimationBuilder<double>(
              key: const Key('desktop-scripture-panel'),
              tween: Tween(end: widget.scriptureOpen ? 1 : 0),
              duration: reduceMotion
                  ? Duration.zero
                  : const Duration(milliseconds: 240),
              curve: Curves.easeOutCubic,
              onEnd: () {
                if (!widget.scriptureOpen && _showPanelContent) {
                  setState(() => _showPanelContent = false);
                }
              },
              builder: (context, progress, child) => ClipRect(
                child: Align(
                  alignment: Alignment.centerRight,
                  widthFactor: progress,
                  child: Transform.translate(
                    offset: Offset(panelWidth * (1 - progress), 0),
                    child: SizedBox(width: panelWidth, child: child),
                  ),
                ),
              ),
              child: !_showPanelContent
                  ? const SizedBox.shrink()
                  : DecoratedBox(
                      decoration: BoxDecoration(
                        border: Border(
                          left: BorderSide(
                            color: Theme.of(context).dividerColor,
                          ),
                        ),
                        boxShadow: const [
                          BoxShadow(
                            color: Color(0x18000000),
                            blurRadius: 18,
                            offset: Offset(-4, 0),
                          ),
                        ],
                      ),
                      child: ScriptureWorkspace(
                        onClose: widget.onCloseScripture,
                        onAdd: widget.onAddScripture,
                      ),
                    ),
            ),
          ],
        );
      },
    );
  }
}

class _LoadingView extends StatelessWidget {
  const _LoadingView({super.key});

  @override
  Widget build(BuildContext context) => const ColoredBox(
    color: Color(0xFFF4F0E8),
    child: Center(child: CircularProgressIndicator()),
  );
}

class _MoodView extends StatelessWidget {
  const _MoodView({
    required this.state,
    required this.onChanged,
    required this.onFinish,
    required this.onBinder,
    super.key,
  });

  final JournalAppState state;
  final void Function(double, double) onChanged;
  final Future<void> Function() onFinish;
  final Future<void> Function() onBinder;

  @override
  Widget build(BuildContext context) {
    final angle = state.checkIn?.moodAngle ?? .12;
    final intensity = state.checkIn?.moodIntensity ?? .55;
    final accent = MoodPalette.colorFor(angle, intensity);
    return ColoredBox(
      color: Color.lerp(const Color(0xFFF4F0E8), accent, .18)!,
      child: SafeArea(
        child: Stack(
          children: [
            Positioned(
              top: 12,
              left: 14,
              child: IconButton(
                key: const Key('mood-binder'),
                tooltip: 'Open binder',
                onPressed: onBinder,
                icon: const Icon(Icons.menu_book_outlined),
              ),
            ),
            Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(28),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 620),
                  child: Column(
                    children: [
                      Text(
                        _friendlyDate(state.selectedDateKey),
                        style: const TextStyle(fontSize: 13, letterSpacing: 1),
                      ),
                      const SizedBox(height: 12),
                      const Text(
                        'How did today feel?',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontFamily: MenoTheme.serif,
                          fontSize: 38,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 28),
                      MoodDial(
                        angle: angle,
                        intensity: intensity,
                        onChanged: onChanged,
                      ),
                      const SizedBox(height: 24),
                      FilledButton(
                        key: const Key('finish-mood'),
                        onPressed: onFinish,
                        style: FilledButton.styleFrom(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 28,
                            vertical: 16,
                          ),
                        ),
                        child: const Text('Save mood'),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
