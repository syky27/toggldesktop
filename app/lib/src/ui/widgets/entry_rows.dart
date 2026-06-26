import '../../models/time_entry.dart';
import 'entry_bits.dart';

/// One visual row in the time-entry list. The backend hands the UI a flat
/// `List<TimeEntry>` of day headers (`isHeader == true`) interleaved with
/// records; [buildEntryRows] turns that into the list actually rendered — either
/// unchanged (flat mode) or with the records of each day folded into collapsible
/// per-issue groups (grouped mode).
sealed class EntryListRow {
  const EntryListRow();
}

/// The backend's day-group header (`Today · …` + daily total), passed through
/// verbatim in both modes.
class DayHeaderRow extends EntryListRow {
  const DayHeaderRow(this.entry);
  final TimeEntry entry;
}

/// A collapsible header for all of one day's records that share a Redmine issue
/// (issue `0` ⇒ the "No issue" bucket).
class IssueGroupRow extends EntryListRow {
  const IssueGroupRow({
    required this.groupKey,
    required this.sample,
    required this.count,
    required this.totalSeconds,
    required this.expanded,
  });

  /// Stable identity used to remember expand/collapse state — see [groupKeyFor].
  final String groupKey;

  /// The newest record of the group; source of the issue label, project colour
  /// and the continue (▶) target.
  final TimeEntry sample;

  /// Number of records in the group.
  final int count;

  /// Sum of the group's record durations (running/negative durations skipped).
  final int totalSeconds;

  final bool expanded;
}

/// A single time record. [grouped] is true when it sits inside an expanded
/// [IssueGroupRow] (rendered indented).
class RecordRow extends EntryListRow {
  const RecordRow(this.entry, {this.grouped = false});
  final TimeEntry entry;
  final bool grouped;
}

/// Stable per-day, per-issue key: `"Y-M-D|issueNumber"`. Records of the same
/// issue on the same local day share a key, so a group stays open across the
/// frequent `timeEntriesProvider` re-emissions.
String groupKeyFor(TimeEntry e) {
  final d = DateTime.fromMillisecondsSinceEpoch(e.started * 1000);
  return '${d.year}-${d.month}-${d.day}|${issueNumber(e)}';
}

/// Sum of record durations, skipping running entries (whose `durationInSeconds`
/// is negative). Matches the day-total convention in `calendar_screen.dart`.
int groupTotalSeconds(Iterable<TimeEntry> records) => records.fold(
    0, (s, e) => s + (e.durationInSeconds > 0 ? e.durationInSeconds : 0));

/// `h:mm:ss` — the same shape used across the app for list/total durations.
String formatDuration(int seconds) {
  final s = seconds < 0 ? 0 : seconds;
  return '${s ~/ 3600}:${((s % 3600) ~/ 60).toString().padLeft(2, '0')}:'
      '${(s % 60).toString().padLeft(2, '0')}';
}

/// Build the flat list of rows to render.
///
/// In flat mode each incoming row maps 1:1. In grouped mode the records under
/// each day header are bucketed by issue, preserving first-seen order — and
/// since records arrive newest-first, that orders groups by their most-recent
/// record (newest issue on top). Only groups whose key is in [expanded] reveal
/// their records.
List<EntryListRow> buildEntryRows(
  List<TimeEntry> entries, {
  required bool groupByIssue,
  required Set<String> expanded,
}) {
  final out = <EntryListRow>[];

  if (!groupByIssue) {
    for (final e in entries) {
      out.add(e.isHeader ? DayHeaderRow(e) : RecordRow(e));
    }
    return out;
  }

  var i = 0;
  while (i < entries.length) {
    final e = entries[i];
    if (e.isHeader) {
      out.add(DayHeaderRow(e));
      i++;
    }
    // Collect this day's records up to the next header (records before any
    // header — not expected, but handled — form their own section).
    final dayRecords = <TimeEntry>[];
    while (i < entries.length && !entries[i].isHeader) {
      dayRecords.add(entries[i]);
      i++;
    }
    _emitGroups(out, dayRecords, expanded);
  }
  return out;
}

void _emitGroups(
    List<EntryListRow> out, List<TimeEntry> dayRecords, Set<String> expanded) {
  final order = <int>[];
  final buckets = <int, List<TimeEntry>>{};
  for (final e in dayRecords) {
    final n = issueNumber(e);
    final bucket = buckets[n];
    if (bucket == null) {
      order.add(n);
      buckets[n] = [e];
    } else {
      bucket.add(e);
    }
  }

  for (final n in order) {
    final group = buckets[n]!;
    final sample = group.first;
    final key = groupKeyFor(sample);
    final isOpen = expanded.contains(key);
    out.add(IssueGroupRow(
      groupKey: key,
      sample: sample,
      count: group.length,
      totalSeconds: groupTotalSeconds(group),
      expanded: isOpen,
    ));
    if (isOpen) {
      for (final e in group) {
        out.add(RecordRow(e, grouped: true));
      }
    }
  }
}

/// Whether a hairline divider should follow row [i]. One predicate shared by
/// both the iOS sliver path and the `ListView.separated` path: a divider trails
/// every record and every collapsed group header, but never a day header, an
/// expanded group header (it sits flush against its first child), or the last
/// row.
bool dividerAfterRow(List<EntryListRow> rows, int i) {
  if (i < 0 || i >= rows.length - 1) return false;
  return switch (rows[i]) {
    DayHeaderRow() => false,
    IssueGroupRow(:final expanded) => !expanded,
    RecordRow() => true,
  };
}
