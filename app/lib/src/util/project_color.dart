/// Deterministic per-project accent colour derived ONLY from the Redmine project
/// id, so a project always shows the same colour AND the exact same algorithm can
/// be reproduced verbatim elsewhere (e.g. a Redmine plugin) — no shared code, no
/// hardcoded names.
///
/// Algorithm (portable — keep byte-for-byte identical to the reference):
///   hue        = (abs(projectId) * 137.508) mod 360   // golden angle → distinct hues
///   saturation = 0.65
///   lightness  = 0.55
///   colour     = HSL(hue, saturation, lightness) rendered as #RRGGBB (uppercase)
/// A null project id (issue-only entry before the project resolves) → grey #9E9E9E.
String projectColorHex(int? projectId) {
  if (projectId == null) return '#9E9E9E';
  final hue = (projectId.abs() * 137.508) % 360.0;
  return _hslToHex(hue, 0.65, 0.55);
}

// h in [0,360); s,l in [0,1].
String _hslToHex(double h, double s, double l) {
  final c = (1 - (2 * l - 1).abs()) * s;
  final x = c * (1 - (h / 60.0 % 2 - 1).abs());
  final m = l - c / 2;
  final (double r1, double g1, double b1) = switch (h) {
    < 60 => (c, x, 0.0),
    < 120 => (x, c, 0.0),
    < 180 => (0.0, c, x),
    < 240 => (0.0, x, c),
    < 300 => (x, 0.0, c),
    _ => (c, 0.0, x),
  };
  // The reference uses round-half-to-even; for the fixed s=0.65/l=0.55 constants a
  // *.5 midpoint never occurs, so .round() (half-away-from-zero) is byte-identical.
  int ch(double v) => ((v + m) * 255.0).round().clamp(0, 255);
  String hx(int v) => v.toRadixString(16).toUpperCase().padLeft(2, '0');
  return '#${hx(ch(r1))}${hx(ch(g1))}${hx(ch(b1))}';
}
