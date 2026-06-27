import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/time_entry.dart';
import '../../platform/idle.dart';
import '../../platform/idle_log.dart';
import '../../state/idle_settings.dart';
import '../../state/providers.dart';
import '../theme.dart';
import 'entry_bits.dart';
import 'issue_picker.dart';

enum IdleChoice { keep, discardStop, discardContinue, addAsNew }

/// Test-only fast trigger. When `> 0`, overrides the configured idle threshold
/// (minutes × 60) so the prompt can be reproduced in seconds during a
/// `flutter run`/release diagnosis (`--dart-define=REDTICK_IDLE_THRESHOLD_SEC=15`).
/// Default `0` = no override, so the shipped 5-minute default is unchanged.
const int _idleThresholdOverrideSec =
    int.fromEnvironment('REDTICK_IDLE_THRESHOLD_SEC', defaultValue: 0);

/// Wraps the app shell and, while a timer runs, polls desktop idle time. When
/// the user has been idle past the threshold it shows the idle prompt once
/// (re-arming when they become active again). Design §3.9.
class IdleWatcher extends ConsumerStatefulWidget {
  const IdleWatcher({super.key, required this.child});
  final Widget child;

  @override
  ConsumerState<IdleWatcher> createState() => _IdleWatcherState();
}

class _IdleWatcherState extends ConsumerState<IdleWatcher> {
  Timer? _timer;
  bool _armed = true;
  bool _showing = false;

  @override
  void initState() {
    super.initState();
    if (IdleDetector.supported) {
      _timer = Timer.periodic(const Duration(seconds: 20), (_) => _check());
      idleLog('watcher.init supported=true pollEvery=20s '
          'thresholdOverrideSec=$_idleThresholdOverrideSec');
    } else {
      idleLog('watcher.init NOT supported -> timer not started');
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _check() async {
    if (_showing || !mounted) {
      idleLog('check skip: showing=$_showing mounted=$mounted');
      return;
    }
    final settings = ref.read(idleSettingsProvider);
    if (!settings.enabled) {
      _armed = true; // detection off → nothing to do (re-arm for when re-enabled)
      idleLog('check stop: detection disabled (re-armed)');
      return;
    }
    final thresholdSec = _idleThresholdOverrideSec > 0
        ? _idleThresholdOverrideSec
        : settings.minutes * 60;
    // Read the synchronous snapshot, NOT timerStateProvider: that StreamProvider
    // is never watched, so a cold ref.read returns AsyncLoading (null) even while
    // a timer runs — the original reason the prompt never fired.
    final running = ref.read(coreServiceProvider).currentTimer;
    if (running == null || !running.isRunning) {
      _armed = true;
      idleLog('check stop: timer not running '
          '(running=${running == null ? "null" : running.isRunning})');
      return;
    }
    final idle = await IdleDetector.seconds();
    idleLog('check idle=${idle}s threshold=${thresholdSec}s armed=$_armed');
    if (idle < thresholdSec / 2) {
      _armed = true; // user is active again → re-arm
      idleLog('check re-arm: idle ${idle}s < half ${thresholdSec / 2}s');
      return;
    }
    if (idle < thresholdSec || !_armed || !mounted) {
      idleLog('check stop: belowThreshold=${idle < thresholdSec} '
          'armed=$_armed mounted=$mounted');
      return;
    }

    _armed = false;
    _showing = true;
    final idleStart = DateTime.now().subtract(Duration(seconds: idle.round()));
    idleLog('check FIRE: showing prompt, idle=${idle.round()}s '
        'idleStart=$idleStart');
    // try/finally guarantees _showing resets even if the dialog, issue picker,
    // or a core call throws — otherwise _showing stuck true permanently killed
    // detection.
    try {
      final choice = await _showIdlePrompt(
          context, running, idleStart, idle.round() ~/ 60);
      idleLog('check prompt closed: choice=$choice');
      if (mounted && choice != null) {
        final core = ref.read(coreServiceProvider);
        switch (choice) {
          case IdleChoice.keep:
            break;
          case IdleChoice.discardStop:
            core.stopRunningAt(idleStart);
          case IdleChoice.discardContinue:
            core.discardIdleAndContinue(idleStart);
          case IdleChoice.addAsNew:
            final issue = await showIssuePicker(context);
            if (issue != null) {
              core.logIdleAsNewEntry(
                idleStart,
                issueId: issue.id,
                projectId: issue.projectId,
                subject: issue.subject,
                projectName: issue.projectName,
              );
            }
        }
      }
    } catch (e, st) {
      idleLog('check prompt error: $e\n$st');
    } finally {
      _showing = false;
    }
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

Future<IdleChoice?> _showIdlePrompt(
  BuildContext context,
  TimeEntry running,
  DateTime idleStart,
  int idleMinutes,
) {
  final cs = Theme.of(context).colorScheme;
  final t = Theme.of(context).extension<RedtickTokens>()!;
  String hhmm(DateTime d) =>
      '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';

  return showDialog<IdleChoice>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => Dialog(
      backgroundColor: cs.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text("You've been idle",
                  style: Theme.of(ctx)
                      .textTheme
                      .titleMedium
                      ?.copyWith(fontWeight: FontWeight.w800)),
              const SizedBox(height: 4),
              Text('Idle since ${hhmm(idleStart)} · $idleMinutes minutes',
                  style: TextStyle(color: cs.onSurfaceVariant, fontSize: 13)),
              const SizedBox(height: 14),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: t.accentSoft,
                  borderRadius: BorderRadius.circular(10),
                  border: Border(left: BorderSide(color: cs.primary, width: 3)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      running.description.isNotEmpty
                          ? running.description
                          : 'Running',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 4),
                    IssueChip(entry: running),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              _Action(
                icon: Icons.check_circle_outline,
                title: 'Keep idle time',
                subtitle: 'The idle minutes count toward this entry.',
                primary: true,
                onTap: () => Navigator.of(ctx).pop(IdleChoice.keep),
              ),
              _Action(
                icon: Icons.content_cut,
                title: 'Discard idle & stop',
                subtitle: 'Trim back to ${hhmm(idleStart)} and stop.',
                onTap: () => Navigator.of(ctx).pop(IdleChoice.discardStop),
              ),
              _Action(
                icon: Icons.play_circle_outline,
                title: 'Discard idle & continue',
                subtitle: 'Trim to ${hhmm(idleStart)}, then start fresh now.',
                onTap: () => Navigator.of(ctx).pop(IdleChoice.discardContinue),
              ),
              _Action(
                icon: Icons.note_add_outlined,
                title: 'Add idle as a new entry',
                subtitle: 'Log the idle on another Redmine issue you pick.',
                onTap: () => Navigator.of(ctx).pop(IdleChoice.addAsNew),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

class _Action extends StatelessWidget {
  const _Action({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.primary = false,
  });
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  final bool primary;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final t = Theme.of(context).extension<RedtickTokens>()!;
    final color = primary ? cs.primary : cs.onSurface;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: primary ? t.accentSoft : Colors.transparent,
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
            child: Row(
              children: [
                Icon(icon, size: 20, color: color),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title,
                          style: TextStyle(
                              fontWeight: FontWeight.w600,
                              fontSize: 14,
                              color: color)),
                      Text(subtitle,
                          style: TextStyle(
                              color: cs.onSurfaceVariant, fontSize: 12)),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
