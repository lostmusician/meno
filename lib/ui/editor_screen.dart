import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:file_selector/file_selector.dart';
import 'package:uuid/uuid.dart';

import '../models/journal_entry.dart';
import '../providers/journal_providers.dart';
import '../services/database_service.dart';
import '../services/save_coordinator.dart';
import '../services/smart_bullet_formatter.dart';
import 'binder_screen.dart';
import 'brand_assets.dart';
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
  String? _loadedEntryId;
  String? _loadedDateKey;
  int _scriptureRevision = 0;
  bool _scripturePanelOpen = false;
  bool _journalExitInProgress = false;

  @override
  void initState() {
    super.initState();
    _writingFocus = FocusNode(onKeyEvent: _handleWritingKey);
    HardwareKeyboard.instance.addHandler(_handleGlobalKeyEvent);
    WidgetsBinding.instance.addObserver(this);
    if (widget.autoInitialize) {
      Future.microtask(() async {
        await ref.read(journalControllerProvider.notifier).initialize();
        await _offerFirstRestore();
      });
    }
  }

  Future<void> _offerFirstRestore() async {
    final database = ref.read(databaseServiceProvider);
    if (!await database.shouldOfferFirstRestore() || !mounted) return;
    await database.saveSetting(
      DatabaseService.firstRestorePromptSettingKey,
      'true',
    );
    if (!mounted) return;
    final restore = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Bring your journal into Meno?'),
        content: const Text(
          'If you created a backup with the Meno bridge, restore it now. '
          'You can also restore later from Settings.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Later'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Choose backup'),
          ),
        ],
      ),
    );
    if (restore != true || !mounted) return;
    final file = await openFile(
      acceptedTypeGroups: const [
        XTypeGroup(label: 'Meno backup', extensions: ['meno-backup']),
      ],
    );
    if (file == null) return;
    try {
      await ref.read(backupServiceProvider).restore(File(file.path));
      await ref.read(journalControllerProvider.notifier).initialize();
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Restore failed: $error')));
      }
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

  bool _hasActiveTextComposition() {
    final focusContext = FocusManager.instance.primaryFocus?.context;
    if (focusContext == null) return false;
    final widget = focusContext.widget;
    final editable = widget is EditableText
        ? widget
        : focusContext.findAncestorWidgetOfExactType<EditableText>();
    final composing = editable?.controller.value.composing;
    return composing != null && composing.isValid && !composing.isCollapsed;
  }

  bool _handleGlobalKeyEvent(KeyEvent event) {
    if (event is! KeyDownEvent ||
        event.logicalKey != LogicalKeyboardKey.escape ||
        ref.read(journalControllerProvider).phase != AppPhase.journal ||
        ModalRoute.of(context)?.isCurrent != true ||
        _journalExitInProgress ||
        _hasActiveTextComposition()) {
      return false;
    }
    _handleJournalEscape();
    return true;
  }

  void _handleJournalEscape() {
    if (ModalRoute.of(context)?.isCurrent != true ||
        _journalExitInProgress ||
        _hasActiveTextComposition()) {
      return;
    }
    if (_scripturePanelOpen) {
      setState(() => _scripturePanelOpen = false);
      return;
    }
    _journalExitInProgress = true;
    unawaited(
      (() async {
        final saved = await ref
            .read(saveCoordinatorProvider.notifier)
            .flushAll();
        if (saved) {
          await ref.read(journalControllerProvider.notifier).openBinder();
        }
      })().whenComplete(() => _journalExitInProgress = false),
    );
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    HardwareKeyboard.instance.removeHandler(_handleGlobalKeyEvent);
    _titleController.dispose();
    _contentController.dispose();
    _gratitudeController.dispose();
    _writingFocus.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) {
      unawaited(ref.read(saveCoordinatorProvider.notifier).flushAll());
      return;
    }
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
    final entry = ref.read(journalControllerProvider).selectedEntry;
    if (entry == null) return;
    ref.read(saveCoordinatorProvider.notifier).schedule(
      'organization:${entry.id}',
      () async {
        if (!await ref
            .read(saveCoordinatorProvider.notifier)
            .flush('entry:${entry.id}')) {
          return;
        }
        final current = ref.read(journalControllerProvider);
        final latest = current.entries
            .where((item) => item.id == entry.id)
            .firstOrNull;
        if (current.smartOrganizationEnabled &&
            latest != null &&
            !latest.isEmpty) {
          await ref
              .read(discoveryControllerProvider.notifier)
              .organizeEntry(latest);
        }
      },
    );
  }

  void _onGratitudeChanged(String value) {
    final controller = ref.read(journalControllerProvider.notifier);
    controller.updateGratitude(value);
  }

  void _onMoodChanged(double angle, double intensity) {
    final controller = ref.read(journalControllerProvider.notifier);
    controller.updateMood(angle, intensity);
  }

  Future<void> _selectEntry(String entryId) async {
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
    final saveState = ref.watch(saveCoordinatorProvider);
    _syncControllers(state);
    return Material(
      color: Colors.transparent,
      child: Stack(
        children: [
          Positioned.fill(
            child: AnimatedSwitcher(
              duration: MediaQuery.disableAnimationsOf(context)
                  ? Duration.zero
                  : const Duration(milliseconds: 320),
              child:
                  state.error is UnsupportedDatabaseVersionException ||
                      state.error is DatabaseIntegrityException ||
                      (state.error != null && state.selectedDateKey == null)
                  ? _DatabaseRecoveryView(error: state.error!)
                  : switch (state.phase) {
                      AppPhase.loading => const _LoadingView(
                        key: ValueKey('loading'),
                      ),
                      AppPhase.mood => _MoodView(
                        key: const ValueKey('mood'),
                        state: state,
                        onChanged: _onMoodChanged,
                        onFinish: () async {
                          await ref
                              .read(journalControllerProvider.notifier)
                              .finishMood();
                        },
                        onBinder: ref
                            .read(journalControllerProvider.notifier)
                            .openBinder,
                      ),
                      AppPhase.journal => CallbackShortcuts(
                        bindings: {
                          const SingleActivator(LogicalKeyboardKey.escape):
                              _handleJournalEscape,
                        },
                        child: _JournalSplitView(
                          key: const ValueKey('journal'),
                          scriptureOpen: _scripturePanelOpen,
                          onCloseScripture: () =>
                              setState(() => _scripturePanelOpen = false),
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
                              await ref
                                  .read(journalControllerProvider.notifier)
                                  .addEntry();
                              if (mounted) _writingFocus.requestFocus();
                            },
                            onAddQuietTime: () async {
                              await ref
                                  .read(journalControllerProvider.notifier)
                                  .addQuietTime();
                              if (mounted) _writingFocus.requestFocus();
                            },
                            onOpenScripture: _openScripture,
                            onFinish: () async {
                              await ref
                                  .read(journalControllerProvider.notifier)
                                  .finishEditing();
                            },
                          ),
                        ),
                      ),
                      AppPhase.binder => const BinderScreen(
                        key: ValueKey('binder'),
                      ),
                    },
            ),
          ),
          Positioned(
            right: 12,
            bottom: 10,
            child: _SaveStatusIndicator(state: saveState),
          ),
        ],
      ),
    );
  }
}

class _SaveStatusIndicator extends ConsumerWidget {
  const _SaveStatusIndicator({required this.state});

  final SaveState state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final failed = state.phase == SavePhase.failed;
    return IgnorePointer(
      ignoring: state.phase == SavePhase.saved,
      child: AnimatedOpacity(
        opacity: state.phase == SavePhase.saved ? 0 : 1,
        duration: const Duration(milliseconds: 160),
        child: Material(
          color: failed
              ? Theme.of(context).colorScheme.errorContainer
              : Theme.of(context).colorScheme.surfaceContainerHigh,
          borderRadius: BorderRadius.circular(16),
          child: InkWell(
            borderRadius: BorderRadius.circular(16),
            onTap: failed
                ? () => ref.read(saveCoordinatorProvider.notifier).flushAll()
                : null,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              child: Text(switch (state.phase) {
                SavePhase.saved => 'Saved',
                SavePhase.saving => 'Saving…',
                SavePhase.failed => 'Save failed · Retry',
              }, style: Theme.of(context).textTheme.labelSmall),
            ),
          ),
        ),
      ),
    );
  }
}

class _DatabaseRecoveryView extends ConsumerWidget {
  const _DatabaseRecoveryView({required this.error});

  final Object error;

  @override
  Widget build(BuildContext context, WidgetRef ref) => ColoredBox(
    color: MenoSurfaces.of(context).page,
    child: Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560),
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.health_and_safety_outlined, size: 44),
              const SizedBox(height: 18),
              Text(
                'Your journal was not changed',
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const SizedBox(height: 12),
              Text('$error', textAlign: TextAlign.center),
              const SizedBox(height: 22),
              Wrap(
                spacing: 10,
                children: [
                  OutlinedButton(
                    onPressed: () async {
                      final location = await getSaveLocation(
                        suggestedName: 'Meno recovery.sqlite',
                        acceptedTypeGroups: const [
                          XTypeGroup(
                            label: 'SQLite database',
                            extensions: ['sqlite'],
                          ),
                        ],
                      );
                      if (location == null) return;
                      try {
                        await ref
                            .read(databaseServiceProvider)
                            .copyRawDatabase(File(location.path));
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('Recovery copy saved.'),
                            ),
                          );
                        }
                      } catch (copyError) {
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text('Copy failed: $copyError')),
                          );
                        }
                      }
                    },
                    child: const Text('Export recovery copy'),
                  ),
                  FilledButton(
                    onPressed: () => ref
                        .read(journalControllerProvider.notifier)
                        .initialize(),
                    child: const Text('Retry'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    ),
  );
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
  Widget build(BuildContext context) => ColoredBox(
    color: MenoSurfaces.of(context).glassMode
        ? MenoSurfaces.of(context).page
        : const Color(0xFFF4F0E8),
    child: const Center(
      child: FittedBox(
        fit: BoxFit.scaleDown,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            MenoBrandMark(size: 104),
            SizedBox(height: 18),
            MenoWordmark(width: 142),
            SizedBox(height: 32),
            SizedBox.square(
              dimension: 18,
              child: CircularProgressIndicator(strokeWidth: 1.6),
            ),
          ],
        ),
      ),
    ),
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
      color: Color.lerp(
        MenoSurfaces.of(context).glassMode
            ? MenoSurfaces.of(context).page
            : const Color(0xFFF4F0E8),
        accent,
        .18,
      )!,
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
