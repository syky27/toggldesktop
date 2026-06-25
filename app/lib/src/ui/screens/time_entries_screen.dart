import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/time_entry.dart';
import '../../state/providers.dart';
import '../theme.dart';
import '../widgets/time_entry_tile.dart';
import '../widgets/timer_bar.dart';
import 'time_entry_editor_screen.dart';

/// Main screen (design §3.1/§3.3/§3.4): running-timer hero on top, day-grouped
/// entry list below.
class TimeEntriesScreen extends ConsumerWidget {
  const TimeEntriesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final entriesAsync = ref.watch(timeEntriesProvider);
    return ColoredBox(
      color: Theme.of(context).colorScheme.surface,
      child: SafeArea(
        child: Column(
          children: [
            const TimerBar(),
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
      return Center(
        child: Text('No time entries yet',
            style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant)),
      );
    }
    final hairline = Theme.of(context).extension<RedtickTokens>()!.hairline;

    return ListView.separated(
      itemCount: entries.length,
      separatorBuilder: (_, i) =>
          entries[i].isHeader ? const SizedBox.shrink() : Divider(height: 1, color: hairline),
      itemBuilder: (context, i) {
        final e = entries[i];
        if (e.isHeader) return _DayHeader(entry: e);
        return TimeEntryTile(
          entry: e,
          onContinue: () => ref.read(coreServiceProvider).continueEntry(e.guid),
          onTap: () => showEntryEditor(context, e),
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
