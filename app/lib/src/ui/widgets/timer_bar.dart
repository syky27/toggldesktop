import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/redmine_service.dart';
import '../../models/time_entry.dart';
import '../../state/multi_task_settings.dart';
import '../../state/providers.dart';
import '../theme.dart';
import 'entry_bits.dart';
import 'issue_picker.dart';
import 'running_start_editor.dart';

/// Running-timer hero bar (design §3.3): live red mono duration, issue chip +
/// activity, and a Stop button; an idle "Start" affordance otherwise. With
/// concurrent tracking enabled (multi_task_settings) several running timers
/// stack here, each with its own Stop, plus a "Start another task" affordance.
class TimerBar extends ConsumerWidget {
  const TimerBar({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final running =
        ref.watch(runningEntriesProvider).asData?.value ?? const <TimeEntry>[];
    final allowConcurrent =
        ref.watch(multiTaskSettingsProvider).allowConcurrent;
    final core = ref.read(coreServiceProvider);
    final cs = Theme.of(context).colorScheme;
    final t = Theme.of(context).extension<RedtickTokens>()!;

    final active = running.where((e) => e.isRunning).toList();

    final Widget child = active.isEmpty
        ? _Idle(core: core, allowConcurrent: allowConcurrent)
        : Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (var i = 0; i < active.length; i++) ...[
                if (i > 0) Divider(height: 22, thickness: 1, color: t.hairline),
                _Running(core: core, entry: active[i]),
              ],
              if (allowConcurrent) ...[
                const SizedBox(height: 10),
                _StartAnother(core: core),
              ],
            ],
          );

    return Container(
      decoration: BoxDecoration(
        color: cs.surface,
        border: Border(bottom: BorderSide(color: t.hairline)),
      ),
      padding: const EdgeInsets.fromLTRB(22, 16, 22, 16),
      child: child,
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
        MouseRegion(
          cursor: SystemMouseCursors.click,
          child: GestureDetector(
            onTap: () => showRunningStartEditor(context, core, entry),
            child: Tooltip(
              message: 'Adjust start time',
              child: Text(entry.duration,
                  style: RedtickTheme.mono(
                      fontSize: 26,
                      fontWeight: FontWeight.w700,
                      color: cs.primary)),
            ),
          ),
        ),
        const SizedBox(width: 16),
        FilledButton.icon(
          onPressed: () => core.stopEntry(entry.guid),
          icon: const Icon(Icons.stop, size: 18),
          label: const Text('Stop'),
        ),
      ],
    );
  }
}

class _Idle extends StatelessWidget {
  const _Idle({required this.core, required this.allowConcurrent});
  final RedmineService core;
  final bool allowConcurrent;

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
              stopOthers: !allowConcurrent,
            );
          },
          icon: const Icon(Icons.play_arrow, size: 18),
          label: const Text('Start'),
        ),
      ],
    );
  }
}

/// "Start another task" — starts an additional concurrent timer without
/// stopping the running ones (shown only when concurrent tracking is enabled).
class _StartAnother extends StatelessWidget {
  const _StartAnother({required this.core});
  final RedmineService core;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: TextButton.icon(
        onPressed: () async {
          final issue = await showIssuePicker(context);
          if (issue == null) return;
          core.startEntryForIssue(
            issueId: issue.id,
            projectId: issue.projectId,
            subject: issue.subject,
            projectName: issue.projectName,
            description: issue.subject,
            stopOthers: false,
          );
        },
        icon: const Icon(Icons.add, size: 18),
        label: const Text('Start another task'),
      ),
    );
  }
}
