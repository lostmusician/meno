import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/journal_entry.dart';
import '../services/database_service.dart';
import 'service_providers.dart';

class BinderState {
  const BinderState({
    this.zoom = BinderZoom.days,
    this.days = const [],
    this.selectedDateKey,
    this.isLoading = false,
    this.hasMore = true,
    this.error,
  });

  final BinderZoom zoom;
  final List<BinderDay> days;
  final String? selectedDateKey;
  final bool isLoading;
  final bool hasMore;
  final Object? error;

  BinderState copyWith({
    BinderZoom? zoom,
    List<BinderDay>? days,
    String? selectedDateKey,
    bool? isLoading,
    bool? hasMore,
    Object? error,
    bool clearError = false,
  }) => BinderState(
    zoom: zoom ?? this.zoom,
    days: days ?? this.days,
    selectedDateKey: selectedDateKey ?? this.selectedDateKey,
    isLoading: isLoading ?? this.isLoading,
    hasMore: hasMore ?? this.hasMore,
    error: clearError ? null : error ?? this.error,
  );
}

class BinderController extends StateNotifier<BinderState> {
  BinderController(this._database) : super(const BinderState());

  static const pageSize = 20;
  final DatabaseService _database;

  Future<void> refresh({String? anchorDateKey}) async {
    state = state.copyWith(
      days: const [],
      selectedDateKey: anchorDateKey ?? state.selectedDateKey,
      hasMore: true,
      clearError: true,
    );
    await loadMore();
    if (state.selectedDateKey == null && state.days.isNotEmpty) {
      state = state.copyWith(selectedDateKey: state.days.first.day.dateKey);
    }
  }

  Future<void> loadMore() async {
    if (state.isLoading || !state.hasMore) return;
    state = state.copyWith(isLoading: true, clearError: true);
    try {
      final page = await _database.binderPage(
        cursor: state.days.lastOrNull == null
            ? null
            : BinderCursor(state.days.last.day.dateKey),
        limit: pageSize,
      );
      state = state.copyWith(
        days: [...state.days, ...page],
        isLoading: false,
        hasMore: page.length == pageSize,
      );
    } catch (error) {
      state = state.copyWith(isLoading: false, error: error);
    }
  }

  void selectDate(String dateKey) {
    state = state.copyWith(selectedDateKey: dateKey);
  }

  void setZoom(BinderZoom zoom) {
    state = state.copyWith(zoom: zoom);
  }
}

final binderControllerProvider =
    StateNotifierProvider<BinderController, BinderState>(
      (ref) => BinderController(ref.watch(databaseServiceProvider)),
    );
