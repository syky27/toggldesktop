import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../state/providers.dart';
import '../../state/report_summary.dart';
import '../theme.dart';
import '../widgets/entry_bits.dart';
import '../widgets/entry_rows.dart' show formatDuration;

/// Statistics page: how much time was tracked in the selected window — a grand
/// total plus a per-project breakdown — computed purely from the locally cached
/// time-entry list (no extra Redmine calls).
class ReportsScreen extends ConsumerWidget {
  const ReportsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cs = Theme.of(context).colorScheme;
    final entriesAsync = ref.watch(timeEntriesProvider);
    final period = ref.watch(reportPeriodProvider);

    return ColoredBox(
      color: cs.surface,
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _Header(period: period),
            Expanded(
              child: entriesAsync.when(
                loading: () =>
                    const Center(child: CircularProgressIndicator()),
                error: (e, _) => Center(child: Text('Error: $e')),
                data: (entries) {
                  final summary = buildReportSummary(entries, period);
                  if (summary.totalSeconds == 0) return const _EmptyState();
                  return _ReportBody(summary: summary, period: period);
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Header extends ConsumerWidget {
  const _Header({required this.period});
  final ReportPeriod period;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = Theme.of(context).extension<RedtickTokens>()!;
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.fromLTRB(22, 16, 16, 12),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: t.hairline)),
      ),
      child: Row(
        children: [
          Text('Reports',
              style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: cs.onSurface)),
          const Spacer(),
          _PeriodToggle(
            period: period,
            onChanged: (p) => ref.read(reportPeriodProvider.notifier).set(p),
          ),
        ],
      ),
    );
  }
}

/// A three-segment pill (Week / Month / 30 days), styled like the timer screen's
/// view toggle rather than the chunky Material `SegmentedButton`.
class _PeriodToggle extends StatelessWidget {
  const _PeriodToggle({required this.period, required this.onChanged});
  final ReportPeriod period;
  final ValueChanged<ReportPeriod> onChanged;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).extension<RedtickTokens>()!;
    return Container(
      padding: const EdgeInsets.all(2),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(9),
        border: Border.all(color: t.hairline),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final p in ReportPeriod.values)
            _PeriodSegment(
              label: p.shortLabel,
              selected: p == period,
              onTap: () => onChanged(p),
            ),
        ],
      ),
    );
  }
}

class _PeriodSegment extends StatelessWidget {
  const _PeriodSegment({
    required this.label,
    required this.selected,
    required this.onTap,
  });
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).extension<RedtickTokens>()!;
    final cs = Theme.of(context).colorScheme;
    return Material(
      color: selected ? t.accentSoft : Colors.transparent,
      borderRadius: BorderRadius.circular(7),
      child: InkWell(
        borderRadius: BorderRadius.circular(7),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 13,
              fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
              color: selected ? cs.primary : cs.onSurfaceVariant,
            ),
          ),
        ),
      ),
    );
  }
}

class _ReportBody extends StatelessWidget {
  const _ReportBody({required this.summary, required this.period});
  final ReportSummary summary;
  final ReportPeriod period;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(22, 18, 22, 24),
      children: [
        _SummaryCard(summary: summary, period: period),
        const SizedBox(height: 20),
        for (final p in summary.projects)
          Padding(
            padding: const EdgeInsets.only(bottom: 16),
            child: _ProjectBarRow(total: p, grandTotal: summary.totalSeconds),
          ),
      ],
    );
  }
}

class _SummaryCard extends StatelessWidget {
  const _SummaryCard({required this.summary, required this.period});
  final ReportSummary summary;
  final ReportPeriod period;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).extension<RedtickTokens>()!;
    final cs = Theme.of(context).colorScheme;
    final projects = summary.projects.length;
    return Container(
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 18),
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(13),
        border: Border.all(color: t.hairline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            period.label(DateTime.now()).toUpperCase(),
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.5,
              color: t.faint,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            formatDuration(summary.totalSeconds),
            style: RedtickTheme.mono(
              fontSize: 30,
              fontWeight: FontWeight.w700,
              color: cs.onSurface,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            '${summary.entryCount} ${summary.entryCount == 1 ? 'entry' : 'entries'}'
            ' · $projects ${projects == 1 ? 'project' : 'projects'}',
            style: TextStyle(fontSize: 12.5, color: cs.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}

class _ProjectBarRow extends StatelessWidget {
  const _ProjectBarRow({required this.total, required this.grandTotal});
  final ProjectTotal total;
  final int grandTotal;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).extension<RedtickTokens>()!;
    final cs = Theme.of(context).colorScheme;
    final fraction = grandTotal == 0 ? 0.0 : total.seconds / grandTotal;
    final pct = (fraction * 100).round();
    final barColor = entryDotColor(total.color) ?? cs.primary;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            ProjectDot(total.color, size: 9),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                total.project,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w600,
                  color: cs.onSurface,
                ),
              ),
            ),
            const SizedBox(width: 8),
            Text(
              formatDuration(total.seconds),
              style: RedtickTheme.mono(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: cs.onSurface,
              ),
            ),
            const SizedBox(width: 8),
            SizedBox(
              width: 40,
              child: Text(
                '$pct%',
                textAlign: TextAlign.right,
                style: TextStyle(fontSize: 12.5, color: cs.onSurfaceVariant),
              ),
            ),
          ],
        ),
        const SizedBox(height: 7),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: Container(
            height: 6,
            color: t.hairline,
            child: FractionallySizedBox(
              alignment: Alignment.centerLeft,
              widthFactor: fraction.clamp(0.0, 1.0),
              child: Container(color: barColor),
            ),
          ),
        ),
      ],
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).extension<RedtickTokens>()!;
    final cs = Theme.of(context).colorScheme;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.bar_chart_outlined, size: 40, color: t.faint),
          const SizedBox(height: 12),
          Text(
            'No time tracked in this period',
            style: TextStyle(color: cs.onSurfaceVariant, fontSize: 14),
          ),
        ],
      ),
    );
  }
}
