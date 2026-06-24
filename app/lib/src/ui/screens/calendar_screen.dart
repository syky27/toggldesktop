import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/time_entry.dart';
import '../../state/providers.dart';
import 'time_entry_editor_screen.dart';

/// Day calendar view (FP-46): a 24-hour vertical grid with entries positioned by
/// their start/end, tap-to-edit. Mirrors the `calendarview` added on the Redmine
/// fork. Drag-to-move and edge-resize are a follow-up enhancement (the core
/// setters `setStart`/`setEnd` are already wired in CoreService to support them).
class CalendarScreen extends ConsumerStatefulWidget {
  const CalendarScreen({super.key});

  @override
  ConsumerState<CalendarScreen> createState() => _CalendarScreenState();
}

class _CalendarScreenState extends ConsumerState<CalendarScreen> {
  static const double _hourHeight = 56;

  DateTime _day = _dateOnly(DateTime.now());

  static DateTime _dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

  bool _onDay(TimeEntry e) {
    if (e.isHeader || e.started == 0) return false;
    final start =
        DateTime.fromMillisecondsSinceEpoch(e.started * 1000).toLocal();
    return _dateOnly(start) == _day;
  }

  @override
  Widget build(BuildContext context) {
    final entries = (ref.watch(timeEntriesProvider).asData?.value ?? [])
        .where(_onDay)
        .toList();

    return SafeArea(
      child: Column(
        children: [
          _DayHeaderBar(
            day: _day,
            onPrev: () =>
                setState(() => _day = _day.subtract(const Duration(days: 1))),
            onNext: () =>
                setState(() => _day = _day.add(const Duration(days: 1))),
            onToday: () => setState(() => _day = _dateOnly(DateTime.now())),
          ),
          const Divider(height: 1),
          Expanded(
            child: SingleChildScrollView(
              child: SizedBox(
                height: _hourHeight * 24,
                child: Stack(
                  children: [
                    ..._hourLines(context),
                    ...entries.map((e) => _block(context, e)),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  List<Widget> _hourLines(BuildContext context) {
    final style = Theme.of(context).textTheme.bodySmall;
    return [
      for (int h = 0; h < 24; h++)
        Positioned(
          top: h * _hourHeight,
          left: 0,
          right: 0,
          child: SizedBox(
            height: _hourHeight,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: 48,
                  child: Text('${h.toString().padLeft(2, '0')}:00',
                      style: style, textAlign: TextAlign.right),
                ),
                const SizedBox(width: 8),
                const Expanded(child: Divider(height: 1)),
              ],
            ),
          ),
        ),
    ];
  }

  Widget _block(BuildContext context, TimeEntry e) {
    final start =
        DateTime.fromMillisecondsSinceEpoch(e.started * 1000).toLocal();
    final end = e.ended > 0
        ? DateTime.fromMillisecondsSinceEpoch(e.ended * 1000).toLocal()
        : start.add(const Duration(minutes: 30));
    final top = (start.hour + start.minute / 60) * _hourHeight;
    final height =
        (end.difference(start).inMinutes / 60 * _hourHeight).clamp(18.0, 24 * _hourHeight);
    final color = Theme.of(context).colorScheme.primaryContainer;

    return Positioned(
      top: top,
      left: 64,
      right: 8,
      height: height.toDouble(),
      child: Material(
        color: color,
        borderRadius: BorderRadius.circular(6),
        child: InkWell(
          borderRadius: BorderRadius.circular(6),
          onTap: () => Navigator.of(context).push(MaterialPageRoute(
            builder: (_) => TimeEntryEditorScreen(entry: e),
          )),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            child: Text(
              e.description.isNotEmpty
                  ? e.description
                  : (e.projectLabel.isNotEmpty ? e.projectLabel : 'Entry'),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
        ),
      ),
    );
  }
}

class _DayHeaderBar extends StatelessWidget {
  const _DayHeaderBar({
    required this.day,
    required this.onPrev,
    required this.onNext,
    required this.onToday,
  });

  final DateTime day;
  final VoidCallback onPrev;
  final VoidCallback onNext;
  final VoidCallback onToday;

  @override
  Widget build(BuildContext context) {
    final label = '${day.year}-${day.month.toString().padLeft(2, '0')}-'
        '${day.day.toString().padLeft(2, '0')}';
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: Row(
        children: [
          IconButton(icon: const Icon(Icons.chevron_left), onPressed: onPrev),
          Expanded(
            child: Text(label,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.titleMedium),
          ),
          IconButton(icon: const Icon(Icons.chevron_right), onPressed: onNext),
          TextButton(onPressed: onToday, child: const Text('Today')),
        ],
      ),
    );
  }
}
