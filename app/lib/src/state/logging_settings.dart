import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'providers.dart';

/// Whether HTTP traffic is written to the on-disk log. Opt-in (default off):
/// the log holds the user's own Redmine data, and the API key is redacted.
class LoggingSettings {
  const LoggingSettings({this.enabled = false});
  final bool enabled;

  LoggingSettings copyWith({bool? enabled}) =>
      LoggingSettings(enabled: enabled ?? this.enabled);
}

class LoggingSettingsNotifier extends Notifier<LoggingSettings> {
  /// Public so `main()` can read the persisted flag before the widget tree (and
  /// thus this notifier) exists, to arm the logger for the very first login.
  static const kEnabled = 'http_logging_enabled';

  @override
  LoggingSettings build() {
    _load();
    return const LoggingSettings();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final on = prefs.getBool(kEnabled) ?? false;
    state = LoggingSettings(enabled: on);
    ref.read(httpLoggerProvider).enabled = on;
  }

  Future<void> setEnabled(bool v) async {
    state = state.copyWith(enabled: v);
    // Flip the shared logger live — the client reads `enabled` per call, so this
    // takes effect immediately with no client rebuild.
    ref.read(httpLoggerProvider).enabled = v;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(kEnabled, v);
  }
}

final loggingSettingsProvider =
    NotifierProvider<LoggingSettingsNotifier, LoggingSettings>(
        LoggingSettingsNotifier.new);
