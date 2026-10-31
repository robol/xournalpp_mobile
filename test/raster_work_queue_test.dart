import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xournalpp/src/RasterWorkQueue.dart';
import 'package:xournalpp/widgets/StrokeRasterPolicy.dart';

void main() {
  testWidgets('shared queue wakeups are registered only once', (tester) async {
    final policy = StrokeRasterPolicy(viewport: () => null);
    var calls = 0;
    void wake() => calls++;
    policy.addWorkListener(wake);
    policy.addWorkListener(wake);
    policy.viewportChanged();
    expect(calls, 1);
    policy.removeWorkListener(wake);
    policy.viewportChanged();
    expect(calls, 2);
    policy.removeWorkListener(wake);
    policy.viewportChanged();
    expect(calls, 2);
    policy.dispose();
  });

  testWidgets('offscreen work waits for idle eligibility and can be promoted', (
    tester,
  ) async {
    await tester.pumpWidget(const SizedBox());
    await tester.runAsync(() async {
      final queue = RasterWorkQueue();
      var visible = false;
      var idle = false;
      final calls = <String>[];
      final promoted = Completer<void>();
      queue.schedule(
        isCurrent: () => true,
        isVisible: () => visible,
        backgroundAllowed: () => idle,
        run: () async {
          calls.add('promoted');
          promoted.complete();
        },
      );
      await Future<void>.delayed(Duration.zero);
      expect(calls, isEmpty);
      visible = true;
      queue.prioritiesChanged();
      await promoted.future;
      expect(calls, ['promoted']);

      final warmed = Completer<void>();
      queue.schedule(
        isCurrent: () => true,
        isVisible: () => false,
        backgroundAllowed: () => idle,
        run: () async {
          calls.add('warm');
          warmed.complete();
        },
      );
      await Future<void>.delayed(Duration.zero);
      expect(calls, ['promoted']);
      idle = true;
      queue.prioritiesChanged();
      await warmed.future;
      expect(calls, ['promoted', 'warm']);
    });
  });

  testWidgets('held interaction defers warm-up until it ends', (tester) async {
    var active = true;
    final policy = StrokeRasterPolicy(viewport: () => null)
      ..interactionActive = () => active;
    expect(policy.backgroundAllowed, isFalse);
    await tester.pump(const Duration(seconds: 2));
    expect(policy.backgroundAllowed, isFalse);
    active = false;
    policy.noteActivity();
    await tester.pump(const Duration(milliseconds: 499));
    expect(policy.backgroundAllowed, isFalse);
    await tester.pump(const Duration(milliseconds: 1));
    expect(policy.backgroundAllowed, isTrue);
    policy.noteActivity();
    expect(policy.backgroundAllowed, isFalse);
    policy.dispose();
  });
}
