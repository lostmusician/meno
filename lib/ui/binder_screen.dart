import 'dart:async';
import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/journal_entry.dart';
import '../providers/journal_providers.dart';
import 'brand_assets.dart';
import 'discovery_screen.dart';
import 'mood_dial.dart';
import 'theme_primitives.dart';

part 'binder_components.dart';

class BinderScreen extends ConsumerStatefulWidget {
  const BinderScreen({super.key});

  @override
  ConsumerState<BinderScreen> createState() => _BinderScreenState();
}

class _BinderScreenState extends ConsumerState<BinderScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _motionController;
  Animation<double>? _railAnimation;
  Timer? _snapTimer;
  List<_BinderItem> _currentItems = const [];
  double _railPosition = 0;
  int _selectedIndex = 0;
  bool _scaleHandled = false;
  bool _initialAnchorSynced = false;
  String? _pendingZoomAnchor;

  @override
  void initState() {
    super.initState();
    _motionController = AnimationController(vsync: this)
      ..addListener(() {
        final animation = _railAnimation;
        if (animation == null) return;
        setState(() => _railPosition = animation.value);
        _commitNearest(_currentItems);
      });
    HardwareKeyboard.instance.addHandler(_handleGlobalKeyEvent);
    Future.microtask(() {
      final anchor = ref.read(journalControllerProvider).selectedDateKey;
      ref
          .read(binderControllerProvider.notifier)
          .refresh(anchorDateKey: anchor);
    });
  }

  @override
  void dispose() {
    _snapTimer?.cancel();
    HardwareKeyboard.instance.removeHandler(_handleGlobalKeyEvent);
    _motionController.dispose();
    super.dispose();
  }

  void _changeZoom(BinderZoom zoom, {String? anchorDateKey}) {
    if (zoom == ref.read(binderControllerProvider).zoom) return;
    _pendingZoomAnchor =
        anchorDateKey ?? ref.read(binderControllerProvider).selectedDateKey;
    ref.read(binderControllerProvider.notifier).setZoom(zoom);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final items = _itemsFor(ref.read(binderControllerProvider));
      final anchor = _pendingZoomAnchor;
      final index = items.indexWhere(
        (item) => item.days.any((day) => day.day.dateKey == anchor),
      );
      _pendingZoomAnchor = null;
      _jumpToIndex(index < 0 ? 0 : index, items, commit: false);
      if (anchor != null &&
          index >= 0 &&
          items[index].days.any((day) => day.day.dateKey == anchor)) {
        ref.read(binderControllerProvider.notifier).selectDate(anchor);
      }
    });
  }

  void _activateItem(_BinderItem item, BinderZoom zoom) {
    switch (zoom) {
      case BinderZoom.days:
        unawaited(
          ref
              .read(journalControllerProvider.notifier)
              .openDay(item.anchorDateKey),
        );
      case BinderZoom.weeks:
        _changeZoom(BinderZoom.days, anchorDateKey: item.anchorDateKey);
      case BinderZoom.months:
        _changeZoom(BinderZoom.weeks, anchorDateKey: item.anchorDateKey);
    }
  }

  void _zoomBy(int delta) {
    final state = ref.read(binderControllerProvider);
    final index = BinderZoom.values.indexOf(state.zoom);
    final next = (index + delta).clamp(0, BinderZoom.values.length - 1);
    if (next != index) _changeZoom(BinderZoom.values[next]);
  }

  void _jumpToIndex(int index, List<_BinderItem> items, {bool commit = true}) {
    if (items.isEmpty) return;
    _motionController.stop();
    _snapTimer?.cancel();
    final target = index.clamp(0, items.length - 1);
    setState(() {
      _railPosition = target.toDouble();
      _selectedIndex = target;
    });
    if (commit) _commitIndex(target, items);
  }

  void _moveBy(double amount, List<_BinderItem> items) {
    if (items.isEmpty || amount == 0) return;
    _motionController.stop();
    setState(() {
      _railPosition = (_railPosition + amount).clamp(
        0.0,
        math.max(0, items.length - 1).toDouble(),
      );
    });
    _commitNearest(items);
  }

  void _scheduleSnap(List<_BinderItem> items) {
    _snapTimer?.cancel();
    _snapTimer = Timer(
      const Duration(milliseconds: 110),
      () => _animateToIndex(_railPosition.round(), items),
    );
  }

  void _snapWithVelocity(double velocity, List<_BinderItem> items) {
    final projected = _railPosition - velocity / 360;
    _animateToIndex(projected.round(), items);
  }

  void _animateToIndex(int index, List<_BinderItem> items) {
    if (!mounted || items.isEmpty) return;
    _snapTimer?.cancel();
    final target = index.clamp(0, items.length - 1).toDouble();
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    if (reduceMotion || (target - _railPosition).abs() < .01) {
      _jumpToIndex(target.round(), items);
      return;
    }
    final distance = (target - _railPosition).abs();
    _motionController.duration = Duration(
      milliseconds: (170 + distance * 34).round().clamp(170, 430),
    );
    _railAnimation = Tween<double>(begin: _railPosition, end: target).animate(
      CurvedAnimation(parent: _motionController, curve: Curves.easeOutCubic),
    );
    _motionController.forward(from: 0);
  }

  void _commitNearest(List<_BinderItem> items) {
    if (items.isEmpty) return;
    final index = _railPosition.round().clamp(0, items.length - 1);
    final selectedDate = ref.read(binderControllerProvider).selectedDateKey;
    if (index == _selectedIndex && selectedDate == items[index].anchorDateKey) {
      return;
    }
    _selectedIndex = index;
    _commitIndex(index, items);
  }

  void _commitIndex(int index, List<_BinderItem> items) {
    if (items.isEmpty) return;
    final target = index.clamp(0, items.length - 1);
    ref
        .read(binderControllerProvider.notifier)
        .selectDate(items[target].anchorDateKey);
    if (target >= items.length - 4) {
      ref.read(binderControllerProvider.notifier).loadMore();
    }
  }

  void _moveKeyboard(int delta) {
    _animateToIndex(_selectedIndex + delta, _currentItems);
  }

  bool _handleGlobalKeyEvent(KeyEvent event) {
    if (event is! KeyDownEvent) return false;
    final key = event.logicalKey;
    final modifier =
        HardwareKeyboard.instance.isMetaPressed ||
        HardwareKeyboard.instance.isControlPressed;
    if (modifier &&
        (key == LogicalKeyboardKey.equal || key == LogicalKeyboardKey.add)) {
      _zoomBy(-1);
      return true;
    }
    if (modifier && key == LogicalKeyboardKey.minus) {
      _zoomBy(1);
      return true;
    }
    final delta = switch (key) {
      LogicalKeyboardKey.arrowLeft => 1,
      LogicalKeyboardKey.arrowRight => -1,
      LogicalKeyboardKey.pageDown => 5,
      LogicalKeyboardKey.pageUp => -5,
      _ => 0,
    };
    if (delta == 0) return false;
    _moveKeyboard(delta);
    return true;
  }

  Future<void> _openSettings() async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) => const MenoSettingsSheet(),
    );
  }

  Future<void> _openDiscovery() async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) => const DiscoverySheet(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final binder = ref.watch(binderControllerProvider);
    final app = ref.watch(journalControllerProvider);
    ref.listen<List<BinderDay>>(
      binderControllerProvider.select((state) => state.days),
      (_, days) =>
          ref.read(discoveryControllerProvider.notifier).loadForDays(days),
    );
    final items = _itemsFor(binder);
    _currentItems = items;
    if (items.isNotEmpty && !_initialAnchorSynced) {
      _initialAnchorSynced = true;
      final anchor = binder.selectedDateKey;
      final anchorIndex = items.indexWhere(
        (item) => item.days.any((day) => day.day.dateKey == anchor),
      );
      if (anchorIndex > 0) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _jumpToIndex(anchorIndex, items);
        });
      }
    }
    if (items.isNotEmpty &&
        _selectedIndex >= items.length &&
        _pendingZoomAnchor == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _jumpToIndex(items.length - 1, items);
      });
    }
    return Focus(
      autofocus: true,
      child: ColoredBox(
        color: MenoSurfaces.of(context).glassMode
            ? MenoSurfaces.of(context).page
            : MenoTheme.binderBackground,
        child: SafeArea(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 14, 8),
                child: Row(
                  children: [
                    const Expanded(
                      child: Row(
                        children: [
                          MenoBrandMark(size: 30),
                          SizedBox(width: 11),
                          Flexible(
                            child: FittedBox(
                              fit: BoxFit.scaleDown,
                              alignment: Alignment.centerLeft,
                              child: Text(
                                'Your days',
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
                    ),
                    if (app.showMoodReminder)
                      Builder(
                        builder: (context) {
                          void addMood() {
                            unawaited(
                              ref
                                  .read(journalControllerProvider.notifier)
                                  .openMood(localDateKey(DateTime.now())),
                            );
                          }

                          if (MediaQuery.sizeOf(context).width < 680) {
                            return IconButton(
                              key: const Key('binder-add-mood'),
                              tooltip: 'Add mood',
                              onPressed: addMood,
                              icon: const Icon(Icons.mood_rounded),
                            );
                          }
                          return Padding(
                            padding: const EdgeInsets.only(right: 4),
                            child: FilledButton.tonalIcon(
                              key: const Key('binder-add-mood'),
                              onPressed: addMood,
                              icon: const Icon(Icons.mood_rounded, size: 18),
                              label: const Text('Add mood'),
                            ),
                          );
                        },
                      ),
                    IconButton(
                      key: const Key('binder-discovery'),
                      tooltip: 'Search journal',
                      onPressed: _openDiscovery,
                      icon: const Icon(Icons.search_rounded),
                    ),
                    IconButton(
                      key: const Key('binder-settings'),
                      tooltip: 'Settings',
                      onPressed: _openSettings,
                      icon: const Icon(Icons.tune_rounded),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: SegmentedButton<BinderZoom>(
                  key: const Key('binder-zoom'),
                  showSelectedIcon: false,
                  segments: const [
                    ButtonSegment(value: BinderZoom.days, label: Text('Days')),
                    ButtonSegment(
                      value: BinderZoom.weeks,
                      label: Text('Weeks'),
                    ),
                    ButtonSegment(
                      value: BinderZoom.months,
                      label: Text('Months'),
                    ),
                  ],
                  selected: {binder.zoom},
                  onSelectionChanged: (value) => _changeZoom(value.first),
                ),
              ),
              const SizedBox(height: 10),
              Expanded(
                child: items.isEmpty && !binder.isLoading
                    ? const Center(
                        child: Text(
                          'Your first recorded day will appear here.',
                          style: TextStyle(fontStyle: FontStyle.italic),
                        ),
                      )
                    : LayoutBuilder(
                        builder: (context, constraints) {
                          final compact = constraints.maxWidth < 600;
                          final pitch = compact ? 14.0 : 24.0;
                          final transitionDuration =
                              MediaQuery.disableAnimationsOf(context)
                              ? Duration.zero
                              : const Duration(milliseconds: 260);
                          return AnimatedSwitcher(
                            key: const Key('binder-zoom-transition'),
                            duration: transitionDuration,
                            reverseDuration: transitionDuration,
                            layoutBuilder: (currentChild, previousChildren) {
                              final children = <Widget>[...previousChildren];
                              if (currentChild != null) {
                                children.add(currentChild);
                              }
                              return Stack(
                                fit: StackFit.expand,
                                children: children,
                              );
                            },
                            transitionBuilder: (child, animation) =>
                                FadeTransition(
                                  opacity: CurvedAnimation(
                                    parent: animation,
                                    curve: Curves.easeOutCubic,
                                  ),
                                  child: ScaleTransition(
                                    alignment: Alignment.center,
                                    scale: Tween<double>(begin: .94, end: 1)
                                        .animate(
                                          CurvedAnimation(
                                            parent: animation,
                                            curve: Curves.easeOutCubic,
                                          ),
                                        ),
                                    child: child,
                                  ),
                                ),
                            child: KeyedSubtree(
                              key: ValueKey(binder.zoom),
                              child: Listener(
                                key: const Key('binder-rail'),
                                onPointerSignal: (event) {
                                  if (event is! PointerScrollEvent) return;
                                  final delta =
                                      event.scrollDelta.dx.abs() >
                                          event.scrollDelta.dy.abs()
                                      ? event.scrollDelta.dx
                                      : event.scrollDelta.dy;
                                  _moveBy(delta / pitch, items);
                                  _scheduleSnap(items);
                                },
                                onPointerPanZoomStart: (_) {
                                  _motionController.stop();
                                  _scaleHandled = false;
                                },
                                onPointerPanZoomUpdate: (event) {
                                  if (!_scaleHandled && event.scale > 1.12) {
                                    _scaleHandled = true;
                                    _zoomBy(-1);
                                    return;
                                  }
                                  if (!_scaleHandled && event.scale < .88) {
                                    _scaleHandled = true;
                                    _zoomBy(1);
                                    return;
                                  }
                                  if (!_scaleHandled) {
                                    final delta =
                                        event.panDelta.dx.abs() >
                                            event.panDelta.dy.abs()
                                        ? -event.panDelta.dx
                                        : event.panDelta.dy;
                                    _moveBy(delta / pitch, items);
                                  }
                                },
                                onPointerPanZoomEnd: (_) => _animateToIndex(
                                  _railPosition.round(),
                                  items,
                                ),
                                child: GestureDetector(
                                  behavior: HitTestBehavior.opaque,
                                  onScaleStart: (_) {
                                    _motionController.stop();
                                    _scaleHandled = false;
                                  },
                                  onScaleUpdate: (details) {
                                    if (details.pointerCount > 1) {
                                      if (!_scaleHandled &&
                                          details.scale > 1.12) {
                                        _scaleHandled = true;
                                        _zoomBy(-1);
                                      } else if (!_scaleHandled &&
                                          details.scale < .88) {
                                        _scaleHandled = true;
                                        _zoomBy(1);
                                      }
                                      return;
                                    }
                                    if (!_scaleHandled) {
                                      _moveBy(
                                        -details.focalPointDelta.dx / pitch,
                                        items,
                                      );
                                    }
                                  },
                                  onScaleEnd: (details) {
                                    if (!_scaleHandled) {
                                      _snapWithVelocity(
                                        details.velocity.pixelsPerSecond.dx,
                                        items,
                                      );
                                    }
                                  },
                                  child: _BinderRail(
                                    key: const Key('binder-pages'),
                                    items: items,
                                    zoom: binder.zoom,
                                    position: _railPosition,
                                    selectedIndex: _selectedIndex.clamp(
                                      0,
                                      items.length - 1,
                                    ),
                                    pitch: pitch,
                                    compact: compact,
                                    onSelect: (index) =>
                                        _animateToIndex(index, items),
                                    onActivate: (item) =>
                                        _activateItem(item, binder.zoom),
                                  ),
                                ),
                              ),
                            ),
                          );
                        },
                      ),
              ),
              if (binder.isLoading)
                const Padding(
                  padding: EdgeInsets.only(bottom: 12),
                  child: LinearProgressIndicator(),
                ),
            ],
          ),
        ),
      ),
    );
  }

  List<_BinderItem> _itemsFor(BinderState state) {
    if (state.zoom == BinderZoom.days) {
      return [
        for (final day in state.days)
          _BinderItem(label: _friendlyDate(day.day.dateKey), days: [day]),
      ];
    }
    final groups = <String, List<BinderDay>>{};
    for (final day in state.days) {
      final date = localDateFromKey(day.day.dateKey);
      final label = state.zoom == BinderZoom.weeks
          ? _weekLabel(date)
          : '${_monthName(date.month)} ${date.year}';
      groups.putIfAbsent(label, () => []).add(day);
    }
    return [
      for (final group in groups.entries)
        _BinderItem(label: group.key, days: group.value),
    ];
  }
}
