import 'package:flutter/gestures.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xournalpp/widgets/StylusInputPolicy.dart';

void main() {
  testWidgets(
    'hover contact release hover exit keeps palms rejected until release',
    (t) async {
      final policy = StylusInputPolicy();
      policy.hover(
        const PointerHoverEvent(device: 7, kind: PointerDeviceKind.stylus),
      );
      expect(policy.stylusNearby, isTrue);
      policy.down(
        const PointerDownEvent(pointer: 10, kind: PointerDeviceKind.touch),
      );
      policy.down(
        const PointerDownEvent(
          pointer: 11,
          device: 7,
          kind: PointerDeviceKind.stylus,
        ),
      );
      policy.up(
        const PointerUpEvent(
          pointer: 11,
          device: 7,
          kind: PointerDeviceKind.stylus,
        ),
      );
      await t.pump(const Duration(milliseconds: 300));
      policy.hover(
        const PointerHoverEvent(device: 7, kind: PointerDeviceKind.stylus),
      );
      await t.pump(const Duration(milliseconds: 300));
      expect(policy.suppressTouch, isTrue);
      policy.hover(
        const PointerHoverEvent(device: 7, kind: PointerDeviceKind.stylus),
      );
      policy.exitProximity(
        const PointerExitEvent(device: 7, kind: PointerDeviceKind.stylus),
      );
      expect(policy.stylusNearby, isFalse);
      await t.pump(const Duration(milliseconds: 499));
      expect(policy.suppressTouch, isTrue);
      await t.pump(const Duration(milliseconds: 1));
      expect(policy.suppressTouch, isFalse);
      expect(policy.rejects(10), isTrue);
      policy.up(
        const PointerUpEvent(pointer: 10, kind: PointerDeviceKind.touch),
      );
      expect(policy.hasRejectedTouches, isFalse);
      policy.dispose();
    },
  );
  testWidgets(
    'missing hover exit expires safely without changing contact ownership',
    (t) async {
      final policy = StylusInputPolicy();
      policy.hover(
        const PointerHoverEvent(device: 7, kind: PointerDeviceKind.stylus),
      );
      await t.pump(StylusInputPolicy.proximityTimeout);
      expect(policy.stylusNearby, isFalse);
      expect(policy.suppressTouch, isFalse);
      policy.down(
        const PointerDownEvent(pointer: 1, kind: PointerDeviceKind.stylus),
      );
      policy.hover(
        const PointerHoverEvent(device: 7, kind: PointerDeviceKind.stylus),
      );
      await t.pump(const Duration(seconds: 3));
      expect(policy.stylusActive, isTrue);
      expect(policy.suppressTouch, isTrue);
      policy.up(
        const PointerUpEvent(pointer: 1, kind: PointerDeviceKind.stylus),
      );
      await t.pump(const Duration(milliseconds: 500));
      expect(policy.suppressTouch, isFalse);
      policy.dispose();
    },
  );
  testWidgets(
    'hover refresh and multiple devices do not prematurely release proximity',
    (t) async {
      final policy = StylusInputPolicy();
      policy.hover(
        const PointerHoverEvent(device: 1, kind: PointerDeviceKind.mouse),
      );
      expect(policy.stylusNearby, isFalse);
      policy.hover(
        const PointerHoverEvent(device: 7, kind: PointerDeviceKind.stylus),
      );
      await t.pump(const Duration(milliseconds: 250));
      policy.hover(
        const PointerHoverEvent(device: 7, kind: PointerDeviceKind.stylus),
      );
      policy.hover(
        const PointerHoverEvent(
          device: 8,
          kind: PointerDeviceKind.invertedStylus,
        ),
      );
      await t.pump(const Duration(milliseconds: 275));
      expect(policy.stylusNearby, isTrue);
      policy.exitProximity(
        const PointerExitEvent(device: 7, kind: PointerDeviceKind.stylus),
      );
      expect(policy.suppressTouch, isTrue);
      policy.interrupt();
      expect(policy.stylusNearby, isFalse);
      expect(policy.suppressTouch, isFalse);
      await t.pump(const Duration(seconds: 3));
      expect(policy.suppressTouch, isFalse);
      policy.hover(
        const PointerHoverEvent(device: 7, kind: PointerDeviceKind.stylus),
      );
      policy.dispose();
      await t.pump(const Duration(seconds: 3));
    },
  );

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
