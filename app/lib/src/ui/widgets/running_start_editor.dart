import 'package:flutter/material.dart';

import '../../data/redmine_service.dart';
import '../../models/time_entry.dart';

/// Adjust a *running* timer's elapsed time (design §3.3 hero bar): a compact
/// modal to correct the start when you began tracking a few minutes late.
/// Editing the elapsed duration shifts the start so `start = now - elapsed`.
Future<void> showRunningStartEditor(
  BuildContext context,
  RedmineService core,
  TimeEntry entry,
) {
  return showDialog<void>(
    context: context,
    builder: (_) => _RunningStartDialog(core: core, entry: entry),
  );
}

class _RunningStartDialog extends StatefulWidget {
  const _RunningStartDialog({required this.core, required this.entry});
  final RedmineService core;
  final TimeEntry entry;

  @override
  State<_RunningStartDialog> createState() => _RunningStartDialogState();
}

class _RunningStartDialogState extends State<_RunningStartDialog> {
  late final TextEditingController _elapsed =
      TextEditingController(text: _fmtHHMM(_currentElapsed()));
  bool _saving = false;
  bool _error = false;

  Duration _currentElapsed() {
    final startedAt =
        DateTime.fromMillisecondsSinceEpoch(widget.entry.started * 1000);
    final d = DateTime.now().difference(startedAt);
    return d.isNegative ? Duration.zero : d;
  }

  @override
  void dispose() {
    _elapsed.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final dur = _parseElapsed(_elapsed.text);
    if (dur == null) {
      setState(() => _error = true);
      return;
    }
    setState(() {
      _saving = true;
      _error = false;
    });
    final newStart = DateTime.now().subtract(dur);
    final ok = await widget.core.adjustRunningStart(widget.entry.guid, newStart);
    if (!mounted) return;
    if (ok) {
      Navigator.of(context).pop();
    } else {
      setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final dur = _parseElapsed(_elapsed.text);
    final hint = dur == null
        ? null
        : 'Starts at ${_fmtClock(DateTime.now().subtract(dur))}';

    return Dialog(
      backgroundColor: cs.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 380),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text('Adjust running timer',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context)
                            .textTheme
                            .titleMedium
                            ?.copyWith(fontWeight: FontWeight.w700)),
                  ),
                  IconButton(
                      icon: const Icon(Icons.close, size: 20),
                      onPressed: () => Navigator.of(context).pop()),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                'Set how long you have actually been working — the start time '
                'moves to match.',
                style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12),
              ),
              const SizedBox(height: 16),
              _label(cs, 'Elapsed'),
              TextField(
                controller: _elapsed,
                autofocus: true,
                onChanged: (_) => setState(() => _error = false),
                onSubmitted: (_) => _saving ? null : _save(),
                decoration: const InputDecoration(hintText: 'H:MM'),
              ),
              const SizedBox(height: 8),
              if (_error)
                Text('Enter a valid duration (e.g. 0:20 or 1:30).',
                    style: TextStyle(color: cs.error, fontSize: 12))
              else if (hint != null)
                Text(hint,
                    style:
                        TextStyle(color: cs.onSurfaceVariant, fontSize: 12)),
              const SizedBox(height: 20),
              Row(
                children: [
                  const Spacer(),
                  TextButton(
                      onPressed: () => Navigator.of(context).pop(),
                      child: const Text('Cancel')),
                  const SizedBox(width: 8),
                  FilledButton.icon(
                    onPressed: _saving ? null : _save,
                    icon: _saving
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: Colors.white))
                        : const Icon(Icons.check, size: 18),
                    label: const Text('Save'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _label(ColorScheme cs, String s) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Text(s,
            style: TextStyle(
                color: cs.onSurfaceVariant,
                fontSize: 12,
                fontWeight: FontWeight.w600)),
      );

  /// "H:MM" for the elapsed field prefill.
  static String _fmtHHMM(Duration d) {
    final h = d.inHours;
    final m = d.inMinutes % 60;
    return '$h:${m.toString().padLeft(2, '0')}';
  }

  static String _fmtClock(DateTime d) =>
      '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';

  /// Parse "H:MM" (or decimal hours "1.5" / "1,5") → a Duration; null if invalid
  /// or negative. Mirrors the editor's duration parsing.
  static Duration? _parseElapsed(String s) {
    final v = s.trim();
    if (v.isEmpty) return null;
    final colon = RegExp(r'^(\d+):([0-5]?\d)$').firstMatch(v);
    if (colon != null) {
      final h = int.parse(colon.group(1)!);
      final m = int.parse(colon.group(2)!);
      return Duration(hours: h, minutes: m);
    }
    final dec = double.tryParse(v.replaceAll(',', '.'));
    if (dec == null || dec < 0) return null;
    return Duration(seconds: (dec * 3600).round());
  }
}
