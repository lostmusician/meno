import 'dart:ui' as ui;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/journal_entry.dart';
import '../providers/journal_providers.dart';
import '../services/bible_service.dart';
import 'theme_primitives.dart';

class ScriptureSelection {
  const ScriptureSelection(this.verses) : assert(verses.length > 0);

  final List<BiblePassage> verses;

  BibleVersion get version => verses.first.version;
  String get passageId => verses.length == 1
      ? verses.first.id
      : '${verses.first.id}-${verses.last.id}';
  String get content => verses.map((verse) => verse.content).join(' ');

  String get reference {
    final first = verses.first.reference;
    if (verses.length == 1) return first;
    return '$first–${verses.last.id.split('.').last}';
  }

  BiblePassage get passage => BiblePassage(
    id: passageId,
    reference: reference,
    content: content,
    version: version,
  );
}

class ScriptureWorkspace extends ConsumerStatefulWidget {
  const ScriptureWorkspace({
    this.onClose,
    this.onAdd,
    this.scrollController,
    super.key,
  });

  final VoidCallback? onClose;
  final Future<void> Function(ScriptureSelection)? onAdd;
  final ScrollController? scrollController;

  @override
  ConsumerState<ScriptureWorkspace> createState() => _ScriptureWorkspaceState();
}

class _ScriptureWorkspaceState extends ConsumerState<ScriptureWorkspace> {
  static const _initialVersion = BibleVersion(
    id: 'NIV',
    abbreviation: 'NIV',
    title: 'New International Version',
    copyright: '',
  );

  List<BibleVersion> _versions = const [];
  List<BibleBook> _books = const [];
  List<int> _chapters = const [1];
  List<BiblePassage> _results = const [];
  BibleVersion _version = _initialVersion;
  BibleBook? _book;
  int _chapter = 1;
  int? _selectionAnchor;
  int? _selectionExtent;
  bool _loading = true;
  bool _adding = false;
  bool _selectorsManuallyExpanded = false;
  double _scrollOffset = 0;
  Object? _error;
  final _fallbackScrollController = ScrollController();

  BibleProvider get _provider => ref.read(youVersionBibleProvider);
  ScrollController get _scrollController =>
      widget.scrollController ?? _fallbackScrollController;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_handleScroll);
    Future.microtask(_initialize);
  }

  @override
  void didUpdateWidget(covariant ScriptureWorkspace oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.scrollController == widget.scrollController) return;
    (oldWidget.scrollController ?? _fallbackScrollController).removeListener(
      _handleScroll,
    );
    _scrollController.addListener(_handleScroll);
  }

  @override
  void dispose() {
    _scrollController.removeListener(_handleScroll);
    _fallbackScrollController.dispose();
    super.dispose();
  }

  void _handleScroll() {
    final offset = _scrollController.hasClients
        ? _scrollController.offset.clamp(0, double.infinity).toDouble()
        : 0.0;
    if ((offset - _scrollOffset).abs() < .5) return;
    final scrollingDown = offset > _scrollOffset;
    setState(() {
      _scrollOffset = offset;
      if (offset <= 24 || scrollingDown) {
        _selectorsManuallyExpanded = false;
      }
    });
  }

  bool _usesMobileChrome(BuildContext context) =>
      switch (Theme.of(context).platform) {
        TargetPlatform.iOS || TargetPlatform.android => true,
        _ => false,
      };

  double get _selectorCollapseProgress =>
      ((_scrollOffset - 24) / 96).clamp(0, 1);

  void _expandSelectors() {
    setState(() => _selectorsManuallyExpanded = true);
  }

  void _settleSelectorsAfterSelection() {
    if (_scrollOffset > 24) {
      setState(() => _selectorsManuallyExpanded = false);
    }
  }

  Future<void> _initialize() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final remote = ref.read(youVersionBibleProvider);
      if (!remote.isConfigured) {
        throw StateError(
          'Add a YouVersion app key to browse ESV, NIV, ERV, and NKJV.',
        );
      }
      final versions = await remote.versions();
      if (versions.isEmpty) {
        throw StateError(
          'None of ESV, NIV, ERV, or NKJV is licensed to this app key.',
        );
      }
      final preferredId = ref.read(journalControllerProvider).preferredBibleId;
      final selected = versions.firstWhere(
        (version) =>
            version.id == preferredId ||
            version.abbreviation.toUpperCase() == preferredId.toUpperCase(),
        orElse: () => versions.firstWhere(
          (version) => version.abbreviation.toUpperCase() == 'NIV',
          orElse: () => versions.first,
        ),
      );
      final books = await remote.books(selected);
      final chapters = books.isEmpty
          ? const [1]
          : await remote.chapters(selected, books.first);
      if (!mounted) return;
      setState(() {
        _versions = versions;
        _version = selected;
        _books = books;
        _chapters = chapters.isEmpty ? const [1] : chapters;
        _book = books.firstOrNull;
      });
      await _loadChapter();
    } catch (error) {
      if (mounted) setState(() => _error = error);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _changeVersion(BibleVersion version) async {
    _settleSelectorsAfterSelection();
    setState(() {
      _version = version;
      _loading = true;
      _error = null;
    });
    try {
      await ref
          .read(journalControllerProvider.notifier)
          .setPreferredBibleId(version.abbreviation.toUpperCase());
      final books = await _provider.books(version);
      final chapters = books.isEmpty
          ? const [1]
          : await _provider.chapters(version, books.first);
      if (!mounted) return;
      setState(() {
        _books = books;
        _chapters = chapters.isEmpty ? const [1] : chapters;
        _book = books.firstOrNull;
        _chapter = 1;
      });
      await _loadChapter();
    } catch (error) {
      if (mounted) setState(() => _error = error);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _changeBook(BibleBook book) async {
    _settleSelectorsAfterSelection();
    setState(() {
      _book = book;
      _chapter = 1;
      _loading = true;
      _error = null;
    });
    try {
      final chapters = await _provider.chapters(_version, book);
      if (!mounted) return;
      setState(() => _chapters = chapters.isEmpty ? const [1] : chapters);
      await _loadChapter();
    } catch (error) {
      if (mounted) setState(() => _error = error);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _loadChapter() async {
    final book = _book;
    if (book == null) return;
    setState(() {
      _loading = true;
      _error = null;
      _selectionAnchor = null;
      _selectionExtent = null;
    });
    try {
      final passages = await _provider.chapterVerses(_version, book, _chapter);
      if (passages.isEmpty) {
        throw StateError('No verse text was returned for this chapter.');
      }
      if (!mounted) return;
      setState(() => _results = passages);
    } catch (error) {
      if (mounted) setState(() => _error = error);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _selectVerse(int index) {
    setState(() {
      final anchor = _selectionAnchor;
      final extent = _selectionExtent;
      if (anchor == null || extent == null) {
        _selectionAnchor = index;
        _selectionExtent = index;
      } else if (anchor == extent && index == anchor) {
        _selectionAnchor = null;
        _selectionExtent = null;
      } else if (index >= _selectionStart && index <= _selectionEnd) {
        _selectionAnchor = index;
        _selectionExtent = index;
      } else {
        _selectionExtent = index;
      }
    });
  }

  int get _selectionStart => _selectionAnchor! < _selectionExtent!
      ? _selectionAnchor!
      : _selectionExtent!;
  int get _selectionEnd => _selectionAnchor! > _selectionExtent!
      ? _selectionAnchor!
      : _selectionExtent!;

  ScriptureSelection? get _selection {
    if (_selectionAnchor == null || _selectionExtent == null) return null;
    return ScriptureSelection(
      _results.sublist(_selectionStart, _selectionEnd + 1),
    );
  }

  void _close() {
    if (widget.onClose != null) {
      widget.onClose!();
    } else {
      Navigator.maybePop(context);
    }
  }

  Future<void> _addSelection() async {
    final selection = _selection;
    if (selection == null) return;
    if (widget.onAdd != null) {
      setState(() => _adding = true);
      try {
        await widget.onAdd!(selection);
      } finally {
        if (mounted) setState(() => _adding = false);
      }
    } else {
      Navigator.pop(context, selection);
    }
  }

  void _changeChapter(int value) {
    _settleSelectorsAfterSelection();
    setState(() => _chapter = value);
    _loadChapter();
  }

  @override
  Widget build(BuildContext context) {
    final mobile = _usesMobileChrome(context);
    final collapseProgress = _selectorsManuallyExpanded
        ? 0.0
        : _selectorCollapseProgress;
    final reader = _ReaderBody(
      mobile: mobile,
      loading: _loading,
      error: _error,
      scrollController: _scrollController,
      scrollOffset: _scrollOffset,
      book: _book,
      chapter: _chapter,
      results: _results,
      selectionAnchor: _selectionAnchor,
      selectionStart: _selectionAnchor == null ? null : _selectionStart,
      selectionEnd: _selectionExtent == null ? null : _selectionEnd,
      onVerseTap: _selectVerse,
      onRetry: _initialize,
    );
    return Material(
      color: MenoSurfaces.of(context).paper,
      child: SafeArea(
        top: false,
        child: mobile
            ? Stack(
                children: [
                  Positioned.fill(child: reader),
                  Align(
                    alignment: Alignment.topCenter,
                    child: _MobileReaderChrome(onClose: _close),
                  ),
                  Align(
                    alignment: Alignment.bottomCenter,
                    child: _MobileReaderDock(
                      versions: _versions,
                      version: _version,
                      books: _books,
                      book: _book,
                      chapters: _chapters,
                      chapter: _chapter,
                      enabled: !_loading,
                      collapseProgress: collapseProgress,
                      selection: _selection,
                      adding: _adding,
                      onVersionChanged: _changeVersion,
                      onBookChanged: _changeBook,
                      onChapterChanged: _changeChapter,
                      onExpand: _expandSelectors,
                      onAdd: _selection == null || _adding
                          ? null
                          : _addSelection,
                    ),
                  ),
                ],
              )
            : Column(
                children: [
                  _ReaderHeader(
                    versions: _versions,
                    version: _version,
                    books: _books,
                    book: _book,
                    chapters: _chapters,
                    chapter: _chapter,
                    enabled: !_loading,
                    onVersionChanged: _changeVersion,
                    onBookChanged: _changeBook,
                    onChapterChanged: _changeChapter,
                    onClose: _close,
                  ),
                  Expanded(child: reader),
                  _ScriptureActionBar(
                    version: _version,
                    selection: _selection,
                    adding: _adding,
                    onAdd: _selection == null || _adding ? null : _addSelection,
                  ),
                ],
              ),
      ),
    );
  }
}

class _ReaderBody extends StatelessWidget {
  const _ReaderBody({
    required this.mobile,
    required this.loading,
    required this.error,
    required this.scrollController,
    required this.scrollOffset,
    required this.book,
    required this.chapter,
    required this.results,
    required this.selectionAnchor,
    required this.selectionStart,
    required this.selectionEnd,
    required this.onVerseTap,
    required this.onRetry,
  });

  final bool mobile;
  final bool loading;
  final Object? error;
  final ScrollController scrollController;
  final double scrollOffset;
  final BibleBook? book;
  final int chapter;
  final List<BiblePassage> results;
  final int? selectionAnchor;
  final int? selectionStart;
  final int? selectionEnd;
  final ValueChanged<int> onVerseTap;
  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) {
    final fadeOpacity = (scrollOffset / 32).clamp(0, 1).toDouble();
    return Stack(
      children: [
        Positioned.fill(
          child: error != null
              ? _ReaderError(error: error!, onRetry: onRetry)
              : SingleChildScrollView(
                  key: const Key('scripture-verse-list'),
                  controller: scrollController,
                  padding: EdgeInsets.fromLTRB(
                    24,
                    mobile ? 66 : 24,
                    24,
                    mobile ? 196 : 40,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${book?.name ?? ''} $chapter'.trim(),
                        style: const TextStyle(
                          fontFamily: MenoTheme.serif,
                          fontSize: 26,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 18),
                      _ContinuousChapter(
                        passages: results,
                        selectionStart: selectionAnchor == null
                            ? null
                            : selectionStart,
                        selectionEnd: selectionEnd,
                        onVerseTap: onVerseTap,
                      ),
                    ],
                  ),
                ),
        ),
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          height: mobile ? 58 : 36,
          child: IgnorePointer(
            child: AnimatedOpacity(
              key: const Key('scripture-top-fade'),
              opacity: fadeOpacity,
              duration: MediaQuery.disableAnimationsOf(context)
                  ? Duration.zero
                  : MenoTheme.quickAnimation,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      MenoSurfaces.of(context).paper,
                      const Color(0x00FFFCF5),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
        if (loading)
          Positioned(
            top: mobile ? 42 : 0,
            left: 0,
            right: 0,
            child: const LinearProgressIndicator(minHeight: 2),
          ),
      ],
    );
  }
}

class _MobileReaderChrome extends StatelessWidget {
  const _MobileReaderChrome({required this.onClose});

  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) => Center(
    heightFactor: 1,
    child: Semantics(
      button: true,
      label: 'Close Scripture',
      child: Tooltip(
        message: 'Close Scripture',
        child: GestureDetector(
          key: const Key('scripture-drag-handle'),
          behavior: HitTestBehavior.translucent,
          onTap: onClose,
          child: SizedBox(
            width: 72,
            height: 42,
            child: Center(
              child: Container(
                width: 38,
                height: 5,
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.outlineVariant,
                  borderRadius: BorderRadius.circular(99),
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

class _ReaderHeader extends StatelessWidget {
  const _ReaderHeader({
    required this.versions,
    required this.version,
    required this.books,
    required this.book,
    required this.chapters,
    required this.chapter,
    required this.enabled,
    required this.onVersionChanged,
    required this.onBookChanged,
    required this.onChapterChanged,
    required this.onClose,
  });

  final List<BibleVersion> versions;
  final BibleVersion version;
  final List<BibleBook> books;
  final BibleBook? book;
  final List<int> chapters;
  final int chapter;
  final bool enabled;
  final ValueChanged<BibleVersion> onVersionChanged;
  final ValueChanged<BibleBook> onBookChanged;
  final ValueChanged<int> onChapterChanged;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      border: Border(
        bottom: BorderSide(
          color: Theme.of(
            context,
          ).colorScheme.outlineVariant.withValues(alpha: .7),
        ),
      ),
    ),
    child: Padding(
      padding: const EdgeInsets.fromLTRB(14, 10, 6, 10),
      child: Row(
        children: [
          Expanded(
            child: _ReaderSelectors(
              versions: versions,
              version: version,
              books: books,
              book: book,
              chapters: chapters,
              chapter: chapter,
              enabled: enabled,
              openUpward: false,
              onVersionChanged: onVersionChanged,
              onBookChanged: onBookChanged,
              onChapterChanged: onChapterChanged,
            ),
          ),
          const SizedBox(width: 2),
          IconButton(
            key: const Key('close-scripture'),
            tooltip: 'Close Scripture',
            onPressed: onClose,
            icon: const Icon(Icons.close, size: 20),
          ),
        ],
      ),
    ),
  );
}

class _ReaderSelectors extends StatelessWidget {
  const _ReaderSelectors({
    required this.versions,
    required this.version,
    required this.books,
    required this.book,
    required this.chapters,
    required this.chapter,
    required this.enabled,
    required this.openUpward,
    required this.onVersionChanged,
    required this.onBookChanged,
    required this.onChapterChanged,
    super.key,
  });

  final List<BibleVersion> versions;
  final BibleVersion version;
  final List<BibleBook> books;
  final BibleBook? book;
  final List<int> chapters;
  final int chapter;
  final bool enabled;
  final bool openUpward;
  final ValueChanged<BibleVersion> onVersionChanged;
  final ValueChanged<BibleBook> onBookChanged;
  final ValueChanged<int> onChapterChanged;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      Expanded(
        flex: 2,
        child: _GlassDropdown<BibleBook>(
          key: const Key('scripture-book-picker'),
          value: book,
          hint: 'Book',
          items: books,
          label: (item) => item.name,
          menuWidth: 220,
          enabled: enabled && books.isNotEmpty,
          openUpward: openUpward,
          onChanged: onBookChanged,
        ),
      ),
      const SizedBox(width: 6),
      Expanded(
        child: _GlassDropdown<int>(
          key: const Key('scripture-chapter-picker'),
          value: chapters.contains(chapter) ? chapter : null,
          hint: 'Chapter',
          items: chapters,
          label: (item) => '$item',
          menuWidth: 96,
          enabled: enabled && chapters.isNotEmpty,
          openUpward: openUpward,
          onChanged: onChapterChanged,
        ),
      ),
      const SizedBox(width: 6),
      Expanded(
        child: _GlassDropdown<BibleVersion>(
          key: const Key('scripture-version-picker'),
          value: versions.contains(version) ? version : null,
          hint: version.abbreviation,
          items: versions,
          label: (item) => item.abbreviation,
          menuWidth: 150,
          enabled: enabled && versions.isNotEmpty,
          openUpward: openUpward,
          onChanged: onVersionChanged,
        ),
      ),
    ],
  );
}

class _GlassDropdown<T> extends StatefulWidget {
  const _GlassDropdown({
    required this.value,
    required this.hint,
    required this.items,
    required this.label,
    required this.menuWidth,
    required this.enabled,
    required this.openUpward,
    required this.onChanged,
    super.key,
  });

  final T? value;
  final String hint;
  final List<T> items;
  final String Function(T) label;
  final double menuWidth;
  final bool enabled;
  final bool openUpward;
  final ValueChanged<T> onChanged;

  @override
  State<_GlassDropdown<T>> createState() => _GlassDropdownState<T>();
}

class _GlassDropdownState<T> extends State<_GlassDropdown<T>> {
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final highContrast = MediaQuery.highContrastOf(context);
    final label = widget.value == null
        ? widget.hint
        : widget.label(widget.value as T);
    final menuColor = highContrast
        ? colors.surface
        : colors.surface.withValues(alpha: .94);
    final estimatedMenuHeight =
        (widget.items.length * kMinInteractiveDimension + 12).clamp(0.0, 360.0);
    return MenuAnchor(
      alignmentOffset: Offset(
        0,
        widget.openUpward ? -estimatedMenuHeight - 6 : 6,
      ),
      style: MenuStyle(
        alignment: widget.openUpward
            ? AlignmentDirectional.topStart
            : AlignmentDirectional.bottomStart,
        backgroundColor: WidgetStatePropertyAll(menuColor),
        surfaceTintColor: const WidgetStatePropertyAll(Colors.transparent),
        shadowColor: WidgetStatePropertyAll(
          colors.shadow.withValues(alpha: .18),
        ),
        elevation: const WidgetStatePropertyAll(12),
        padding: const WidgetStatePropertyAll(
          EdgeInsets.symmetric(vertical: 6),
        ),
        maximumSize: WidgetStatePropertyAll(Size(widget.menuWidth + 24, 360)),
        side: WidgetStatePropertyAll(
          BorderSide(color: colors.outlineVariant.withValues(alpha: .7)),
        ),
        shape: WidgetStatePropertyAll(
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        ),
      ),
      onOpen: () => setState(() => _open = true),
      onClose: () => setState(() => _open = false),
      menuChildren: [
        for (final item in widget.items)
          MenuItemButton(
            closeOnActivate: true,
            onPressed: widget.enabled ? () => widget.onChanged(item) : null,
            leadingIcon: item == widget.value
                ? const Icon(Icons.check, size: 17)
                : const SizedBox(width: 17),
            child: Tooltip(
              message: widget.label(item),
              child: SizedBox(
                width: widget.menuWidth,
                child: Text(
                  widget.label(item),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ),
          ),
      ],
      builder: (context, controller, child) => Semantics(
        button: true,
        enabled: widget.enabled,
        expanded: _open,
        label: label,
        child: Tooltip(
          message: label,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: BackdropFilter(
              filter: ui.ImageFilter.blur(sigmaX: 12, sigmaY: 12),
              child: Material(
                color: highContrast
                    ? colors.surface
                    : colors.surfaceContainerHighest.withValues(alpha: .58),
                child: InkWell(
                  onTap: widget.enabled
                      ? () => controller.isOpen
                            ? controller.close()
                            : controller.open()
                      : null,
                  child: Container(
                    height: 38,
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    decoration: BoxDecoration(
                      border: Border.all(
                        color: colors.outlineVariant.withValues(alpha: .72),
                      ),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            label,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: widget.enabled
                                  ? colors.onSurface
                                  : colors.onSurface.withValues(alpha: .38),
                            ),
                          ),
                        ),
                        const SizedBox(width: 4),
                        AnimatedRotation(
                          turns: _open ? .5 : 0,
                          duration: MediaQuery.disableAnimationsOf(context)
                              ? Duration.zero
                              : MenoTheme.quickAnimation,
                          child: Icon(
                            Icons.keyboard_arrow_down_rounded,
                            size: 18,
                            color: widget.enabled
                                ? colors.onSurfaceVariant
                                : colors.onSurface.withValues(alpha: .3),
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
    );
  }
}

class _MobileReaderDock extends StatelessWidget {
  const _MobileReaderDock({
    required this.versions,
    required this.version,
    required this.books,
    required this.book,
    required this.chapters,
    required this.chapter,
    required this.enabled,
    required this.collapseProgress,
    required this.selection,
    required this.adding,
    required this.onVersionChanged,
    required this.onBookChanged,
    required this.onChapterChanged,
    required this.onExpand,
    required this.onAdd,
  });

  final List<BibleVersion> versions;
  final BibleVersion version;
  final List<BibleBook> books;
  final BibleBook? book;
  final List<int> chapters;
  final int chapter;
  final bool enabled;
  final double collapseProgress;
  final ScriptureSelection? selection;
  final bool adding;
  final ValueChanged<BibleVersion> onVersionChanged;
  final ValueChanged<BibleBook> onBookChanged;
  final ValueChanged<int> onChapterChanged;
  final VoidCallback onExpand;
  final VoidCallback? onAdd;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final reducedMotion = MediaQuery.disableAnimationsOf(context);
    final collapsed = collapseProgress >= .92;
    return ClipRect(
      child: BackdropFilter(
        filter: ui.ImageFilter.blur(sigmaX: 18, sigmaY: 18),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: colors.surface.withValues(alpha: .74),
            border: Border(
              top: BorderSide(
                color: colors.outlineVariant.withValues(alpha: .72),
              ),
            ),
            boxShadow: [
              BoxShadow(
                color: colors.shadow.withValues(alpha: .08),
                blurRadius: 18,
                offset: const Offset(0, -4),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: EdgeInsets.fromLTRB(
                  14,
                  ui.lerpDouble(10, 6, collapseProgress)!,
                  14,
                  ui.lerpDouble(8, 4, collapseProgress)!,
                ),
                child: AnimatedSwitcher(
                  duration: reducedMotion
                      ? Duration.zero
                      : MenoTheme.quickAnimation,
                  switchInCurve: Curves.easeOutCubic,
                  switchOutCurve: Curves.easeInCubic,
                  child: collapsed
                      ? _CollapsedPassageButton(
                          key: const Key('scripture-collapsed-picker'),
                          book: book,
                          chapter: chapter,
                          version: version,
                          onTap: onExpand,
                        )
                      : Transform.scale(
                          alignment: Alignment.bottomCenter,
                          scale: ui.lerpDouble(1, .95, collapseProgress)!,
                          child: Opacity(
                            opacity: ui.lerpDouble(1, .86, collapseProgress)!,
                            child: _ReaderSelectors(
                              key: const Key('scripture-expanded-pickers'),
                              versions: versions,
                              version: version,
                              books: books,
                              book: book,
                              chapters: chapters,
                              chapter: chapter,
                              enabled: enabled,
                              openUpward: true,
                              onVersionChanged: onVersionChanged,
                              onBookChanged: onBookChanged,
                              onChapterChanged: onChapterChanged,
                            ),
                          ),
                        ),
                ),
              ),
              _ScriptureActionBar(
                version: version,
                selection: selection,
                adding: adding,
                glass: true,
                onAdd: onAdd,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CollapsedPassageButton extends StatelessWidget {
  const _CollapsedPassageButton({
    required this.book,
    required this.chapter,
    required this.version,
    required this.onTap,
    super.key,
  });

  final BibleBook? book;
  final int chapter;
  final BibleVersion version;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final label = '${book?.name ?? 'Book'} $chapter · ${version.abbreviation}';
    return Center(
      child: Material(
        color: colors.surfaceContainerHighest.withValues(alpha: .66),
        shape: const StadiumBorder(),
        child: InkWell(
          borderRadius: BorderRadius.circular(99),
          onTap: onTap,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 260),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.menu_book_outlined, size: 16),
                  const SizedBox(width: 7),
                  Flexible(
                    child: Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  const SizedBox(width: 5),
                  const Icon(Icons.expand_less_rounded, size: 17),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ContinuousChapter extends StatefulWidget {
  const _ContinuousChapter({
    required this.passages,
    required this.selectionStart,
    required this.selectionEnd,
    required this.onVerseTap,
  });

  final List<BiblePassage> passages;
  final int? selectionStart;
  final int? selectionEnd;
  final ValueChanged<int> onVerseTap;

  @override
  State<_ContinuousChapter> createState() => _ContinuousChapterState();
}

class _ContinuousChapterState extends State<_ContinuousChapter> {
  final List<TapGestureRecognizer> _recognizers = [];
  final _paragraphKey = GlobalKey();
  List<TextSelection> _pendingSelections = const [];
  List<List<Rect>> _highlightRects = const [];
  bool _measurementScheduled = false;

  @override
  void dispose() {
    for (final recognizer in _recognizers) {
      recognizer.dispose();
    }
    super.dispose();
  }

  void _resetRecognizers() {
    for (final recognizer in _recognizers) {
      recognizer.dispose();
    }
    _recognizers.clear();
  }

  void _scheduleHighlightMeasurement(List<TextSelection> selections) {
    _pendingSelections = selections;
    if (_measurementScheduled) return;
    _measurementScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _measurementScheduled = false;
      if (!mounted) return;
      final paragraph =
          _paragraphKey.currentContext?.findRenderObject() as RenderParagraph?;
      if (paragraph == null) return;
      final rects = [
        for (final selection in _pendingSelections)
          [
            for (final box in paragraph.getBoxesForSelection(
              selection,
              boxHeightStyle: ui.BoxHeightStyle.max,
              boxWidthStyle: ui.BoxWidthStyle.tight,
            ))
              box.toRect(),
          ],
      ];
      if (_sameHighlightRects(_highlightRects, rects)) return;
      setState(() => _highlightRects = rects);
    });
  }

  bool _sameHighlightRects(List<List<Rect>> left, List<List<Rect>> right) {
    if (left.length != right.length) return false;
    for (var index = 0; index < left.length; index++) {
      final leftVerse = left[index];
      final rightVerse = right[index];
      if (leftVerse.length != rightVerse.length) return false;
      for (var boxIndex = 0; boxIndex < leftVerse.length; boxIndex++) {
        if (leftVerse[boxIndex] != rightVerse[boxIndex]) return false;
      }
    }
    return true;
  }

  @override
  Widget build(BuildContext context) {
    _resetRecognizers();
    final colors = Theme.of(context).colorScheme;
    final spans = <InlineSpan>[];
    final selectedRanges = <TextSelection>[];
    var textOffset = 0;
    for (var index = 0; index < widget.passages.length; index++) {
      final passage = widget.passages[index];
      final selected =
          widget.selectionStart != null &&
          index >= widget.selectionStart! &&
          index <= widget.selectionEnd!;
      final recognizer = TapGestureRecognizer()
        ..onTap = () => widget.onVerseTap(index);
      _recognizers.add(recognizer);

      final verseStart = textOffset;
      spans.add(
        WidgetSpan(
          alignment: PlaceholderAlignment.top,
          child: GestureDetector(
            key: ValueKey('scripture-verse-${passage.id}'),
            behavior: HitTestBehavior.opaque,
            onTap: () => widget.onVerseTap(index),
            child: Padding(
              padding: const EdgeInsets.only(left: 3, right: 2),
              child: Text(
                passage.id.split('.').last,
                style: TextStyle(
                  fontFamily: MenoTheme.serif,
                  fontSize: 11,
                  height: 1.15,
                  fontWeight: FontWeight.w600,
                  color: colors.onSurfaceVariant,
                ),
              ),
            ),
          ),
        ),
      );
      textOffset += 1;
      spans.add(
        TextSpan(
          text: passage.content,
          recognizer: recognizer,
          mouseCursor: SystemMouseCursors.click,
          semanticsLabel: passage.reference,
        ),
      );
      textOffset += passage.content.length;
      if (selected) {
        selectedRanges.add(
          TextSelection(baseOffset: verseStart, extentOffset: textOffset),
        );
      }
      if (index != widget.passages.length - 1) {
        spans.add(const TextSpan(text: ' '));
        textOffset += 1;
      }
    }
    _scheduleHighlightMeasurement(selectedRanges);
    return Stack(
      children: [
        Positioned.fill(
          child: CustomPaint(
            key: const Key('scripture-highlight-layer'),
            painter: _VerseHighlightPainter(
              verses: _highlightRects,
              color: colors.primaryContainer.withValues(alpha: .62),
            ),
          ),
        ),
        RichText(
          key: _paragraphKey,
          text: TextSpan(
            children: spans,
            style: TextStyle(
              fontFamily: MenoTheme.serif,
              fontSize: 20,
              height: 1.72,
              color: MenoSurfaces.of(context).glassMode
                  ? MenoTheme.glassInk
                  : MenoTheme.ink,
            ),
          ),
        ),
      ],
    );
  }
}

class _VerseHighlightPainter extends CustomPainter {
  const _VerseHighlightPainter({required this.verses, required this.color});

  final List<List<Rect>> verses;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = color;
    for (final boxes in verses) {
      if (boxes.isEmpty) continue;
      final lines = <Rect>[];
      for (final rawBox in boxes) {
        final box = Rect.fromLTRB(
          (rawBox.left - 3).clamp(0, size.width),
          rawBox.top + 2,
          (rawBox.right + 3).clamp(0, size.width),
          rawBox.bottom - 2,
        );
        if (box.width <= 0 || box.height <= 0) continue;
        if (lines.isNotEmpty &&
            (lines.last.center.dy - box.center.dy).abs() < 1 &&
            box.left <= lines.last.right + 2) {
          lines[lines.length - 1] = lines.last.expandToInclude(box);
        } else {
          lines.add(box);
        }
      }
      for (final line in lines) {
        canvas.drawRRect(
          RRect.fromRectAndRadius(line, const Radius.circular(5)),
          paint,
        );
      }
    }
  }

  @override
  bool shouldRepaint(covariant _VerseHighlightPainter oldDelegate) =>
      oldDelegate.color != color || oldDelegate.verses != verses;
}

class _ReaderError extends StatelessWidget {
  const _ReaderError({required this.error, required this.onRetry});

  final Object error;
  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) => Center(
    child: SingleChildScrollView(
      padding: const EdgeInsets.all(28),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.menu_book_outlined, size: 34),
          const SizedBox(height: 14),
          Text(
            'Scripture could not be loaded:\n$error',
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 16),
          OutlinedButton.icon(
            key: const Key('retry-scripture'),
            onPressed: onRetry,
            icon: const Icon(Icons.refresh),
            label: const Text('Try again'),
          ),
        ],
      ),
    ),
  );
}

class _ScriptureActionBar extends StatelessWidget {
  const _ScriptureActionBar({
    required this.version,
    required this.selection,
    required this.adding,
    required this.onAdd,
    this.glass = false,
  });

  final BibleVersion version;
  final ScriptureSelection? selection;
  final bool adding;
  final VoidCallback? onAdd;
  final bool glass;

  @override
  Widget build(BuildContext context) {
    final compactAction =
        MediaQuery.sizeOf(context).width < 360 ||
        MediaQuery.textScalerOf(context).scale(14) > 17;
    return Material(
      color: glass ? Colors.transparent : MenoSurfaces.of(context).paper,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 14),
        decoration: BoxDecoration(
          border: glass
              ? null
              : Border(top: BorderSide(color: Theme.of(context).dividerColor)),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    selection?.reference ?? 'Select a verse or range.',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  if (version.copyright.isNotEmpty) ...[
                    const SizedBox(height: 3),
                    Text(
                      version.copyright,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.labelSmall,
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 12),
            FilledButton(
              key: const Key('add-scripture-to-journal'),
              onPressed: onAdd,
              child: Text(
                adding ? 'Adding…' : (compactAction ? 'Add' : 'Add to journal'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
