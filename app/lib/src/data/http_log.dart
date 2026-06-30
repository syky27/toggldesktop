import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

/// Append-only HTTP wire log for diagnosing Redmine failures (permissions to
/// custom fields, validation errors, etc.). Every Redmine request funnels
/// through [RedmineApiClient]'s two chokepoints and the GitHub release check
/// through [ReleaseWatchService]; both call [record] so the file captures the
/// full request/response of each call.
///
/// Opt-in: [enabled] defaults to `false` (the log contains the user's own
/// Redmine data — issue subjects/comments), and the `X-Redmine-API-Key` header
/// is always redacted. When disabled, [record] is a cheap no-op.
///
/// Writes are serialized through a single [_writeChain] so overlapping calls
/// (the 30s poll racing a user action) never interleave lines, and every append
/// is flushed so the file is complete when the user opens it mid-session. A
/// [fileOverride] lets tests point at a temp file (mirrors [OfflineQueue]).
class HttpLogger {
  HttpLogger({this.enabled = false, this.fileOverride});

  /// Toggled live from Settings; the client reads it per-call so a mid-session
  /// flip takes effect without rebuilding anything.
  bool enabled;

  /// Injectable for tests (point at a temp file); null uses the real app dir.
  final Future<File> Function()? fileOverride;

  /// Serializes all writes so concurrent records can't interleave/corrupt.
  Future<void> _writeChain = Future<void>.value();

  static const int _maxBytes = 5 * 1024 * 1024; // rotate past ~5 MB
  static const int _bodyCap = 16 * 1024; // truncate huge bodies per field
  static const String _redacted = '«redacted»';

  File? _cachedFile;

  /// The log file (`redtick_http.log` next to `redtick_pending.json`).
  Future<File> file() async {
    final override = fileOverride;
    if (override != null) return override();
    final cached = _cachedFile;
    if (cached != null) return cached;
    final dir = await getApplicationSupportDirectory();
    return _cachedFile = File('${dir.path}/redtick_http.log');
  }

  /// Record one HTTP exchange. Cheap no-op when disabled; never throws into the
  /// caller (a disk-full / permission error is swallowed — logging must not
  /// break a request).
  void record({
    required String method,
    required String url,
    required Map<String, String> requestHeaders,
    String? requestBody,
    int? statusCode,
    Map<String, String>? responseHeaders,
    String? responseBody,
    required Duration elapsed,
    Object? error,
  }) {
    if (!enabled) return;
    final text = _format(
      method: method,
      url: url,
      requestHeaders: requestHeaders,
      requestBody: requestBody,
      statusCode: statusCode,
      responseHeaders: responseHeaders,
      responseBody: responseBody,
      elapsed: elapsed,
      error: error,
    );
    _writeChain = _writeChain
        .then((_) => _appendAndMaybeRotate(text))
        .catchError((_) {});
  }

  /// Await any pending writes (tests; also used before revealing the file).
  Future<void> flush() => _writeChain;

  /// Delete the log file and its rotated backup.
  Future<void> clear() {
    _writeChain = _writeChain.then((_) async {
      try {
        final f = await file();
        if (await f.exists()) await f.delete();
        final backup = File('${f.path}.1');
        if (await backup.exists()) await backup.delete();
      } catch (_) {/* best effort */}
    }).catchError((_) {});
    return _writeChain;
  }

  Future<void> _appendAndMaybeRotate(String text) async {
    final f = await file();
    final bytes = utf8.encode(text).length;
    var existing = 0;
    try {
      if (await f.exists()) existing = await f.length();
    } catch (_) {/* treat as empty */}
    if (existing > 0 && existing + bytes > _maxBytes) {
      try {
        final backup = File('${f.path}.1');
        if (await backup.exists()) await backup.delete();
        await f.rename(backup.path);
      } catch (_) {/* keep appending rather than crash */}
    }
    await f.writeAsString(text, mode: FileMode.append, flush: true);
  }

  String _format({
    required String method,
    required String url,
    required Map<String, String> requestHeaders,
    String? requestBody,
    int? statusCode,
    Map<String, String>? responseHeaders,
    String? responseBody,
    required Duration elapsed,
    Object? error,
  }) {
    final ts = DateTime.now().toIso8601String();
    final b = StringBuffer()
      ..writeln('==== $ts  $method $url ====')
      ..writeln('-- request headers --');
    requestHeaders.forEach((k, v) {
      final value = k.toLowerCase() == 'x-redmine-api-key' ? _redacted : v;
      b.writeln('$k: $value');
    });
    if (requestBody != null && requestBody.isNotEmpty) {
      b
        ..writeln('-- request body --')
        ..writeln(_cap(requestBody));
    }
    if (error != null) {
      b.writeln('-- ERROR after ${elapsed.inMilliseconds}ms: $error');
    } else {
      b.writeln('-- response ($statusCode) ${elapsed.inMilliseconds}ms --');
      responseHeaders?.forEach((k, v) => b.writeln('$k: $v'));
      if (responseBody != null && responseBody.isNotEmpty) {
        b
          ..writeln('-- response body --')
          ..writeln(_cap(responseBody));
      }
    }
    b.writeln();
    return b.toString();
  }

  static String _cap(String s) =>
      s.length <= _bodyCap ? s : '${s.substring(0, _bodyCap)}… [truncated]';
}
