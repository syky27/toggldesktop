import 'dart:io' show Platform;

import 'package:flutter/cupertino.dart' show CupertinoSliverRefreshControl;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/time_entry.dart';
import '../../state/multi_task_settings.dart';
import '../../state/providers.dart';
import '../../state/view_settings.dart';
import '../theme.dart';
import '../widgets/entry_bits.dart';
import '../widgets/entry_rows.dart';
import '../widgets/time_entry_tile.dart';
import '../widgets/timer_bar.dart';
import 'time_entry_editor_screen.dart';

/// Main screen (design §3.1/§3.3/§3.4): running-timer hero on top, a flat/grouped
/// view toggle, then the day-grouped entry list below.
class TimeEntriesScreen extends ConsumerWidget {
  const TimeEntriesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final entriesAsync = ref.watch(timeEntriesProvider);
    final groupByIssue = ref.watch(viewSettingsProvider).groupByIssue;
    return ColoredBox(
      color: Theme.of(context).colorScheme.surface,
      child: SafeArea(
        child: Column(
          children: [
            const TimerBar(),
            const _ListViewToolbar(),
            Expanded(
              child: entriesAsync.when(
                loading: () =>
                    const Center(child: CircularProgressIndicator()),
                error: (e, _) => Center(child: Text('Error: $e')),
                data: (entries) =>
                    _EntryList(entries: entries, groupByIssue: groupByIssue),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Slim chrome strip between the timer hero and the list, carrying the
/// flat ↔ grouped-by-issue view toggle (right-aligned). Always visible — even
/// while the list is empty/loading — so the toggle is reachable everywhere.
class _ListViewToolbar extends ConsumerWidget {
  const _ListViewToolbar();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = Theme.of(context).extension<RedtickTokens>()!;
    final grouped = ref.watch(viewSettingsProvider).groupByIssue;
    return Container(
      padding: const EdgeInsets.fromLTRB(22, 6, 14, 6),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: t.hairline)),
      ),
      child: Row(
        children: [
          const Spacer(),
          _ViewToggle(
            grouped: grouped,
            onChanged:
                ref.read(viewSettingsProvider.notifier).setGroupByIssue,
          ),
        ],
      ),
    );
  }
}

/// A lean two-segment pill (flat list / group by issue), styled like the
/// sidebar nav items rather than the chunky Material `SegmentedButton`.
class _ViewToggle extends StatelessWidget {
  const _ViewToggle({required this.grouped, required this.onChanged});
  final bool grouped;
  final ValueChanged<bool> onChanged;

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
          _ViewToggleSegment(
            icon: Icons.view_agenda_outlined,
            tooltip: 'Flat list',
            selected: !grouped,
            onTap: () => onChanged(false),
          ),
          _ViewToggleSegment(
            icon: Icons.account_tree_outlined,
            tooltip: 'Group by issue',
            selected: grouped,
            onTap: () => onChanged(true),
          ),
        ],
      ),
    );
  }
}

class _ViewToggleSegment extends StatelessWidget {
  const _ViewToggleSegment({
    required this.icon,
    required this.tooltip,
    required this.selected,
    required this.onTap,
  });
  final IconData icon;
  final String tooltip;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).extension<RedtickTokens>()!;
    final cs = Theme.of(context).colorScheme;
    return Tooltip(
      message: tooltip,
      child: Material(
        color: selected ? t.accentSoft : Colors.transparent,
        borderRadius: BorderRadius.circular(7),
        child: InkWell(
          borderRadius: BorderRadius.circular(7),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            child: Icon(icon,
                size: 17,
                color: selected ? cs.primary : cs.onSurfaceVariant),
          ),
        ),
      ),
    );
  }
}

/// The entry list with a **platform-native** pull-to-refresh on mobile
/// (Cupertino rubber-band on iOS, Material indicator on Android). Desktop has no
/// pull gesture — it refreshes from the sidebar button — so it renders a plain
/// list. Stateful so the set of expanded issue groups survives the frequent
/// `timeEntriesProvider` re-emissions (keys are stable per day+issue).
class _EntryList extends ConsumerStatefulWidget {
  const _EntryList({required this.entries, required this.groupByIssue});
  final List<TimeEntry> entries;
  final bool groupByIssue;

  @override
  ConsumerState<_EntryList> createState() => _EntryListState();
}

class _EntryListState extends ConsumerState<_EntryList> {
  /// Group keys (`"$dayKey|$issueNumber"`) currently expanded. Empty ⇒ all
  /// collapsed, the default.
  final Set<String> _expanded = {};

  Future<void> _refresh() => ref.read(coreServiceProvider).refresh();

  void _toggle(String key) => setState(() {
        if (!_expanded.remove(key)) _expanded.add(key);
      });

  void _continue(TimeEntry e) {
    final allowConcurrent =
        ref.read(multiTaskSettingsProvider).allowConcurrent;
    ref
        .read(coreServiceProvider)
        .continueEntry(e.guid, stopOthers: !allowConcurrent);
  }

  Widget _rowWidget(
      BuildContext context, EntryListRow row, bool showTimestamps) {
    switch (row) {
      case DayHeaderRow(:final entry):
        return _DayHeader(entry: entry);
      case IssueGroupRow():
        return _IssueGroupHeader(
          row: row,
          onToggle: () => _toggle(row.groupKey),
          onContinue: () => _continue(row.sample),
        );
      case RecordRow(:final entry, :final grouped):
        final tile = TimeEntryTile(
          entry: entry,
          onContinue: () => _continue(entry),
          onTap: () => showEntryEditor(context, entry),
          showTimestamps: showTimestamps,
        );
        return grouped
            ? Padding(padding: const EdgeInsets.only(left: 24), child: tile)
            : tile;
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final hairline = Theme.of(context).extension<RedtickTokens>()!.hairline;

    final rows = buildEntryRows(widget.entries,
        groupByIssue: widget.groupByIssue, expanded: _expanded);
    final showTimestamps = ref.watch(customFieldConfigProvider).asData?.value
            .sendCustomFields ??
        ref.read(coreServiceProvider).sendCustomFields;

    if (rows.isEmpty) {
      final empty = Center(
        child: Text('No time entries yet',
            style: TextStyle(color: cs.onSurfaceVariant)),
      );
      if (Platform.isIOS) {
        return CustomScrollView(
          slivers: [
            CupertinoSliverRefreshControl(onRefresh: _refresh),
            SliverFillRemaining(hasScrollBody: false, child: empty),
          ],
        );
      }
      if (Platform.isAndroid) {
        return RefreshIndicator(
          onRefresh: _refresh,
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            children: [
              SizedBox(
                  height: MediaQuery.sizeOf(context).height * 0.6, child: empty),
            ],
          ),
        );
      }
      return empty;
    }

    // iOS: native rubber-band refresh over a sliver list (manual dividers).
    if (Platform.isIOS) {
      return CustomScrollView(
        slivers: [
          CupertinoSliverRefreshControl(onRefresh: _refresh),
          SliverList(
            delegate: SliverChildBuilderDelegate(
              (context, i) {
                final divider = dividerAfterRow(rows, i);
                return Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _rowWidget(context, rows[i], showTimestamps),
                    if (divider) Divider(height: 1, color: hairline),
                  ],
                );
              },
              childCount: rows.length,
            ),
          ),
        ],
      );
    }

    final list = ListView.separated(
      physics:
          Platform.isAndroid ? const AlwaysScrollableScrollPhysics() : null,
      itemCount: rows.length,
      separatorBuilder: (_, i) => dividerAfterRow(rows, i)
          ? Divider(height: 1, color: hairline)
          : const SizedBox.shrink(),
      itemBuilder: (context, i) => _rowWidget(context, rows[i], showTimestamps),
    );
    // Android: Material drop-down indicator. Desktop: plain list (sidebar button).
    if (Platform.isAndroid) {
      return RefreshIndicator(onRefresh: _refresh, child: list);
    }
    return list;
  }
}

class _DayHeader extends StatelessWidget {
  const _DayHeader({required this.entry});
  final TimeEntry entry;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      color: cs.surfaceContainerHighest,
      padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 7),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(entry.dateHeader.toUpperCase(),
              style: TextStyle(
                  color: cs.onSurfaceVariant,
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.5)),
          Text(entry.dateDuration,
              style: RedtickTheme.mono(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: cs.onSurfaceVariant)),
        ],
      ),
    );
  }
}

/// A collapsible header for all of one day's records that share a Redmine issue:
/// a left expand arrow, the project dot, the issue label, a record-count badge,
/// the group's total duration, and a continue (▶) shortcut for the newest
/// record. Tapping anywhere toggles the group open/closed.
class _IssueGroupHeader extends StatelessWidget {
  const _IssueGroupHeader({
    required this.row,
    required this.onToggle,
    required this.onContinue,
  });
  final IssueGroupRow row;
  final VoidCallback onToggle;
  final VoidCallback onContinue;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final sample = row.sample;
    final title = sample.taskLabel.isNotEmpty
        ? sample.taskLabel
        : (issueNumber(sample) > 0 ? issueRef(sample) : 'No issue');

    return InkWell(
      onTap: onToggle,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 10),
        child: Row(
          children: [
            SizedBox(
              width: 24,
              child: Align(
                alignment: Alignment.centerLeft,
                child: AnimatedRotation(
                  turns: row.expanded ? 0.25 : 0.0,
                  duration: const Duration(milliseconds: 150),
                  child: Icon(Icons.chevron_right,
                      size: 18, color: cs.onSurfaceVariant),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(top: 1),
              child: ProjectDot(sample.color),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Text(
                title,
                style: const TextStyle(
                    fontWeight: FontWeight.w600, fontSize: 14),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
              decoration: BoxDecoration(
                color: cs.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(9),
              ),
              child: Text('${row.count}',
                  style: TextStyle(
                      color: cs.onSurfaceVariant,
                      fontSize: 11,
                      fontWeight: FontWeight.w600)),
            ),
            const SizedBox(width: 14),
            Text(formatDuration(row.totalSeconds),
                style: RedtickTheme.mono(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: cs.onSurface)),
            const SizedBox(width: 8),
            PlayButton(onTap: onContinue),
          ],
        ),
      ),
    );
  }
}
