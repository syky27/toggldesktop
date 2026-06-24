import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../state/providers.dart';

/// Running-timer bar (FP-42). Shows the running entry's issue/description and a
/// live-ish duration, with a start/stop button. Mirrors the Qt `timerwidget`
/// (issue shown on top, description underneath).
class TimerBar extends ConsumerWidget {
  const TimerBar({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final running = ref.watch(timerStateProvider).asData?.value;
    final core = ref.read(coreServiceProvider);
    final isRunning = running != null && running.isRunning;

    return Material(
      color: Theme.of(context).colorScheme.surfaceContainerHigh,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    isRunning
                        ? (running.projectLabel.isNotEmpty
                            ? running.projectLabel
                            : 'Running')
                        : 'Not running',
                    style: Theme.of(context).textTheme.titleMedium,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (isRunning && running.description.isNotEmpty)
                    Text(
                      running.description,
                      style: Theme.of(context).textTheme.bodySmall,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            if (isRunning)
              Text(running.duration,
                  style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(width: 12),
            IconButton.filled(
              icon: Icon(isRunning ? Icons.stop : Icons.play_arrow),
              onPressed: () => isRunning ? core.stop() : core.continueEntry(''),
            ),
          ],
        ),
      ),
    );
  }
}
