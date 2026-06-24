import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/time_entry.dart';
import '../../state/providers.dart';
import '../widgets/time_entry_tile.dart';
import '../widgets/timer_bar.dart';
import 'time_entry_editor_screen.dart';

/// The main screen: running-timer bar on top, day-grouped entry list below.
/// Mirrors the Qt `timeentrylistwidget` + `timeentrycellwidget`. Implements
/// FP-42 (timer bar host) and FP-43 (list).
class TimeEntriesScreen extends ConsumerWidget {
  const TimeEntriesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final entriesAsync = ref.watch(timeEntriesProvider);

    return SafeArea(
      child: Column(
        children: [
          const TimerBar(),
          const Divider(height: 1),
          Expanded(
            child: entriesAsync.when(
              loading: () =>
                  const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(child: Text('Error: $e')),
              data: (entries) => _EntryList(entries: entries),
            ),
          ),
        ],
      ),
    );
  }
}

class _EntryList extends ConsumerWidget {
  const _EntryList({required this.entries});
  final List<TimeEntry> entries;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (entries.isEmpty) {
      return const Center(child: Text('No time entries yet'));
    }
    final showLoadMore =
        ref.watch(showLoadMoreProvider).asData?.value ?? false;

    return ListView.separated(
      itemCount: entries.length + (showLoadMore ? 1 : 0),
      separatorBuilder: (_, _) => const Divider(height: 1),
      itemBuilder: (context, i) {
        if (i >= entries.length) {
          return const Padding(
            padding: EdgeInsets.all(16),
            child: Center(child: Text('Load more…')),
          );
        }
        final e = entries[i];
        if (e.isHeader) {
          return _DayHeader(entry: e);
        }
        return TimeEntryTile(
          entry: e,
          onContinue: () =>
              ref.read(coreServiceProvider).continueEntry(e.guid),
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => TimeEntryEditorScreen(entry: e),
            ),
          ),
        );
      },
    );
  }
}

class _DayHeader extends StatelessWidget {
  const _DayHeader({required this.entry});
  final TimeEntry entry;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(entry.dateHeader,
              style: Theme.of(context).textTheme.labelLarge),
          Text(entry.dateDuration,
              style: Theme.of(context).textTheme.labelLarge),
        ],
      ),
    );
  }
}
