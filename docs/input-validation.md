# Stylus and touch validation

The input handlers latch a gesture's tool at contact start, retain its release
endpoint, and commit only on the owner's successful release. Viewport takeover,
palm rejection, pointer cancellation, and lifecycle interruption cancel pending
mutations. Content tap recognizers honor the same cancellation through tap tokens.

A second finger creates a pinch candidate. The original touch gesture remains
transient until pinch intent is accepted; the second contact cannot start another
document mutation. Existing global-pixel thresholds remain 24 pixels of initial
separation and 8 pixels of movement. Accepted pinches retain the existing deferred
PDF/stroke raster updates.

Stroke interpolation is capped at 32 points per raw segment and 128 per smoothed
segment. Non-finite input is rejected, duplicate samples are skipped, and exact
endpoints are retained. Normal-range smoothing retains its original calculations.

## Automated checks

Regression coverage includes ownership, cross-page palm cancellation for ink and
eraser, cancel followed by up, release-only endpoints, pressure continuity,
button mode latching, text cancellation, long and short content taps, accidental
second contacts, accepted pinch cancellation, large coordinate jumps, lifecycle
interruption, and existing document/undo/rendering tests.

## Physical-device validation still required

No physical device or interactive device session is available in this cloud
workspace. The following checks have not been performed here:

- Samsung S Pen: palm contact before/during/after ink, side-button normalization,
  inverted pen, and hover event/exit reliability.
- Generic Android stylus: pressure ranges and missing pressure information.
- Apple Pencil: mixed pen/touch input and cancellation.
- Desktop drawing tablet and scrcpy: mixed pointer streams and side buttons.
- Mobile browser: browser focus changes and touch pinch.
- Long handwriting sessions: visible continuity, frame times, and memory use.

Stylus hover samples now suppress touch across the editor, including the toolbar.
An exit starts the 500 ms cooldown. Missing exits expire after two seconds without
a hover sample, then start the cooldown. Rejected contacts remain rejected until
release. Devices without hover retain the contact-only 500 ms fallback.

Flutter hover/exit routing is covered by synthetic tests. Physical-device hover
reliability remains unverified; Android native stylus normalization is unchanged.
A native hover bridge should be considered only if device evidence shows Flutter
does not deliver usable hover events.
