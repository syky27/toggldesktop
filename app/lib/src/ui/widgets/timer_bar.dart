import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/redmine_service.dart';
import '../../models/time_entry.dart';
import '../../state/providers.dart';
import '../theme.dart';
import 'entry_bits.dart';
import 'issue_picker.dart';

/// Running-timer hero bar (design §3.3): live red mono duration, issue chip +
/// activity, and a Stop button; an idle "Start" affordance otherwise.
class TimerBar extends ConsumerWidget {
  const TimerBar({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final running = ref.watch(timerStateProvider).asData?.value;
    final core = ref.read(coreServiceProvider);
    final cs = Theme.of(context).colorScheme;
    final t = Theme.of(context).extension<RedtickTokens>()!;
    final isRunning = running != null && running.isRunning;

    return Container(
      decoration: BoxDecoration(
        color: cs.surface,
        border: Border(bottom: BorderSide(color: t.hairline)),
      ),
      padding: const EdgeInsets.fromLTRB(22, 16, 22, 16),
      child: isRunning
          ? _Running(core: core, entry: running)
          : _Idle(core: core),
    );
  }
}

class _Running extends StatelessWidget {
  const _Running({required this.core, required this.entry});
  final RedmineService core;
  final TimeEntry entry;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final activity = core.activityName(entry.activityId);
    return Row(
      children: [
        Container(
          width: 9,
          height: 9,
          margin: const EdgeInsets.only(right: 14),
          decoration: BoxDecoration(color: cs.primary, shape: BoxShape.circle),
        ),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                entry.description.isNotEmpty ? entry.description : 'Running',
                style: Theme.of(context)
                    .textTheme
                    .titleMedium
                    ?.copyWith(fontWeight: FontWeight.w700),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 6),
              Row(
                children: [
                  Flexible(child: IssueChip(entry: entry)),
                  if (activity.isNotEmpty)
                    Flexible(
                      child: Padding(
                        padding: const EdgeInsets.only(left: 10),
                        child: Text('Activity: $activity',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                                color: cs.onSurfaceVariant, fontSize: 12)),
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(width: 16),
        Text(entry.duration,
            style: RedtickTheme.mono(
                fontSize: 26, fontWeight: FontWeight.w700, color: cs.primary)),
        const SizedBox(width: 16),
        FilledButton.icon(
          onPressed: core.stop,
          icon: const Icon(Icons.stop, size: 18),
          label: const Text('Stop'),
        ),
      ],
    );
  }
}

class _Idle extends StatelessWidget {
  const _Idle({required this.core});
  final RedmineService core;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final t = Theme.of(context).extension<RedtickTokens>()!;
    return Row(
      children: [
        Container(
          width: 9,
          height: 9,
          margin: const EdgeInsets.only(right: 14),
          decoration: BoxDecoration(color: t.faint, shape: BoxShape.circle),
        ),
        Expanded(
          child: Text('Not running',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  color: cs.onSurfaceVariant, fontWeight: FontWeight.w600)),
        ),
        FilledButton.icon(
          onPressed: () async {
            final issue = await showIssuePicker(context);
            if (issue == null) return;
            core.startEntryForIssue(
              issueId: issue.id,
              projectId: issue.projectId,
              subject: issue.subject,
              projectName: issue.projectName,
              description: issue.subject,
            );
          },
          icon: const Icon(Icons.play_arrow, size: 18),
          label: const Text('Start'),
        ),
      ],
    );
  }
}
