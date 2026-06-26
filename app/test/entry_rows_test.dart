import 'package:flutter_test/flutter_test.dart';
import 'package:redtick/src/models/time_entry.dart';
import 'package:redtick/src/ui/widgets/entry_rows.dart';

/// A completed record on [start] for Redmine [issue] (0 ⇒ no issue), lasting
/// [seconds] (negative ⇒ a running entry, as the core encodes it).
TimeEntry rec({
  required int id,
  required int issue,
  required int seconds,
  required DateTime start,
  String desc = 'work',
}) {
  final startEpoch = start.millisecondsSinceEpoch ~/ 1000;
  return TimeEntry(
    id: id,
    guid: 'g$id',
    description: desc,
    durationInSeconds: seconds,
    duration: formatDuration(seconds),
    projectLabel: 'Proj',
    taskLabel: issue == 0 ? '' : '#$issue: Subject $issue',
    clientLabel: '',
    color: '#3b82f6',
    tags: '',
    billable: false,
    started: startEpoch,
    ended: startEpoch + (seconds > 0 ? seconds : 0),
    startTimeString: '10:00',
    endTimeString: '11:00',
    isHeader: false,
    dateHeader: '',
    dateDuration: '',
    unsynced: false,
    error: '',
    activityId: 0,
  );
}

TimeEntry header(String label) => TimeEntry(
      id: 0,
      guid: '',
      description: '',
      durationInSeconds: 0,
      duration: '',
      projectLabel: '',
      taskLabel: '',
      clientLabel: '',
      color: '',
      tags: '',
      billable: false,
      started: 0,
      ended: 0,
      startTimeString: '',
      endTimeString: '',
      isHeader: true,
      dateHeader: label,
      dateDuration: '',
      unsynced: false,
      error: '',
      activityId: 0,
    );

void main() {
  // Two days. Within a day records arrive newest-first; the same issue (23409)
  // appears twice, non-contiguously, on day 1.
  final day1 = DateTime(2024, 6, 26);
  final day2 = DateTime(2024, 6, 25);
  final r1 = rec(id: 1, issue: 23409, seconds: 600, start: day1.add(const Duration(hours: 12)));
  final r2 = rec(id: 2, issue: 23567, seconds: 300, start: day1.add(const Duration(hours: 11)));
  final r3 = rec(id: 3, issue: 23409, seconds: 1200, start: day1.add(const Duration(hours: 9)));
  final r4 = rec(id: 4, issue: 0, seconds: 120, start: day1.add(const Duration(hours: 8)));
  final r5 = rec(id: 5, issue: 23409, seconds: 200, start: day2.add(const Duration(hours: 15)));

  final incoming = [header('Today'), r1, r2, r3, r4, header('Yesterday'), r5];

  final k1 = groupKeyFor(r1); // "2024-6-26|23409"
  final k2 = groupKeyFor(r2); // "2024-6-26|23567"
  final k0 = groupKeyFor(r4); // "2024-6-26|0"
  final k5 = groupKeyFor(r5); // "2024-6-25|23409"

  group('groupKeyFor', () {
    test('keys are day-scoped: same issue on different days differs', () {
      expect(k1, '2024-6-26|23409');
      expect(k5, '2024-6-25|23409');
      expect(k1, isNot(k5));
    });
    test('no-issue records key on issue 0', () => expect(k0, '2024-6-26|0'));
  });

  group('flat mode', () {
    test('maps 1:1 with no groups', () {
      final rows = buildEntryRows(incoming, groupByIssue: false, expanded: {});
      expect(rows.length, incoming.length);
      expect(rows.whereType<IssueGroupRow>(), isEmpty);
      expect(rows.whereType<DayHeaderRow>().length, 2);
      expect(rows.whereType<RecordRow>().length, 5);
      expect(rows.whereType<RecordRow>().every((r) => !r.grouped), isTrue);
    });
  });

  group('grouped mode — collapsed by default', () {
    final rows = buildEntryRows(incoming, groupByIssue: true, expanded: {});

    test('reveals no records while collapsed', () {
      expect(rows.whereType<RecordRow>(), isEmpty);
    });

    test('groups are ordered by most-recent record within each day', () {
      final day1Groups = rows
          .whereType<IssueGroupRow>()
          .where((g) => g.groupKey.startsWith('2024-6-26|'))
          .map((g) => g.groupKey)
          .toList();
      expect(day1Groups, [k1, k2, k0]); // 23409, 23567, No issue
    });

    test('a repeated issue is one group with summed total and count', () {
      final g = rows.whereType<IssueGroupRow>().firstWhere((g) => g.groupKey == k1);
      expect(g.count, 2);
      expect(g.totalSeconds, 1800); // 600 + 1200
      expect(g.sample.id, r1.id); // newest record is the sample
    });

    test('single-record issues are still groups (arrow always present)', () {
      final g = rows.whereType<IssueGroupRow>().firstWhere((g) => g.groupKey == k5);
      expect(g.count, 1);
      expect(g.totalSeconds, 200);
    });

    test('day headers pass through untouched', () {
      final headers = rows.whereType<DayHeaderRow>().toList();
      expect(headers.map((h) => h.entry.dateHeader), ['Today', 'Yesterday']);
    });
  });

  group('grouped mode — expanded', () {
    test('an expanded group reveals its records newest-first; others stay shut', () {
      final rows = buildEntryRows(incoming, groupByIssue: true, expanded: {k1});
      final records = rows.whereType<RecordRow>().toList();
      expect(records.map((r) => r.entry.id), [r1.id, r3.id]);
      expect(records.every((r) => r.grouped), isTrue);
      // The group itself reports expanded.
      expect(rows.whereType<IssueGroupRow>().firstWhere((g) => g.groupKey == k1).expanded, isTrue);
    });
  });

  group('running entries (negative duration) are skipped in totals', () {
    test('total sums only completed records', () {
      final running = rec(id: 9, issue: 999, seconds: -17000, start: day1.add(const Duration(hours: 13)));
      final done = rec(id: 10, issue: 999, seconds: 600, start: day1.add(const Duration(hours: 7)));
      final rows = buildEntryRows(
          [header('Today'), running, done], groupByIssue: true, expanded: {});
      final g = rows.whereType<IssueGroupRow>().single;
      expect(g.count, 2);
      expect(g.totalSeconds, 600); // -17000 skipped
    });
  });

  group('formatDuration', () {
    test('h:mm:ss with zero-padding', () {
      expect(formatDuration(1800), '0:30:00');
      expect(formatDuration(200), '0:03:20');
      expect(formatDuration(3661), '1:01:01');
      expect(formatDuration(-5), '0:00:00');
    });
  });

  group('dividerAfterRow', () {
    test('collapsed: trails group headers, not day headers, not the last row', () {
      final rows = buildEntryRows(incoming, groupByIssue: true, expanded: {});
      expect(rows[0], isA<DayHeaderRow>());
      expect(dividerAfterRow(rows, 0), isFalse); // after day header
      expect(rows[1], isA<IssueGroupRow>());
      expect(dividerAfterRow(rows, 1), isTrue); // after collapsed group
      expect(dividerAfterRow(rows, rows.length - 1), isFalse); // after last row
    });

    test('expanded: no divider before the first child; dividers between records', () {
      final rows = buildEntryRows(incoming, groupByIssue: true, expanded: {k1});
      final gi = rows.indexWhere((r) => r is IssueGroupRow && r.groupKey == k1);
      expect((rows[gi] as IssueGroupRow).expanded, isTrue);
      expect(dividerAfterRow(rows, gi), isFalse); // expanded header is flush
      expect(rows[gi + 1], isA<RecordRow>());
      expect(dividerAfterRow(rows, gi + 1), isTrue); // between r1 and r3
      expect(rows[gi + 2], isA<RecordRow>());
      expect(dividerAfterRow(rows, gi + 2), isTrue); // last child → next group
    });
  });
}
