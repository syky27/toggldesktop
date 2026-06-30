import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../platform/log_file.dart';
import '../../state/idle_settings.dart';
import '../../state/logging_settings.dart';
import '../../state/multi_task_settings.dart';
import '../../state/providers.dart';
import '../../state/release_watch.dart';
import '../../state/reminder_settings.dart';
import '../../state/theme_mode.dart';
import '../theme.dart';
import '../widgets/release_update_banner.dart';

/// Preferences (design §3.8 / §4): Appearance picker, Redmine account, Tracking.
class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final core = ref.watch(coreServiceProvider);
    final mode = ref.watch(themeModeProvider);
    final idle = ref.watch(idleSettingsProvider);
    final rem = ref.watch(reminderSettingsProvider);
    final multi = ref.watch(multiTaskSettingsProvider);
    final logging = ref.watch(loggingSettingsProvider);
    final cs = Theme.of(context).colorScheme;
    final isDesktop =
        Platform.isMacOS || Platform.isWindows || Platform.isLinux;

    return ColoredBox(
      color: cs.surface,
      child: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(22, 20, 22, 32),
          children: [
            Text('Preferences',
                style: Theme.of(context)
                    .textTheme
                    .headlineSmall
                    ?.copyWith(fontWeight: FontWeight.w800)),
            const SizedBox(height: 20),

            // --- Appearance ---
            const _SectionHeader('Appearance'),
            Row(
              children: [
                _AppearanceCard(
                  label: 'Light',
                  mode: ThemeMode.light,
                  selected: mode == ThemeMode.light,
                  onTap: () =>
                      ref.read(themeModeProvider.notifier).set(ThemeMode.light),
                ),
                const SizedBox(width: 14),
                _AppearanceCard(
                  label: 'Dark',
                  mode: ThemeMode.dark,
                  selected: mode == ThemeMode.dark,
                  onTap: () =>
                      ref.read(themeModeProvider.notifier).set(ThemeMode.dark),
                ),
                const SizedBox(width: 14),
                _AppearanceCard(
                  label: 'Auto',
                  mode: ThemeMode.system,
                  selected: mode == ThemeMode.system,
                  onTap: () => ref
                      .read(themeModeProvider.notifier)
                      .set(ThemeMode.system),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              switch (mode) {
                ThemeMode.light => 'Always light — Slate.',
                ThemeMode.dark => 'Always dark — Carbon.',
                ThemeMode.system => 'Following system.',
              },
              style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12),
            ),
            const SizedBox(height: 24),

            // --- Redmine account ---
            const _SectionHeader('Redmine account'),
            _Row(
              title: 'Instance URL',
              subtitle: core.host.isEmpty ? '—' : core.host,
              trailing: OutlinedButton.icon(
                onPressed: core.reconnect,
                icon: const Icon(Icons.refresh, size: 16),
                label: const Text('Reconnect'),
              ),
            ),
            _Row(
              title: 'API access key',
              subtitle: core.maskedKey,
              trailing: OutlinedButton.icon(
                onPressed: core.logout,
                icon: const Icon(Icons.logout, size: 16),
                label: const Text('Log out'),
              ),
            ),
            const SizedBox(height: 24),

            // --- Tracking ---
            const _SectionHeader('Tracking'),
            _Row(
              title: 'Default activity',
              subtitle: 'Used for new entries',
              trailing: _ActivityDropdown(),
            ),
            _Row(
              title: 'Track multiple tasks at once',
              subtitle: 'Run several timers concurrently; they stack on top',
              trailing: Switch(
                value: multi.allowConcurrent,
                onChanged: (v) => ref
                    .read(multiTaskSettingsProvider.notifier)
                    .setAllowConcurrent(v),
              ),
            ),

            // --- Idle detection (desktop only; idle input isn't tracked on
            // mobile, so the controls are hidden there) ---
            if (isDesktop) ...[
              const SizedBox(height: 24),
              const _SectionHeader('Idle detection'),
              _Row(
                title: 'Enable idle detection',
                subtitle: 'Prompt to keep or discard idle time while tracking',
                trailing: Switch(
                  value: idle.enabled,
                  onChanged: (v) =>
                      ref.read(idleSettingsProvider.notifier).setEnabled(v),
                ),
              ),
              _Row(
                title: 'Idle threshold',
                subtitle: 'Minutes of inactivity before prompting',
                trailing: _MinutesStepper(
                  value: idle.minutes,
                  enabled: idle.enabled,
                  onChanged: (v) =>
                      ref.read(idleSettingsProvider.notifier).setMinutes(v),
                ),
              ),
            ],

            // --- Reminders (desktop only: a phone keeps the app alive in the
            // background, so a "you're not tracking" nudge there is just noise;
            // desktop apps can be fully quit, where the nudge is useful) ---
            if (isDesktop) ...[
              const SizedBox(height: 24),
              const _SectionHeader('Reminders'),
              _Row(
                title: 'Remind me to track time',
                subtitle: 'Notify when no timer is running',
                trailing: Switch(
                  value: rem.enabled,
                  onChanged: (v) =>
                      ref.read(reminderSettingsProvider.notifier).setEnabled(v),
                ),
              ),
              _Row(
                title: 'Remind every',
                subtitle: 'Minutes between reminders',
                trailing: _MinutesStepper(
                  value: rem.minutes,
                  enabled: rem.enabled,
                  onChanged: (v) =>
                      ref.read(reminderSettingsProvider.notifier).setMinutes(v),
                ),
              ),
              _WeekdayChips(enabled: rem.enabled),
              _TimeWindowRow(enabled: rem.enabled),
            ],

            // --- Redmine custom fields (all platforms): the timer-metadata
            // field ids + the master "send custom fields" toggle. ---
            const _CustomFieldsSection(),

            // --- Diagnostics (desktop only: opening/revealing the log file
            // needs a file manager, which mobile doesn't expose) ---
            if (isDesktop) ...[
              const SizedBox(height: 24),
              const _SectionHeader('Diagnostics'),
              _Row(
                title: 'Log HTTP to a file',
                subtitle: 'Records every Redmine request and response (your '
                    'Redmine data) to a local file. The API key is never '
                    'written. Use it to diagnose failing requests.',
                trailing: Switch(
                  value: logging.enabled,
                  onChanged: (v) => ref
                      .read(loggingSettingsProvider.notifier)
                      .setEnabled(v),
                ),
              ),
              if (logging.enabled) const _LogFileRow(),
            ],

            // --- About / updates ---
            const SizedBox(height: 24),
            const _SectionHeader('About'),
            const _AboutVersionRow(),
            // GitHub releases are desktop installers, so the manual check is
            // desktop-only (mobile gets the version line but no check button).
            if (isDesktop) const _CheckForUpdatesRow(),
          ],
        ),
      ),
    );
  }
}

/// Shows the running version (the release tag — `dev` in local builds) and a
/// link to the GitHub releases page.
class _AboutVersionRow extends ConsumerWidget {
  const _AboutVersionRow();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final watch = ref.watch(releaseWatchProvider);
    final tag = watch.currentTag;
    return _Row(
      title: 'Version',
      subtitle: tag == 'dev' ? 'dev (local build)' : tag,
      trailing: TextButton.icon(
        onPressed: () => ref.read(releaseLinkLauncherProvider)(
          Uri.parse('https://github.com/${watch.repository}/releases'),
        ),
        icon: const Icon(Icons.open_in_new, size: 16),
        label: const Text('View releases'),
      ),
    );
  }
}

/// Desktop-only manual "check for updates" against GitHub. The persistent top
/// banner still handles the available-update case; this gives explicit feedback
/// (incl. "you're up to date") without waiting for the 24h auto-check.
class _CheckForUpdatesRow extends ConsumerWidget {
  const _CheckForUpdatesRow();

  Future<void> _check(BuildContext context, WidgetRef ref) async {
    final outcome =
        await ref.read(releaseWatchProvider.notifier).checkForUpdates();
    if (!context.mounted) return;
    final message = switch (outcome.status) {
      UpdateCheckStatus.updateAvailable =>
        'Update available: ${outcome.release?.tagName ?? ''}',
      UpdateCheckStatus.upToDate => "You're on the latest version",
      UpdateCheckStatus.failed => "Couldn't check for updates — try again",
      UpdateCheckStatus.unsupported =>
        'Latest release: ${outcome.release?.tagName ?? '—'}',
    };
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final watch = ref.watch(releaseWatchProvider);
    final checking = watch.checking;
    final lastChecked = watch.lastCheckedAt;
    return _Row(
      title: 'Check for updates',
      subtitle: lastChecked == null
          ? 'Checks GitHub for a newer release'
          : 'Last checked ${_relativeTime(lastChecked)}',
      trailing: OutlinedButton.icon(
        onPressed: checking ? null : () => _check(context, ref),
        icon: checking
            ? const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : const Icon(Icons.system_update_alt, size: 16),
        label: Text(checking ? 'Checking…' : 'Check for updates'),
      ),
    );
  }
}

/// The toggl_* custom-field config: the master "send custom fields" toggle plus
/// the three editable numeric field ids (prefilled with what we resolved). The
/// ids commit on submit / focus-loss; the toggle flips simple mode live.
class _CustomFieldsSection extends ConsumerStatefulWidget {
  const _CustomFieldsSection();

  @override
  ConsumerState<_CustomFieldsSection> createState() =>
      _CustomFieldsSectionState();
}

class _CustomFieldsSectionState extends ConsumerState<_CustomFieldsSection> {
  final _start = TextEditingController();
  final _stop = TextEditingController();
  final _guid = TextEditingController();
  final _startFocus = FocusNode();
  final _stopFocus = FocusNode();
  final _guidFocus = FocusNode();

  @override
  void initState() {
    super.initState();
    final core = ref.read(coreServiceProvider);
    _start.text = '${core.cfStartId}';
    _stop.text = '${core.cfStopId}';
    _guid.text = '${core.cfGuidId}';
    _startFocus.addListener(_commitOnBlur);
    _stopFocus.addListener(_commitOnBlur);
    _guidFocus.addListener(_commitOnBlur);
  }

  @override
  void dispose() {
    _start.dispose();
    _stop.dispose();
    _guid.dispose();
    _startFocus.dispose();
    _stopFocus.dispose();
    _guidFocus.dispose();
    super.dispose();
  }

  void _commitOnBlur() {
    if (_startFocus.hasFocus || _stopFocus.hasFocus || _guidFocus.hasFocus) {
      return;
    }
    _commit();
  }

  void _commit() {
    ref.read(coreServiceProvider).setCustomFieldIds(
          start: int.tryParse(_start.text.trim()),
          stop: int.tryParse(_stop.text.trim()),
          guid: int.tryParse(_guid.text.trim()),
        );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final core = ref.watch(coreServiceProvider);
    final cfg = ref.watch(customFieldConfigProvider).asData?.value ??
        core.currentCustomFieldConfig;
    // Reflect login-time id resolution in any field the user isn't editing.
    ref.listen(customFieldConfigProvider, (_, next) {
      final c = next.asData?.value;
      if (c == null) return;
      if (!_startFocus.hasFocus) _start.text = '${c.startId}';
      if (!_stopFocus.hasFocus) _stop.text = '${c.stopId}';
      if (!_guidFocus.hasFocus) _guid.text = '${c.guidId}';
    });
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 24),
        const _SectionHeader('Redmine custom fields'),
        _Row(
          title: 'Send custom fields with entries',
          subtitle: cfg.sendCustomFields
              ? 'Stores precise start/stop times and a Redtick ID on each entry.'
              : 'Off — logging plain hours; timestamps and Calendar are hidden.',
          trailing: Switch(
            value: cfg.sendCustomFields,
            onChanged: (v) async {
              final core = ref.read(coreServiceProvider);
              await core.setSendCustomFields(v);
              if (!v) return;
              // Turning it on → probe the instance immediately. If the fields
              // don't work it flips back off + alerts; if they do, confirm so
              // the toggle's behaviour is never silently ambiguous.
              final ok = await core.verifyCustomFieldsNow();
              if (ok && context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                    content: Text('Custom fields are working on this instance.')));
              }
            },
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(0, 12, 0, 4),
          child: Text(
            'Numeric Redmine custom-field ids. We prefill what we detect; if '
            'your admin gives you the ids, enter them here.',
            style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12.5),
          ),
        ),
        _idField('Redtick ID', _guid, _guidFocus),
        _idField('Start Timestamp', _start, _startFocus),
        _idField('Stop Timestamp', _stop, _stopFocus),
      ],
    );
  }

  Widget _idField(String label, TextEditingController c, FocusNode f) {
    final t = Theme.of(context).extension<RedtickTokens>()!;
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 10),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: t.hairline)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(label,
                style:
                    const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
          ),
          SizedBox(
            width: 88,
            child: TextField(
              controller: c,
              focusNode: f,
              textAlign: TextAlign.center,
              keyboardType: TextInputType.number,
              onSubmitted: (_) => _commit(),
              decoration: const InputDecoration(isDense: true),
            ),
          ),
        ],
      ),
    );
  }
}

/// Shows the HTTP log path (selectable, so it's copyable even if the reveal
/// fails) with buttons to reveal it in the file manager and to clear it.
class _LogFileRow extends ConsumerStatefulWidget {
  const _LogFileRow();

  @override
  ConsumerState<_LogFileRow> createState() => _LogFileRowState();
}

class _LogFileRowState extends ConsumerState<_LogFileRow> {
  String _path = '';

  @override
  void initState() {
    super.initState();
    ref.read(httpLoggerProvider).file().then((f) {
      if (mounted) setState(() => _path = f.path);
    });
  }

  Future<void> _reveal() async {
    final path = _path;
    if (path.isEmpty) return;
    final ok = await ref.read(logFileRevealerProvider)(path);
    if (!mounted) return;
    if (!ok) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Couldn't open the log — it's at:\n$path")),
      );
    }
  }

  Future<void> _clear() async {
    await ref.read(httpLoggerProvider).clear();
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(const SnackBar(content: Text('Log cleared')));
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final t = Theme.of(context).extension<RedtickTokens>()!;
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 14),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: t.hairline)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Log file',
              style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
          const SizedBox(height: 4),
          SelectableText(
            _path.isEmpty ? 'Resolving…' : _path,
            style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12.5),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              OutlinedButton.icon(
                onPressed: _path.isEmpty ? null : _reveal,
                icon: const Icon(Icons.folder_open, size: 16),
                label: const Text('Show log'),
              ),
              const SizedBox(width: 12),
              TextButton.icon(
                onPressed: _path.isEmpty ? null : _clear,
                icon: const Icon(Icons.delete_outline, size: 16),
                label: const Text('Clear log'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Short relative time for the "last checked" subline.
String _relativeTime(DateTime time) {
  final d = DateTime.now().toUtc().difference(time.toUtc());
  if (d.inMinutes < 1) return 'just now';
  if (d.inMinutes < 60) return '${d.inMinutes}m ago';
  if (d.inHours < 24) return '${d.inHours}h ago';
  return '${d.inDays}d ago';
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Text(text.toUpperCase(),
          style: TextStyle(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.6)),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({required this.title, required this.subtitle, this.trailing});
  final String title;
  final String subtitle;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final t = Theme.of(context).extension<RedtickTokens>()!;
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 14),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: t.hairline)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: const TextStyle(
                        fontWeight: FontWeight.w600, fontSize: 14)),
                const SizedBox(height: 2),
                Text(subtitle,
                    style:
                        TextStyle(color: cs.onSurfaceVariant, fontSize: 12.5)),
              ],
            ),
          ),
          ?trailing,
        ],
      ),
    );
  }
}

class _ActivityDropdown extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final core = ref.watch(coreServiceProvider);
    final activities = core.availableActivities;
    if (activities.isEmpty) return const SizedBox.shrink();
    final ids = activities.map((a) => a.id).toSet();
    final value =
        ids.contains(core.defaultActivityId) ? core.defaultActivityId : null;
    return SizedBox(
      width: 180,
      child: DropdownButtonFormField<int>(
        initialValue: value,
        isExpanded: true,
        items: [
          for (final a in activities)
            DropdownMenuItem(value: a.id, child: Text(a.name)),
        ],
        onChanged: (v) async {
          if (v != null) {
            await core.setDefaultActivity(v);
            ref.invalidate(coreServiceProvider);
          }
        },
      ),
    );
  }
}

/// A compact "− N min +" stepper for minute-valued settings (clamped 1..999).
class _MinutesStepper extends StatelessWidget {
  const _MinutesStepper({
    required this.value,
    required this.onChanged,
    this.enabled = true,
  });
  final int value;
  final ValueChanged<int> onChanged;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _StepButton(
          icon: Icons.remove,
          enabled: enabled && value > 1,
          onTap: () => onChanged(value - 1),
        ),
        SizedBox(
          width: 60,
          child: Text(
            '$value min',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontWeight: FontWeight.w600,
              fontSize: 14,
              color: enabled
                  ? null
                  : Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ),
        _StepButton(
          icon: Icons.add,
          enabled: enabled && value < 999,
          onTap: () => onChanged(value + 1),
        ),
      ],
    );
  }
}

class _StepButton extends StatelessWidget {
  const _StepButton(
      {required this.icon, required this.onTap, required this.enabled});
  final IconData icon;
  final VoidCallback onTap;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final t = Theme.of(context).extension<RedtickTokens>()!;
    return InkWell(
      onTap: enabled ? onTap : null,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        width: 32,
        height: 32,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: t.hairline),
        ),
        child: Icon(icon,
            size: 18,
            color: enabled ? cs.onSurface : cs.onSurfaceVariant.withValues(alpha: 0.4)),
      ),
    );
  }
}

/// Weekday toggles (Mon–Sun) for the reminder's active days. Greyed out when
/// the reminder is off.
class _WeekdayChips extends ConsumerWidget {
  const _WeekdayChips({required this.enabled});
  final bool enabled;

  static const _labels = ['Mo', 'Tu', 'We', 'Th', 'Fr', 'Sa', 'Su'];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cs = Theme.of(context).colorScheme;
    final t = Theme.of(context).extension<RedtickTokens>()!;
    final rem = ref.watch(reminderSettingsProvider);
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 14),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: t.hairline)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Active days',
              style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
          const SizedBox(height: 2),
          Text('Only remind on selected weekdays',
              style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12.5)),
          const SizedBox(height: 10),
          Row(
            children: [
              for (var d = 1; d <= 7; d++) ...[
                _DayChip(
                  label: _labels[d - 1],
                  selected: rem.weekdays.contains(d),
                  enabled: enabled,
                  onTap: () => ref
                      .read(reminderSettingsProvider.notifier)
                      .toggleWeekday(d, !rem.weekdays.contains(d)),
                ),
                if (d < 7) const SizedBox(width: 8),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

class _DayChip extends StatelessWidget {
  const _DayChip({
    required this.label,
    required this.selected,
    required this.enabled,
    required this.onTap,
  });
  final String label;
  final bool selected;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final t = Theme.of(context).extension<RedtickTokens>()!;
    final on = selected && enabled;
    return InkWell(
      onTap: enabled ? onTap : null,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        width: 36,
        height: 36,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: on ? cs.primary : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: on ? cs.primary : t.hairline),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            color: on
                ? cs.onPrimary
                : (enabled
                    ? cs.onSurface
                    : cs.onSurfaceVariant.withValues(alpha: 0.4)),
          ),
        ),
      ),
    );
  }
}

/// The reminder's active-hours window (optional). Tapping a pill opens a time
/// picker; the × clears that edge (no bound). Greyed out when the reminder is
/// off.
class _TimeWindowRow extends ConsumerWidget {
  const _TimeWindowRow({required this.enabled});
  final bool enabled;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cs = Theme.of(context).colorScheme;
    final t = Theme.of(context).extension<RedtickTokens>()!;
    final rem = ref.watch(reminderSettingsProvider);
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 14),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: t.hairline)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Active hours',
              style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
          const SizedBox(height: 2),
          Text('Only remind during this window (optional)',
              style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12.5)),
          const SizedBox(height: 10),
          Row(
            children: [
              _TimePill(
                label: 'From',
                value: rem.startHHmm,
                enabled: enabled,
                onPick: (v) =>
                    ref.read(reminderSettingsProvider.notifier).setStart(v),
              ),
              const SizedBox(width: 12),
              _TimePill(
                label: 'To',
                value: rem.endHHmm,
                enabled: enabled,
                onPick: (v) =>
                    ref.read(reminderSettingsProvider.notifier).setEnd(v),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _TimePill extends StatelessWidget {
  const _TimePill({
    required this.label,
    required this.value,
    required this.enabled,
    required this.onPick,
  });
  final String label;
  final String? value;
  final bool enabled;
  final ValueChanged<String?> onPick; // null clears the bound

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final t = Theme.of(context).extension<RedtickTokens>()!;
    final hasValue = value != null && value!.isNotEmpty;
    return InkWell(
      onTap: enabled ? () => _pick(context) : null,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: t.hairline),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('$label  ',
                style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12.5)),
            Text(
              hasValue ? value! : 'Any',
              style: TextStyle(
                fontWeight: FontWeight.w600,
                fontSize: 14,
                color: enabled
                    ? cs.onSurface
                    : cs.onSurfaceVariant.withValues(alpha: 0.4),
              ),
            ),
            if (hasValue && enabled) ...[
              const SizedBox(width: 6),
              GestureDetector(
                onTap: () => onPick(null),
                child: Icon(Icons.close,
                    size: 15, color: cs.onSurfaceVariant),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _pick(BuildContext context) async {
    final mins = minutesOfDay(value);
    final init = mins != null
        ? TimeOfDay(hour: mins ~/ 60, minute: mins % 60)
        : const TimeOfDay(hour: 9, minute: 0);
    final picked = await showTimePicker(context: context, initialTime: init);
    if (picked == null) return;
    final hh = picked.hour.toString().padLeft(2, '0');
    final mm = picked.minute.toString().padLeft(2, '0');
    onPick('$hh:$mm');
  }
}

class _AppearanceCard extends StatelessWidget {
  const _AppearanceCard({
    required this.label,
    required this.mode,
    required this.selected,
    required this.onTap,
  });
  final String label;
  final ThemeMode mode;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final t = Theme.of(context).extension<RedtickTokens>()!;
    return Expanded(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Column(
          children: [
            Container(
              height: 72,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: selected ? cs.primary : t.hairline,
                  width: selected ? 2 : 1,
                ),
              ),
              clipBehavior: Clip.antiAlias,
              child: CustomPaint(painter: _ThumbPainter(mode)),
            ),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                    selected
                        ? Icons.radio_button_checked
                        : Icons.radio_button_unchecked,
                    size: 16,
                    color: selected ? cs.primary : cs.onSurfaceVariant),
                const SizedBox(width: 6),
                Text(label,
                    style: TextStyle(
                        fontWeight:
                            selected ? FontWeight.w700 : FontWeight.w500,
                        fontSize: 13)),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// A tiny app-window preview for the appearance thumbnails.
class _ThumbPainter extends CustomPainter {
  _ThumbPainter(this.mode);
  final ThemeMode mode;

  static const _lightBg = Color(0xFFF6F7F9);
  static const _lightSidebar = Colors.white;
  static const _darkBg = Color(0xFF121214);
  static const _darkSidebar = Color(0xFF161619);

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    void window(Rect r, Color bg, Color sidebar, bool dark) {
      canvas.save();
      canvas.clipRect(r);
      canvas.drawRect(r, Paint()..color = bg);
      canvas.drawRect(
          Rect.fromLTWH(r.left, r.top, r.width * 0.28, r.height),
          Paint()..color = sidebar);
      canvas.drawRRect(
          RRect.fromRectAndRadius(
              Rect.fromLTWH(r.left + 5, r.top + 8, r.width * 0.18, 4),
              const Radius.circular(2)),
          Paint()..color = kBrandRed);
      final line = Paint()
        ..color = (dark ? Colors.white : Colors.black).withValues(alpha: 0.12);
      for (var i = 0; i < 3; i++) {
        canvas.drawRRect(
            RRect.fromRectAndRadius(
                Rect.fromLTWH(r.left + r.width * 0.34, r.top + 10 + i * 12.0,
                    r.width * 0.55, 5),
                const Radius.circular(2)),
            line);
      }
      canvas.restore();
    }

    switch (mode) {
      case ThemeMode.light:
        window(Rect.fromLTWH(0, 0, w, h), _lightBg, _lightSidebar, false);
      case ThemeMode.dark:
        window(Rect.fromLTWH(0, 0, w, h), _darkBg, _darkSidebar, true);
      case ThemeMode.system:
        window(Rect.fromLTWH(0, 0, w / 2, h), _lightBg, _lightSidebar, false);
        window(Rect.fromLTWH(w / 2, 0, w / 2, h), _darkBg, _darkSidebar, true);
    }
  }

  @override
  bool shouldRepaint(covariant _ThumbPainter old) => old.mode != mode;
}
