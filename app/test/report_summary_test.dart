import 'package:flutter_test/flutter_test.dart';
import 'package:redtick/src/models/time_entry.dart';
import 'package:redtick/src/state/report_summary.dart';

/// Wednesday 2026-06-24 12:00 (DateTime.weekday == 3). Its week runs Mon
/// 2026-06-22 → Sun 2026-06-28; its month is June 2026; last-30 is
/// 2026-05-26 → 2026-06-24 inclusive.
final _now = DateTime(2026, 6, 24, 12);

int _secs(DateTime d) => d.millisecondsSinceEpoch ~/ 1000;

TimeEntry _entry({
  required DateTime at,
  int durationInSeconds = 3600,
  String projectLabel = 'Alpha',
  String color = '#3b82f6',
  bool isHeader = false,
}) =>
    TimeEntry(
      id: 1,
      guid: 'g',
      description: '',
      durationInSeconds: durationInSeconds,
      duration: '',
      projectLabel: projectLabel,
      taskLabel: '',
      clientLabel: '',
      color: color,
      tags: '',
      billable: false,
      started: _secs(at),
      ended: _secs(at) + (durationInSeconds > 0 ? durationInSeconds : 0),
      startTimeString: '',
      endTimeString: '',
      isHeader: isHeader,
      dateHeader: '',
      dateDuration: '',
      unsynced: false,
      error: '',
      activityId: 0,
    );

void main() {
  group('ReportPeriod.rangeFor', () {
    test('week is Monday 00:00 → next Monday (mid-week now)', () {
      final (start, end) = ReportPeriod.week.rangeFor(_now); // Wed
      expect(start, DateTime(2026, 6, 22));
      expect(end, DateTime(2026, 6, 29));
    });

    test('week anchors to Monday even when now is Sunday', () {
      final sunday = DateTime(2026, 6, 28, 23); // weekday == 7
      final (start, end) = ReportPeriod.week.rangeFor(sunday);
      expect(start, DateTime(2026, 6, 22));
      expect(end, DateTime(2026, 6, 29));
    });

    test('month is the 1st → 1st of next month', () {
      final (start, end) = ReportPeriod.month.rangeFor(_now);
      expect(start, DateTime(2026, 6, 1));
      expect(end, DateTime(2026, 7, 1));
    });

    test('last30 is today-29 → tomorrow', () {
      final (start, end) = ReportPeriod.last30.rangeFor(_now);
      expect(start, DateTime(2026, 5, 26));
      expect(end, DateTime(2026, 6, 25));
    });
  });

  group('ReportPeriod.label', () {
    test('week within one month', () {
      expect(ReportPeriod.week.label(_now), '22–28 Jun');
    });

    test('month', () {
      expect(ReportPeriod.month.label(_now), 'June 2026');
    });

    test('last30', () {
      expect(ReportPeriod.last30.label(_now), 'Last 30 days');
    });
  });

  group('buildReportSummary', () {
    test('empty input → zeroed summary', () {
      final s = buildReportSummary(const [], ReportPeriod.week, now: _now);
      expect(s.totalSeconds, 0);
      expect(s.entryCount, 0);
      expect(s.projects, isEmpty);
    });

    test('groups by project, sums, sorts longest-first', () {
      final entries = [
        _entry(at: DateTime(2026, 6, 22, 9), durationInSeconds: 3600), // Alpha
        _entry(at: DateTime(2026, 6, 24, 14), durationInSeconds: 7200), // Alpha
        _entry(
            at: DateTime(2026, 6, 23, 10),
            durationInSeconds: 1800,
            projectLabel: 'Beta'),
      ];
      final s = buildReportSummary(entries, ReportPeriod.week, now: _now);
      expect(s.totalSeconds, 3600 + 7200 + 1800);
      expect(s.entryCount, 3);
      expect(s.projects.map((p) => p.project).toList(), ['Alpha', 'Beta']);
      expect(s.projects.first.seconds, 10800);
      expect(s.projects.first.color, '#3b82f6');
    });

    test('excludes day-header rows and running (negative) entries', () {
      final entries = [
        _entry(at: DateTime(2026, 6, 23, 9), durationInSeconds: 3600),
        _entry(at: DateTime(2026, 6, 23), isHeader: true), // header
        _entry(at: DateTime(2026, 6, 23, 11), durationInSeconds: -50), // running
      ];
      final s = buildReportSummary(entries, ReportPeriod.week, now: _now);
      expect(s.entryCount, 1);
      expect(s.totalSeconds, 3600);
      expect(s.projects.single.seconds, 3600);
    });

    test('week excludes entries outside the current week', () {
      final entries = [
        _entry(at: DateTime(2026, 6, 22, 9)), // in week
        _entry(at: DateTime(2026, 6, 15, 9), projectLabel: 'Gamma'), // last week
      ];
      final s = buildReportSummary(entries, ReportPeriod.week, now: _now);
      expect(s.entryCount, 1);
      expect(s.projects.map((p) => p.project), ['Alpha']);
    });

    test('month includes the whole month but not other months', () {
      final entries = [
        _entry(at: DateTime(2026, 6, 1, 0)), // first instant of June → in
        _entry(at: DateTime(2026, 6, 15, 9), projectLabel: 'Gamma'),
        _entry(at: DateTime(2026, 5, 31, 23), projectLabel: 'May'), // out
        _entry(at: DateTime(2026, 7, 1, 0), projectLabel: 'July'), // out (end excl)
      ];
      final s = buildReportSummary(entries, ReportPeriod.month, now: _now);
      expect(s.entryCount, 2);
      expect(
          s.projects.map((p) => p.project).toSet(), {'Alpha', 'Gamma'});
    });

    test('last30 reaches into late May but month does not', () {
      final lateMay = _entry(
          at: DateTime(2026, 5, 28, 10),
          durationInSeconds: 3600,
          projectLabel: 'Echo');
      final june = _entry(at: DateTime(2026, 6, 20, 10), durationInSeconds: 3600);

      final month = buildReportSummary([lateMay, june], ReportPeriod.month,
          now: _now);
      expect(month.entryCount, 1); // only the June entry

      final last30 = buildReportSummary([lateMay, june], ReportPeriod.last30,
          now: _now);
      expect(last30.entryCount, 2);
      expect(last30.totalSeconds, 7200);
    });

    test('empty project label buckets as "No project"', () {
      final s = buildReportSummary(
        [_entry(at: DateTime(2026, 6, 23, 9), projectLabel: '')],
        ReportPeriod.week,
        now: _now,
      );
      expect(s.projects.single.project, 'No project');
    });
  });
}
