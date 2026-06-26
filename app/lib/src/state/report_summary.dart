import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/time_entry.dart';

/// The window the Reports page summarizes. All three are answered from the
/// locally cached ~30-day time-entry list — Reports never pulls extra data.
enum ReportPeriod { week, month, last30 }

const _monthNames = <String>[
  'January', 'February', 'March', 'April', 'May', 'June',
  'July', 'August', 'September', 'October', 'November', 'December',
];

const _monthAbbr = <String>[
  'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
  'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
];

extension ReportPeriodWindow on ReportPeriod {
  /// Short toggle label.
  String get shortLabel => switch (this) {
        ReportPeriod.week => 'Week',
        ReportPeriod.month => 'Month',
        ReportPeriod.last30 => '30 days',
      };

  /// The half-open `[start, end)` local window for [now]. Boundaries are built
  /// with the `DateTime(y, m, d)` constructor (not `Duration` arithmetic off a
  /// wall-clock instant) so a DST transition can't shift a day edge by an hour.
  (DateTime, DateTime) rangeFor(DateTime now) {
    switch (this) {
      case ReportPeriod.week:
        // weekday: Monday == 1 … Sunday == 7.
        final monday = DateTime(now.year, now.month, now.day - (now.weekday - 1));
        return (monday, DateTime(monday.year, monday.month, monday.day + 7));
      case ReportPeriod.month:
        return (
          DateTime(now.year, now.month, 1),
          DateTime(now.year, now.month + 1, 1),
        );
      case ReportPeriod.last30:
        return (
          DateTime(now.year, now.month, now.day - 29),
          DateTime(now.year, now.month, now.day + 1),
        );
    }
  }

  /// Human label for the current window, e.g. `22–28 Jun`, `June 2026`,
  /// `Last 30 days`.
  String label(DateTime now) {
    switch (this) {
      case ReportPeriod.week:
        final (start, end) = rangeFor(now);
        final last = end.subtract(const Duration(days: 1));
        final from = '${start.day} ${_monthAbbr[start.month - 1]}';
        final to = '${last.day} ${_monthAbbr[last.month - 1]}';
        return start.month == last.month
            ? '${start.day}–${last.day} ${_monthAbbr[last.month - 1]}'
            : '$from – $to';
      case ReportPeriod.month:
        return '${_monthNames[now.month - 1]} ${now.year}';
      case ReportPeriod.last30:
        return 'Last 30 days';
    }
  }
}

/// One project's slice of a [ReportSummary].
class ProjectTotal {
  const ProjectTotal({
    required this.project,
    required this.color,
    required this.seconds,
  });

  final String project;

  /// `#rrggbb` project colour (may be empty when the entry carried none).
  final String color;
  final int seconds;
}

/// Aggregated tracked time for a [ReportPeriod]: the grand total plus a
/// per-project breakdown, longest-first.
class ReportSummary {
  const ReportSummary({
    required this.totalSeconds,
    required this.entryCount,
    required this.projects,
  });

  final int totalSeconds;
  final int entryCount;
  final List<ProjectTotal> projects;

  static const empty =
      ReportSummary(totalSeconds: 0, entryCount: 0, projects: []);
}

/// Roll [entries] (the cached time-entry list) up into a [ReportSummary] for
/// [period]. Pure — pass [now] to pin the window in tests.
///
/// Skips day-header rows and running entries (whose `durationInSeconds` is
/// negative), matching the positive-only convention of `groupTotalSeconds`.
/// Entries are placed by their `started` instant falling inside the window.
ReportSummary buildReportSummary(
  List<TimeEntry> entries,
  ReportPeriod period, {
  DateTime? now,
}) {
  final (start, end) = period.rangeFor(now ?? DateTime.now());
  final startMs = start.millisecondsSinceEpoch;
  final endMs = end.millisecondsSinceEpoch;

  final seconds = <String, int>{};
  final colors = <String, String>{};
  final order = <String>[];
  var total = 0;
  var count = 0;

  for (final e in entries) {
    if (e.isHeader || e.durationInSeconds <= 0) continue;
    final ms = e.started * 1000;
    if (ms < startMs || ms >= endMs) continue;

    final name = e.projectLabel.isEmpty ? 'No project' : e.projectLabel;
    if (!seconds.containsKey(name)) {
      order.add(name);
      seconds[name] = 0;
    }
    seconds[name] = seconds[name]! + e.durationInSeconds;
    if ((colors[name] ?? '').isEmpty && e.color.isNotEmpty) {
      colors[name] = e.color;
    }
    total += e.durationInSeconds;
    count++;
  }

  final projects = [
    for (final name in order)
      ProjectTotal(
        project: name,
        color: colors[name] ?? '',
        seconds: seconds[name]!,
      ),
  ]..sort((a, b) => b.seconds.compareTo(a.seconds));

  return ReportSummary(
    totalSeconds: total,
    entryCount: count,
    projects: projects,
  );
}

/// The Reports page period selector — transient view state (not persisted),
/// defaulting to the current week. Mirrors the `Notifier` shape of
/// `ViewSettingsNotifier`.
class ReportPeriodNotifier extends Notifier<ReportPeriod> {
  @override
  ReportPeriod build() => ReportPeriod.week;

  void set(ReportPeriod period) => state = period;
}

final reportPeriodProvider =
    NotifierProvider<ReportPeriodNotifier, ReportPeriod>(
        ReportPeriodNotifier.new);
