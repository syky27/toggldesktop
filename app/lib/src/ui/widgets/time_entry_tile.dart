import 'package:flutter/material.dart';

import '../../models/time_entry.dart';
import '../theme.dart';
import 'entry_bits.dart';

/// A completed time-entry row (design §3.4 `.erow`): project dot, description,
/// `#issue · project` sub-line, the time range + mono duration, and a continue
/// (play) action.
class TimeEntryTile extends StatelessWidget {
  const TimeEntryTile({
    super.key,
    required this.entry,
    required this.onContinue,
    this.onTap,
  });

  final TimeEntry entry;
  final VoidCallback onContinue;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final t = Theme.of(context).extension<RedtickTokens>()!;
    final hasSub = entrySubline(entry).isNotEmpty;
    final range = (entry.startTimeString.isNotEmpty &&
            entry.endTimeString.isNotEmpty)
        ? '${entry.startTimeString} – ${entry.endTimeString}'
        : '';
    // On a narrow (mobile) layout the range + total compete for width, so stack
    // the range above the total instead of placing them side by side. Matches
    // the shell's 720 px breakpoint.
    final narrow = MediaQuery.sizeOf(context).width < 720;
    final duration = Text(entry.duration,
        style: RedtickTheme.mono(
            fontSize: 14, fontWeight: FontWeight.w600, color: cs.onSurface));

    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 12),
        child: Row(
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 3),
              child: ProjectDot(entry.color),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    entry.description.isNotEmpty
                        ? entry.description
                        : '(no description)',
                    style: const TextStyle(
                        fontWeight: FontWeight.w600, fontSize: 14),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (hasSub) ...[
                    const SizedBox(height: 2),
                    EntrySubline(entry: entry),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 12),
            if (entry.unsynced)
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: Icon(Icons.cloud_upload_outlined,
                    size: 15, color: t.faint),
              ),
            if (narrow)
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (range.isNotEmpty) ...[
                    Text(range,
                        style: RedtickTheme.mono(fontSize: 11, color: t.faint)),
                    const SizedBox(height: 3),
                  ],
                  duration,
                ],
              )
            else ...[
              if (range.isNotEmpty) ...[
                Text(range,
                    style: RedtickTheme.mono(fontSize: 12, color: t.faint)),
                const SizedBox(width: 14),
              ],
              duration,
            ],
            const SizedBox(width: 8),
            _PlayButton(onTap: onContinue),
          ],
        ),
      ),
    );
  }
}

class _PlayButton extends StatelessWidget {
  const _PlayButton({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final t = Theme.of(context).extension<RedtickTokens>()!;
    return Material(
      color: Colors.transparent,
      shape: CircleBorder(side: BorderSide(color: t.hairline)),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(7),
          child: Icon(Icons.play_arrow, size: 15, color: cs.primary),
        ),
      ),
    );
  }
}
