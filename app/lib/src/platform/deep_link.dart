import 'dart:async';
import 'dart:io' show Platform, Process;

import 'package:app_links/app_links.dart';

/// Browser → app deep links: the `redtick://start?issue=<N>&host=<host>` scheme
/// the Chrome/Firefox extension launches from a Redmine issue page. Pairs a pure
/// parser (unit-testable, no plugin) with a thin, desktop-guarded wrapper over
/// `app_links`, mirroring how [IdleDetector]/[AppWindow] wrap their channels.
///
/// The transport is deliberately custom-scheme (not a localhost server): the OS
/// routes the link to the running instance (or cold-launches it), and the app
/// verifies the `host` param against the Redmine it's logged into before acting.

/// A parsed `redtick://start` command. Immutable, like the other models.
class StartTimerLink {
  const StartTimerLink({required this.issueId, this.host});

  /// The Redmine issue to start tracking (always > 0).
  final int issueId;

  /// The host the issue lives on (`location.host` from the page), or null when
  /// the link omitted it. Used to refuse issues from a different Redmine.
  final String? host;
}

/// Parse a deep-link [uri] into a [StartTimerLink], or null when it isn't a
/// well-formed `redtick://start?issue=N` link. Tolerant — never throws — so the
/// URI stream can be piped straight through without a guard at every call site.
StartTimerLink? parseStartTimerLink(Uri uri) {
  if (uri.scheme != 'redtick') return null;
  // `redtick://start?...` parses `start` as the URI host.
  if (uri.host != 'start') return null;
  final n = int.tryParse(uri.queryParameters['issue'] ?? '');
  if (n == null || n <= 0) return null;
  final host = uri.queryParameters['host'];
  return StartTimerLink(
    issueId: n,
    host: (host == null || host.isEmpty) ? null : host,
  );
}

/// Desktop-only wrapper over `app_links`. Off desktop (iOS/Android, where the
/// browser-extension flow doesn't apply) every method is a no-op / empty stream
/// so callers stay platform-agnostic — same shape as [IdleDetector.supported].
class DeepLinks {
  DeepLinks._();

  static bool get supported =>
      Platform.isMacOS || Platform.isWindows || Platform.isLinux;

  static final AppLinks? _links = supported ? AppLinks() : null;

  /// All incoming links: the cold-start launch link (the `app_links` plugin
  /// replays it to the first stream subscriber) followed by every warm link
  /// while running. One stream, so the launch link is delivered exactly once —
  /// pairing it with `getInitialLink()` would double-deliver on cold start.
  static Stream<Uri> uriStream() => _links?.uriLinkStream ?? const Stream.empty();

  /// Register the `redtick://` handler on Windows (macOS uses Info.plist at build
  /// time; Linux uses the packaged `.desktop` file). Idempotent, best-effort:
  /// writes `HKCU\Software\Classes\redtick` via `reg.exe` so an unpackaged/dev
  /// build still receives links. No-op off Windows.
  static Future<void> registerScheme() async {
    if (!Platform.isWindows) return;
    final exe = Platform.resolvedExecutable;
    Future<void> reg(List<String> args) async {
      try {
        await Process.run('reg', args);
      } catch (_) {/* best effort — a missing reg.exe just skips registration */}
    }

    const key = r'HKCU\Software\Classes\redtick';
    await reg(['add', key, '/ve', '/d', 'URL:Redtick Protocol', '/f']);
    await reg(['add', key, '/v', 'URL Protocol', '/d', '', '/f']);
    await reg(
        ['add', '$key\\shell\\open\\command', '/ve', '/d', '"$exe" "%1"', '/f']);
  }
}
