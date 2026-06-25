import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/time_entry.dart';
import '../../state/providers.dart';
import '../theme.dart';
import '../widgets/entry_bits.dart';
import '../widgets/issue_picker.dart';
import 'time_entry_editor_screen.dart';

/// Day calendar (design §3.5): a 24-hour grid with project-colored blocks, a
/// now-line, and **drag-to-move + bottom-edge resize** (15-min snap) that persist
/// via `setEntryTimes`. Tap a block to edit.
class CalendarScreen extends ConsumerStatefulWidget {
  const CalendarScreen({super.key});

  @override
  ConsumerState<CalendarScreen> createState() => _CalendarScreenState();
}

class _CalendarScreenState extends ConsumerState<CalendarScreen> {
  static const double _hourHeight = 60;
  static const double _gutter = 56;

  DateTime _day = _dateOnly(DateTime.now());

  // Live drag state (one block at a time).
  String? _dragGuid;
  double _dragTopPx = 0;
  double _dragHeightPx = 0;
  bool _resizing = false;

  static DateTime _dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

  bool _onDay(TimeEntry e) {
    if (e.isHeader || e.started == 0) return false;
    final s = DateTime.fromMillisecondsSinceEpoch(e.started * 1000).toLocal();
    return _dateOnly(s) == _day;
  }

  static String _fmtDur(int seconds) {
    final s = seconds.abs();
    return '${s ~/ 3600}:${((s % 3600) ~/ 60).toString().padLeft(2, '0')}:'
        '${(s % 60).toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final entries = (ref.watch(timeEntriesProvider).asData?.value ?? [])
        .where(_onDay)
        .toList();
    final totalSec = entries.fold<int>(
        0, (a, e) => a + (e.durationInSeconds > 0 ? e.durationInSeconds : 0));

    return ColoredBox(
      color: cs.surface,
      child: SafeArea(
        child: Column(
          children: [
            _HeaderBar(
              day: _day,
              total: _fmtDur(totalSec),
              onPrev: () =>
                  setState(() => _day = _day.subtract(const Duration(days: 1))),
              onNext: () =>
                  setState(() => _day = _day.add(const Duration(days: 1))),
              onToday: () => setState(() => _day = _dateOnly(DateTime.now())),
              onNew: () async {
                final issue = await showIssuePicker(context);
                if (issue == null) return;
                ref.read(coreServiceProvider).startEntryForIssue(
                      issueId: issue.id,
                      projectId: issue.projectId,
                      subject: issue.subject,
                      projectName: issue.projectName,
                      description: issue.subject,
                    );
              },
            ),
            Expanded(
              child: SingleChildScrollView(
                child: SizedBox(
                  height: _hourHeight * 24,
                  child: Stack(
                    children: [
                      ..._hourLines(context),
                      ...entries.map((e) => _block(context, e)),
                      ..._nowLine(context),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  List<Widget> _hourLines(BuildContext context) {
    final t = Theme.of(context).extension<RedtickTokens>()!;
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
                  width: _gutter - 8,
                  child: Text('${h.toString().padLeft(2, '0')}:00',
                      style: RedtickTheme.mono(fontSize: 11, color: t.faint),
                      textAlign: TextAlign.right),
                ),
                const SizedBox(width: 8),
                Expanded(child: Divider(height: 1, color: t.hairline)),
              ],
            ),
          ),
        ),
    ];
  }

  List<Widget> _nowLine(BuildContext context) {
    if (_day != _dateOnly(DateTime.now())) return const [];
    final now = DateTime.now();
    final top = (now.hour * 60 + now.minute) / 60 * _hourHeight;
    final accent = Theme.of(context).colorScheme.primary;
    return [
      Positioned(
        top: top - 4,
        left: _gutter - 12,
        right: 8,
        child: Row(
          children: [
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(color: accent, shape: BoxShape.circle),
            ),
            Expanded(child: Container(height: 1.5, color: accent)),
          ],
        ),
      ),
    ];
  }

  Widget _block(BuildContext context, TimeEntry e) {
    final cs = Theme.of(context).colorScheme;
    final running = e.isRunning;
    final start = DateTime.fromMillisecondsSinceEpoch(
            (running ? -e.durationInSeconds : e.started) * 1000)
        .toLocal();
    final end = (!running && e.ended > 0)
        ? DateTime.fromMillisecondsSinceEpoch(e.ended * 1000).toLocal()
        : (running ? DateTime.now() : start.add(const Duration(minutes: 30)));

    final dragging = _dragGuid == e.guid;
    final baseTop = (start.hour * 60 + start.minute) / 60 * _hourHeight;
    final baseHeight =
        (end.difference(start).inMinutes / 60 * _hourHeight).clamp(22.0, 24 * _hourHeight);
    final top = dragging ? _dragTopPx : baseTop;
    final height = dragging ? _dragHeightPx : baseHeight.toDouble();

    final projColor = entryDotColor(e.color) ?? cs.primary;
    final fill = running
        ? Theme.of(context).extension<RedtickTokens>()!.accentSoft
        : projColor.withValues(alpha: 0.12);
    final edge = running ? cs.primary : projColor;

    return Positioned(
      top: top,
      left: _gutter,
      right: 10,
      height: height,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => showEntryEditor(context, e),
        onVerticalDragStart: (_) => setState(() {
          _dragGuid = e.guid;
          _resizing = false;
          _dragTopPx = baseTop;
          _dragHeightPx = baseHeight.toDouble();
        }),
        onVerticalDragUpdate: (d) {
          if (_dragGuid != e.guid) return;
          setState(() {
            if (_resizing) {
              _dragHeightPx = (_dragHeightPx + d.delta.dy).clamp(22.0, 24 * _hourHeight);
            } else {
              _dragTopPx =
                  (_dragTopPx + d.delta.dy).clamp(0.0, 24 * _hourHeight - _dragHeightPx);
            }
          });
        },
        onVerticalDragEnd: (_) => _commitDrag(e, start, end),
        child: Stack(
          children: [
            Container(
              decoration: BoxDecoration(
                color: fill,
                borderRadius: BorderRadius.circular(8),
                border: Border(left: BorderSide(color: edge, width: 3)),
                boxShadow: running
                    ? [BoxShadow(color: edge.withValues(alpha: 0.25), blurRadius: 6)]
                    : null,
              ),
              padding: const EdgeInsets.fromLTRB(8, 5, 8, 5),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    e.description.isNotEmpty ? e.description : '(no description)',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontWeight: FontWeight.w600, fontSize: 12.5),
                  ),
                  if (height > 36)
                    Text(
                      [
                        entrySubline(e),
                        if (e.duration.isNotEmpty) e.duration,
                      ].where((s) => s.isNotEmpty).join(' · '),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: cs.onSurfaceVariant, fontSize: 11),
                    ),
                ],
              ),
            ),
            // bottom-edge resize handle
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              height: 10,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onVerticalDragStart: (_) => setState(() {
                  _dragGuid = e.guid;
                  _resizing = true;
                  _dragTopPx = baseTop;
                  _dragHeightPx = baseHeight.toDouble();
                }),
                onVerticalDragUpdate: (d) {
                  if (_dragGuid != e.guid) return;
                  setState(() => _dragHeightPx =
                      (_dragHeightPx + d.delta.dy).clamp(22.0, 24 * _hourHeight));
                },
                onVerticalDragEnd: (_) => _commitDrag(e, start, end),
                child: MouseRegion(
                  cursor: SystemMouseCursors.resizeUpDown,
                  child: const SizedBox.expand(),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _commitDrag(TimeEntry e, DateTime origStart, DateTime origEnd) {
    final guid = _dragGuid;
    final resizing = _resizing;
    final topPx = _dragTopPx;
    final heightPx = _dragHeightPx;
    setState(() {
      _dragGuid = null;
      _resizing = false;
    });
    if (guid == null) return;

    final durMin = origEnd.difference(origStart).inMinutes;
    if (resizing) {
      final newDur = _snapMinutes(heightPx / _hourHeight * 60).clamp(15, 24 * 60);
      final newEnd = origStart.add(Duration(minutes: newDur));
      ref.read(coreServiceProvider).setEntryTimes(guid, end: newEnd);
    } else {
      final newStartMin = _snapMinutes(topPx / _hourHeight * 60);
      final newStart =
          DateTime(_day.year, _day.month, _day.day).add(Duration(minutes: newStartMin));
      final newEnd = newStart.add(Duration(minutes: durMin));
      ref.read(coreServiceProvider).setEntryTimes(guid, start: newStart, end: newEnd);
    }
  }

  static int _snapMinutes(double minutes) => (minutes / 15).round() * 15;
}

class _HeaderBar extends StatelessWidget {
  const _HeaderBar({
    required this.day,
    required this.total,
    required this.onPrev,
    required this.onNext,
    required this.onToday,
    required this.onNew,
  });

  final DateTime day;
  final String total;
  final VoidCallback onPrev;
  final VoidCallback onNext;
  final VoidCallback onToday;
  final VoidCallback onNew;

  static const _weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
  static const _months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
  ];

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final t = Theme.of(context).extension<RedtickTokens>()!;
    final label = '${_weekdays[day.weekday - 1]}, ${_months[day.month - 1]} ${day.day}';
    final isToday = day == DateTime(DateTime.now().year, DateTime.now().month, DateTime.now().day);
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: t.hairline)),
      ),
      child: Row(
        children: [
          IconButton(
              icon: const Icon(Icons.chevron_left, size: 20), onPressed: onPrev),
          Text(label,
              style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
          IconButton(
              icon: const Icon(Icons.chevron_right, size: 20), onPressed: onNext),
          const SizedBox(width: 8),
          if (!isToday)
            OutlinedButton(
              onPressed: onToday,
              style: OutlinedButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                  side: BorderSide(color: t.hairline)),
              child: const Text('Today'),
            ),
          const Spacer(),
          Text(total,
              style: RedtickTheme.mono(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: cs.onSurfaceVariant)),
          const SizedBox(width: 14),
          FilledButton.icon(
            onPressed: onNew,
            icon: const Icon(Icons.add, size: 16),
            label: const Text('New'),
          ),
        ],
      ),
    );
  }
}
