import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

/// Reveals [path] in the OS file manager (selecting the file where supported,
/// otherwise opening its containing folder), so the user can grab or send the
/// HTTP log. Returns true if a reveal/open was launched. Desktop-only — returns
/// false on mobile/web (the Settings button is gated on desktop anyway).
typedef LogFileRevealer = Future<bool> Function(String path);

final logFileRevealerProvider =
    Provider<LogFileRevealer>((ref) => revealInFileManager);

/// Default [LogFileRevealer]. Uses argument-list [Process.run] (no `runInShell`)
/// so spaces in `~/Library/Application Support` are handled without quoting, and
/// falls back to `launchUrl(Uri.file(dir))` if the platform command is missing.
Future<bool> revealInFileManager(String path) async {
  final file = File(path);
  final dir = file.parent.path;
  final exists = await file.exists();
  try {
    if (Platform.isMacOS) {
      // -R reveals + selects in Finder; fall back to the folder if absent.
      final result =
          await Process.run('open', exists ? ['-R', path] : [dir]);
      if (result.exitCode == 0) return true;
    } else if (Platform.isWindows) {
      // explorer.exe returns exit code 1 even on success → treat as best-effort.
      if (exists) {
        await Process.run('explorer', ['/select,$path']);
      } else {
        await Process.run('explorer', [dir]);
      }
      return true;
    } else if (Platform.isLinux) {
      // No portable "select" — open the containing folder.
      final result = await Process.run('xdg-open', [dir]);
      if (result.exitCode == 0) return true;
    } else {
      return false; // mobile/web: button isn't shown
    }
  } catch (_) {/* fall through to url_launcher */}

  try {
    return await launchUrl(Uri.file(dir), mode: LaunchMode.externalApplication);
  } catch (_) {
    return false;
  }
}
