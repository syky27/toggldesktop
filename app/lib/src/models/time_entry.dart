/// Plain Dart model mirroring the core's `TogglTimeEntryView` (see
/// `src/toggl_api.h`). The core emits a singly-linked list of these structs in
/// the `on_time_entry_list` / `on_timer_state` callbacks; the FFI layer walks
/// the list and converts each node into one [TimeEntry]. Immutable by design.
///
/// Implements issue FP-23.
class TimeEntry {
  const TimeEntry({
    required this.id,
    required this.guid,
    required this.description,
    required this.durationInSeconds,
    required this.duration,
    required this.projectLabel,
    required this.taskLabel,
    required this.clientLabel,
    required this.color,
    required this.tags,
    required this.billable,
    required this.started,
    required this.ended,
    required this.startTimeString,
    required this.endTimeString,
    required this.isHeader,
    required this.dateHeader,
    required this.dateDuration,
    required this.unsynced,
    required this.error,
    required this.activityId,
  });

  final int id;
  final String guid;
  final String description;
  final int durationInSeconds;
  final String duration;
  final String projectLabel;
  final String taskLabel;
  final String clientLabel;
  final String color;
  final String tags;
  final bool billable;
  final int started;
  final int ended;
  final String startTimeString;
  final String endTimeString;

  /// When true this node is a date-group header row, not a real entry.
  final bool isHeader;
  final String dateHeader;
  final String dateDuration;

  final bool unsynced;
  final String error;

  /// Redmine TimeEntryActivity id (Redmine fork field).
  final int activityId;

  /// A running entry has a zero/empty end and a negative duration in the core's
  /// convention (duration is `-startTime` while running).
  bool get isRunning => durationInSeconds < 0;
}
