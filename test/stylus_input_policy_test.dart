import 'package:flutter/gestures.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xournalpp/widgets/StylusInputPolicy.dart';

void main() {
  testWidgets('shared policy rejects existing contacts until actual release', (
    t,
  ) async {
    final policy = StylusInputPolicy();
    policy.down(
      const PointerDownEvent(pointer: 1, kind: PointerDeviceKind.touch),
    );
    policy.down(
      const PointerDownEvent(pointer: 2, kind: PointerDeviceKind.stylus),
    );
    policy.down(
      const PointerDownEvent(pointer: 2, kind: PointerDeviceKind.stylus),
    );
    expect(policy.rejects(1), isTrue);
    policy.up(const PointerUpEvent(pointer: 2, kind: PointerDeviceKind.stylus));
    await t.pump(const Duration(milliseconds: 501));
    expect(policy.suppressTouch, isFalse);
    expect(policy.rejects(1), isTrue);
    policy.up(const PointerUpEvent(pointer: 1, kind: PointerDeviceKind.touch));
    expect(policy.hasRejectedTouches, isFalse);
    policy.dispose();
  });
  testWidgets(
    'interruption removes active state and ignores orphan terminal events',
    (t) async {
      final policy = StylusInputPolicy();
      policy.down(
        const PointerDownEvent(pointer: 1, kind: PointerDeviceKind.stylus),
      );
      policy.interrupt();
      expect(policy.stylusActive, isFalse);
      expect(policy.suppressTouch, isFalse);
      expect(policy.rejects(1), isTrue);
      policy.up(
        const PointerUpEvent(pointer: 1, kind: PointerDeviceKind.stylus),
      );
      expect(policy.suppressTouch, isFalse);
      policy.dispose();
    },
  );
}
