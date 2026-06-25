import 'dart:io' show Platform;

import 'package:flutter/cupertino.dart' show CupertinoSliverRefreshControl;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/time_entry.dart';
import '../../state/multi_task_settings.dart';
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

/// The day-grouped entry list with a **platform-native** pull-to-refresh on
/// mobile (Cupertino rubber-band on iOS, Material indicator on Android). Desktop
/// has no pull gesture — it refreshes from the sidebar button — so it renders a
/// plain list.
class _EntryList extends ConsumerWidget {
  const _EntryList({required this.entries});
  final List<TimeEntry> entries;

  Future<void> _refresh(WidgetRef ref) =>
      ref.read(coreServiceProvider).refresh();

  Widget _tile(BuildContext context, WidgetRef ref, TimeEntry e) {
    if (e.isHeader) return _DayHeader(entry: e);
    return TimeEntryTile(
      entry: e,
      onContinue: () {
        final allowConcurrent =
            ref.read(multiTaskSettingsProvider).allowConcurrent;
        ref
            .read(coreServiceProvider)
            .continueEntry(e.guid, stopOthers: !allowConcurrent);
      },
      onTap: () => showEntryEditor(context, e),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cs = Theme.of(context).colorScheme;
    final hairline = Theme.of(context).extension<RedtickTokens>()!.hairline;

    if (entries.isEmpty) {
      final empty = Center(
        child: Text('No time entries yet',
            style: TextStyle(color: cs.onSurfaceVariant)),
      );
      if (Platform.isIOS) {
        return CustomScrollView(
          slivers: [
            CupertinoSliverRefreshControl(onRefresh: () => _refresh(ref)),
            SliverFillRemaining(hasScrollBody: false, child: empty),
          ],
        );
      }
      if (Platform.isAndroid) {
        return RefreshIndicator(
          onRefresh: () => _refresh(ref),
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
          CupertinoSliverRefreshControl(onRefresh: () => _refresh(ref)),
          SliverList(
            delegate: SliverChildBuilderDelegate(
              (context, i) {
                final e = entries[i];
                final divider = !e.isHeader && i < entries.length - 1;
                return Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _tile(context, ref, e),
                    if (divider) Divider(height: 1, color: hairline),
                  ],
                );
              },
              childCount: entries.length,
            ),
          ),
        ],
      );
    }

    final list = ListView.separated(
      physics:
          Platform.isAndroid ? const AlwaysScrollableScrollPhysics() : null,
      itemCount: entries.length,
      separatorBuilder: (_, i) => entries[i].isHeader
          ? const SizedBox.shrink()
          : Divider(height: 1, color: hairline),
      itemBuilder: (context, i) => _tile(context, ref, entries[i]),
    );
    // Android: Material drop-down indicator. Desktop: plain list (sidebar button).
    if (Platform.isAndroid) {
      return RefreshIndicator(onRefresh: () => _refresh(ref), child: list);
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
