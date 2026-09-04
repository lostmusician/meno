part of 'editor_screen.dart';

class _JournalView extends StatefulWidget {
  const _JournalView({
    required this.state,
    required this.titleController,
    required this.contentController,
    required this.gratitudeController,
    required this.scriptureRevision,
    required this.writingFocus,
    required this.onEntryChanged,
    required this.onGratitudeChanged,
    required this.onSelectEntry,
    required this.onAddEntry,
    required this.onAddQuietTime,
    required this.onOpenScripture,
    required this.onFinish,
    super.key,
  });

  final JournalAppState state;
  final TextEditingController titleController;
  final TextEditingController contentController;
  final TextEditingController gratitudeController;
  final int scriptureRevision;
  final FocusNode writingFocus;
  final VoidCallback onEntryChanged;
  final ValueChanged<String> onGratitudeChanged;
  final Future<void> Function(String) onSelectEntry;
  final Future<void> Function() onAddEntry;
  final Future<void> Function() onAddQuietTime;
  final Future<void> Function() onOpenScripture;
  final Future<void> Function() onFinish;

  @override
  State<_JournalView> createState() => _JournalViewState();
}

class _JournalViewState extends State<_JournalView> {
  void _moveSelection(int delta) {
    final index = widget.state.entries.indexWhere(
      (entry) => entry.id == widget.state.selectedEntryId,
    );
    final next = (index + delta).clamp(0, widget.state.entries.length - 1);
    if (next != index) {
      unawaited(widget.onSelectEntry(widget.state.entries[next].id));
    }
  }

  void _resumeWriting() => widget.writingFocus.requestFocus();

  @override
  Widget build(BuildContext context) {
    final selected = widget.state.selectedEntry;
    if (selected == null) return const _LoadingView();
    final viewportWidth = MediaQuery.sizeOf(context).width;
    final compact = viewportWidth < 600;
    final wheelOverlapsWritingColumn = viewportWidth < 1380;
    final pagePadding = compact ? 20.0 : 48.0;
    final shortcuts = <ShortcutActivator, VoidCallback>{
      const SingleActivator(LogicalKeyboardKey.arrowUp, alt: true): () =>
          _moveSelection(-1),
      const SingleActivator(LogicalKeyboardKey.arrowDown, alt: true): () =>
          _moveSelection(1),
    };
    final duration = MediaQuery.disableAnimationsOf(context)
        ? Duration.zero
        : MenoTheme.quickAnimation;

    return CallbackShortcuts(
      bindings: shortcuts,
      child: Focus(
        autofocus: true,
        child: ColoredBox(
          key: const Key('full-page-journal'),
          color: MenoTheme.paper,
          child: SafeArea(
            child: Stack(
              children: [
                Positioned.fill(
                  child: LayoutBuilder(
                    builder: (context, constraints) => AnimatedSwitcher(
                      duration: duration,
                      transitionBuilder: (child, animation) => FadeTransition(
                        opacity: animation,
                        child: SlideTransition(
                          position: Tween<Offset>(
                            begin: const Offset(0, .018),
                            end: Offset.zero,
                          ).animate(animation),
                          child: child,
                        ),
                      ),
                      child: SingleChildScrollView(
                        key: ValueKey(selected.id),
                        padding: EdgeInsets.fromLTRB(
                          pagePadding,
                          wheelOverlapsWritingColumn ? 176 : 82,
                          pagePadding,
                          48,
                        ),
                        child: ConstrainedBox(
                          constraints: BoxConstraints(
                            minHeight: math.max(0, constraints.maxHeight - 130),
                          ),
                          child: Align(
                            alignment: Alignment.topCenter,
                            child: ConstrainedBox(
                              constraints: const BoxConstraints(maxWidth: 780),
                              child: GestureDetector(
                                behavior: HitTestBehavior.translucent,
                                onTap: _resumeWriting,
                                child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.stretch,
                                  children: [
                                    TextField(
                                      key: const Key('entry-title'),
                                      controller: widget.titleController,
                                      onTap: _resumeWriting,
                                      onChanged: (_) => widget.onEntryChanged(),
                                      decoration: InputDecoration(
                                        border: InputBorder.none,
                                        hintText:
                                            selected.type == DayEntryType.daily
                                            ? 'Daily journal'
                                            : _entryTime(selected),
                                      ),
                                      style: const TextStyle(
                                        fontFamily: MenoTheme.serif,
                                        fontSize: 19,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                    const Divider(),
                                    TextField(
                                      key: const Key('journal-editor'),
                                      controller: widget.contentController,
                                      focusNode: widget.writingFocus,
                                      autofocus: true,
                                      onTap: _resumeWriting,
                                      onChanged: (_) => widget.onEntryChanged(),
                                      // Keep the gratitude footer in the initial
                                      // viewport, then let this field expand with
                                      // the journal as the user writes.
                                      minLines: compact ? 6 : 5,
                                      maxLines: null,
                                      keyboardType: TextInputType.multiline,
                                      decoration: const InputDecoration(
                                        border: InputBorder.none,
                                        hintText: 'Start where you are…',
                                      ),
                                      style: const TextStyle(
                                        fontFamily: MenoTheme.serif,
                                        fontSize: 24,
                                        height: 1.55,
                                      ),
                                    ),
                                    if (widget.state.quietTimeLoggingEnabled)
                                      _ScriptureAttachments(
                                        entryId: selected.id,
                                        revision: widget.scriptureRevision,
                                        onOpenScripture: widget.onOpenScripture,
                                      ),
                                    if (selected.type ==
                                        DayEntryType.daily) ...[
                                      const SizedBox(height: 42),
                                      const Divider(),
                                      const SizedBox(height: 18),
                                      Text(
                                        'WHAT ARE YOU GRATEFUL FOR TODAY?',
                                        style: TextStyle(
                                          fontSize: 11,
                                          letterSpacing: 1.05,
                                          color: Theme.of(
                                            context,
                                          ).colorScheme.onSurfaceVariant,
                                        ),
                                      ),
                                      TextField(
                                        key: const Key('gratitude-editor'),
                                        controller: widget.gratitudeController,
                                        onChanged: widget.onGratitudeChanged,
                                        minLines: 2,
                                        maxLines: 5,
                                        decoration: const InputDecoration(
                                          border: InputBorder.none,
                                          hintText: 'A small thing is enough…',
                                        ),
                                      ),
                                    ],
                                    if (selected.purpose ==
                                        EntryPurpose.quietTime)
                                      _QuietTimeFields(entryId: selected.id),
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
                Positioned(
                  left: compact ? 14 : 22,
                  top: 14,
                  child: AnimatedBuilder(
                    animation: widget.writingFocus,
                    builder: (context, child) => AnimatedOpacity(
                      duration: duration,
                      opacity: widget.writingFocus.hasFocus
                          ? compact
                                ? .68
                                : .34
                          : .82,
                      child: child,
                    ),
                    child: Text(
                      _friendlyDate(widget.state.selectedDateKey),
                      key: const Key('floating-journal-date'),
                      style: const TextStyle(
                        fontFamily: MenoTheme.serif,
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
                Positioned(
                  right: compact ? 8 : 16,
                  top: 8,
                  child: _EntryWheel(
                    entries: widget.state.entries,
                    selectedEntryId: selected.id,
                    writingFocus: widget.writingFocus,
                    onSelected: widget.onSelectEntry,
                    onAdd: widget.onAddEntry,
                    onAddQuietTime: widget.onAddQuietTime,
                    quietTimeLogging: widget.state.quietTimeLoggingEnabled,
                    onFinish: widget.onFinish,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
