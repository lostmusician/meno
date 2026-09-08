import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

enum SavePhase { saved, saving, failed }

class SaveState {
  const SaveState({this.phase = SavePhase.saved, this.error});

  final SavePhase phase;
  final Object? error;
}

class _PendingSave {
  const _PendingSave(this.generation, this.write);

  final int generation;
  final Future<void> Function() write;
}

class SaveCoordinator extends StateNotifier<SaveState> {
  SaveCoordinator({this.debounce = const Duration(milliseconds: 700)})
    : super(const SaveState());

  final Duration debounce;
  final Map<String, Timer> _timers = {};
  final Map<String, _PendingSave> _pending = {};
  int _generation = 0;

  void schedule(String key, Future<void> Function() write) {
    final pending = _PendingSave(++_generation, write);
    _pending[key] = pending;
    _timers.remove(key)?.cancel();
    state = const SaveState(phase: SavePhase.saving);
    _timers[key] = Timer(debounce, () => unawaited(flush(key)));
  }

  Future<bool> flush(String key) async {
    _timers.remove(key)?.cancel();
    final pending = _pending[key];
    if (pending == null) return true;
    state = const SaveState(phase: SavePhase.saving);
    try {
      await pending.write();
      if (_pending[key]?.generation == pending.generation) {
        _pending.remove(key);
      }
      state = SaveState(
        phase: _pending.isEmpty ? SavePhase.saved : SavePhase.saving,
      );
      return true;
    } catch (error) {
      state = SaveState(phase: SavePhase.failed, error: error);
      return false;
    }
  }

  Future<bool> flushAll() async {
    var saved = true;
    for (final key in _pending.keys.toList()) {
      saved = await flush(key) && saved;
    }
    return saved;
  }

  bool get hasPendingChanges => _pending.isNotEmpty;
  bool hasPending(String key) => _pending.containsKey(key);

  @override
  void dispose() {
    for (final timer in _timers.values) {
      timer.cancel();
    }
    _timers.clear();
    super.dispose();
  }
}
