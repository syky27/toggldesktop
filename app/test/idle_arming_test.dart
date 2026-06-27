import 'package:flutter_test/flutter_test.dart';
import 'package:redtick/src/ui/widgets/idle_prompt.dart';

/// Unit tests for the idle prompt's arming latch. The bug being guarded: after a
/// fire, re-arming used to depend on a poll sampling idle<threshold/2 — a window
/// the 20s poll routinely misses — so the prompt could stop reappearing. The fix
/// re-arms on dismissal via [IdleArming.rearm].
void main() {
  const threshold = 60; // seconds; re-arm window is < 30s

  test('fires when idle >= threshold and armed, consuming the latch', () {
    final a = IdleArming();
    expect(a.armed, isTrue);
    expect(a.evaluate(idleSec: 70, thresholdSec: threshold),
        IdleArmingDecision.fire);
    expect(a.armed, isFalse); // latch consumed → won't re-fire every tick
  });

  test('holds (belowThreshold) between half-threshold and threshold', () {
    final a = IdleArming();
    expect(a.evaluate(idleSec: 45, thresholdSec: threshold),
        IdleArmingDecision.belowThreshold);
    expect(a.armed, isTrue); // unchanged
  });

  test('re-arms (active) when idle drops below half threshold', () {
    final a = IdleArming();
    a.evaluate(idleSec: 70, thresholdSec: threshold); // fire → disarm
    expect(a.armed, isFalse);
    expect(a.evaluate(idleSec: 10, thresholdSec: threshold),
        IdleArmingDecision.active);
    expect(a.armed, isTrue); // user active → re-armed
  });

  test('stays latched on sustained idle after a fire (no re-fire)', () {
    final a = IdleArming();
    a.evaluate(idleSec: 70, thresholdSec: threshold); // fire → disarm
    expect(a.evaluate(idleSec: 80, thresholdSec: threshold),
        IdleArmingDecision.latched);
    expect(a.evaluate(idleSec: 200, thresholdSec: threshold),
        IdleArmingDecision.latched);
  });

  test('regression: rearm() on dismissal unsticks the latch deterministically',
      () {
    final a = IdleArming();
    // 1) idle past threshold → fires.
    expect(a.evaluate(idleSec: 70, thresholdSec: threshold),
        IdleArmingDecision.fire);
    // 2) user dismisses and goes idle again WITHOUT a low-idle sample landing on
    //    a poll — the old code stayed latched here forever.
    expect(a.evaluate(idleSec: 70, thresholdSec: threshold),
        IdleArmingDecision.latched);
    // 3) the fix: dismissing re-arms regardless of poll timing...
    a.rearm();
    expect(a.armed, isTrue);
    // 4) ...so the next idle episode fires again.
    expect(a.evaluate(idleSec: 70, thresholdSec: threshold),
        IdleArmingDecision.fire);
  });

  test('boundaries match the original strict-< semantics', () {
    // idle == threshold → fire (>=).
    expect(IdleArming().evaluate(idleSec: 60, thresholdSec: threshold),
        IdleArmingDecision.fire);
    // idle == threshold/2 → not active (strict <), so belowThreshold.
    expect(IdleArming().evaluate(idleSec: 30, thresholdSec: threshold),
        IdleArmingDecision.belowThreshold);
  });
}
