import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Whether the user may track several tasks at once. Opt-in (default OFF): with
/// it off the app keeps the single-timer behaviour (starting/continuing a task
/// stops the current one). With it on, timers run concurrently and stack in the
/// top bar. Persisted with shared_preferences; read by the timer bar, the
/// continue action, and the live-surface wiring.
class MultiTaskSettings {
  const MultiTaskSettings({this.allowConcurrent = false});
  final bool allowConcurrent;

  MultiTaskSettings copyWith({bool? allowConcurrent}) => MultiTaskSettings(
        allowConcurrent: allowConcurrent ?? this.allowConcurrent,
      );
}

class MultiTaskSettingsNotifier extends Notifier<MultiTaskSettings> {
  static const _kAllow = 'allow_concurrent_tracking';

  @override
  MultiTaskSettings build() {
    _load();
    return const MultiTaskSettings();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    state = MultiTaskSettings(
      allowConcurrent: prefs.getBool(_kAllow) ?? false,
    );
  }

  Future<void> setAllowConcurrent(bool v) async {
    state = state.copyWith(allowConcurrent: v);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kAllow, v);
  }
}

final multiTaskSettingsProvider =
    NotifierProvider<MultiTaskSettingsNotifier, MultiTaskSettings>(
        MultiTaskSettingsNotifier.new);
