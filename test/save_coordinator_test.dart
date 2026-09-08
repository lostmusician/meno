import 'package:flutter_test/flutter_test.dart';
import 'package:meno/services/save_coordinator.dart';

void main() {
  test('flushAll persists the latest pending value before debounce', () async {
    final coordinator = SaveCoordinator(debounce: const Duration(hours: 1));
    addTearDown(coordinator.dispose);
    var saved = '';
    coordinator.schedule('entry', () async => saved = 'old');
    coordinator.schedule('entry', () async => saved = 'latest');

    expect(await coordinator.flushAll(), isTrue);
    expect(saved, 'latest');
    expect(coordinator.state.phase, SavePhase.saved);
  });

  test('failed writes remain pending and succeed on retry', () async {
    final coordinator = SaveCoordinator(debounce: const Duration(hours: 1));
    addTearDown(coordinator.dispose);
    var fail = true;
    coordinator.schedule('entry', () async {
      if (fail) throw StateError('disk full');
    });

    expect(await coordinator.flushAll(), isFalse);
    expect(coordinator.state.phase, SavePhase.failed);
    fail = false;
    expect(await coordinator.flushAll(), isTrue);
    expect(coordinator.state.phase, SavePhase.saved);
  });
}
