import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// How the time-entry list is displayed. With [groupByIssue] off (the default)
/// records render as the flat, day-grouped list. With it on, each day's records
/// are grouped under a collapsible header per Redmine issue. Persisted with
/// shared_preferences; read by the timer screen list and the view toggle.
class ViewSettings {
  const ViewSettings({this.groupByIssue = false});
  final bool groupByIssue;

  ViewSettings copyWith({bool? groupByIssue}) => ViewSettings(
        groupByIssue: groupByIssue ?? this.groupByIssue,
      );
}

class ViewSettingsNotifier extends Notifier<ViewSettings> {
  static const _kGroupByIssue = 'group_by_issue';

  @override
  ViewSettings build() {
    _load();
    return const ViewSettings();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    state = ViewSettings(
      groupByIssue: prefs.getBool(_kGroupByIssue) ?? false,
    );
  }

  Future<void> setGroupByIssue(bool v) async {
    state = state.copyWith(groupByIssue: v);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kGroupByIssue, v);
  }
}

final viewSettingsProvider =
    NotifierProvider<ViewSettingsNotifier, ViewSettings>(
        ViewSettingsNotifier.new);
