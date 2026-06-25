import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/redmine_service.dart';
import '../../models/time_entry.dart';
import '../../state/providers.dart';
import '../theme.dart';
import '../widgets/entry_bits.dart';
import '../widgets/issue_picker.dart';

/// Open the time-entry editor (design §3.6) as a modal.
Future<void> showEntryEditor(BuildContext context, TimeEntry entry) {
  return showDialog<void>(
    context: context,
    builder: (_) => _EntryEditorDialog(entry: entry),
  );
}

class _EntryEditorDialog extends ConsumerStatefulWidget {
  const _EntryEditorDialog({required this.entry});
  final TimeEntry entry;

  @override
  ConsumerState<_EntryEditorDialog> createState() => _EntryEditorDialogState();
}

class _EntryEditorDialogState extends ConsumerState<_EntryEditorDialog> {
  late final TextEditingController _desc =
      TextEditingController(text: widget.entry.description);
  late final TextEditingController _start =
      TextEditingController(text: widget.entry.startTimeString);
  late final TextEditingController _end =
      TextEditingController(text: widget.entry.endTimeString);

  late int _activityId = widget.entry.activityId;
  late int _issueId = _parseIssueId(widget.entry.taskLabel);
  late String _issueSubject = _parseIssueSubject(widget.entry.taskLabel);
  late DateTime _date = widget.entry.started > 0
      ? DateTime.fromMillisecondsSinceEpoch(widget.entry.started * 1000)
      : DateTime.now();
  bool _saving = false;
  bool _timeError = false;

  @override
  void dispose() {
    _desc.dispose();
    _start.dispose();
    _end.dispose();
    super.dispose();
  }

  Duration get _duration {
    final s = _parseTime(_start.text, _date);
    var e = _parseTime(_end.text, _date);
    if (s == null || e == null) return Duration.zero;
    if (!e.isAfter(s)) e = e.add(const Duration(days: 1)); // overnight
    return e.difference(s);
  }

  Future<void> _pickIssue() async {
    final issue = await showIssuePicker(context);
    if (issue == null) return;
    setState(() {
      _issueId = issue.id;
      _issueSubject = issue.subject;
    });
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(2015),
      lastDate: DateTime(2100),
    );
    if (picked != null) setState(() => _date = picked);
  }

  Future<void> _save() async {
    final start = _parseTime(_start.text, _date);
    var end = _parseTime(_end.text, _date);
    if (start == null || end == null) {
      setState(() => _timeError = true);
      return;
    }
    if (!end.isAfter(start)) end = end.add(const Duration(days: 1)); // overnight
    setState(() {
      _saving = true;
      _timeError = false;
    });
    final ok = await ref.read(coreServiceProvider).updateEntry(
          guid: widget.entry.guid,
          description: _desc.text,
          start: start,
          end: end,
          activityId: _activityId == 0 ? null : _activityId,
          issueId: _issueId == 0 ? null : _issueId,
          issueSubject: _issueSubject,
        );
    if (!mounted) return;
    if (ok) {
      Navigator.of(context).pop();
    } else {
      setState(() => _saving = false);
    }
  }

  Future<void> _delete() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete entry?'),
        content: const Text('This removes the time entry from Redmine.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Delete')),
        ],
      ),
    );
    if (confirm != true) return;
    ref.read(coreServiceProvider).deleteEntry(widget.entry.guid);
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final t = Theme.of(context).extension<RedtickTokens>()!;
    final core = ref.read(coreServiceProvider);
    final activities = core.availableActivities;

    return Dialog(
      backgroundColor: cs.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 460),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Text('Edit time entry',
                      style: Theme.of(context)
                          .textTheme
                          .titleMedium
                          ?.copyWith(fontWeight: FontWeight.w700)),
                  const Spacer(),
                  IconButton(
                      icon: const Icon(Icons.close, size: 20),
                      onPressed: () => Navigator.of(context).pop()),
                ],
              ),
              const SizedBox(height: 12),
              _label('Description'),
              TextField(controller: _desc),
              const SizedBox(height: 16),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    flex: 3,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [_label('Issue'), _issueField(cs, t)],
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    flex: 2,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [_label('Activity'), _activityField(activities)],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _label('Start'),
                        TextField(
                            controller: _start,
                            onChanged: (_) => setState(() {}),
                            decoration: const InputDecoration(hintText: 'HH:mm')),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _label('End'),
                        TextField(
                            controller: _end,
                            onChanged: (_) => setState(() {}),
                            decoration: const InputDecoration(hintText: 'HH:mm')),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [_label('Date'), _dateField()],
                    ),
                  ),
                ],
              ),
              if (_timeError) ...[
                const SizedBox(height: 8),
                Text('Enter valid start and end times (HH:mm).',
                    style: TextStyle(color: cs.error, fontSize: 12)),
              ],
              const SizedBox(height: 18),
              Row(
                children: [
                  Text('Duration → Redmine hours',
                      style: TextStyle(color: cs.onSurfaceVariant)),
                  const Spacer(),
                  Text(_fmt(_duration),
                      style: RedtickTheme.mono(
                          fontSize: 20,
                          fontWeight: FontWeight.w700,
                          color: cs.onSurface)),
                ],
              ),
              const SizedBox(height: 20),
              Row(
                children: [
                  TextButton.icon(
                    onPressed: _delete,
                    icon: Icon(Icons.delete_outline, color: cs.error, size: 18),
                    label: Text('Delete', style: TextStyle(color: cs.error)),
                  ),
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

  Widget _label(String s) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Text(s,
            style: TextStyle(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
                fontSize: 12,
                fontWeight: FontWeight.w600)),
      );

  Widget _issueField(ColorScheme cs, RedtickTokens t) {
    final label = _issueId == 0
        ? 'No issue'
        : '#$_issueId${_issueSubject.isNotEmpty ? '  $_issueSubject' : ''}';
    return Container(
      height: 48,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: Theme.of(context).inputDecorationTheme.fillColor,
        borderRadius: BorderRadius.circular(11),
        border: Border.all(color: cs.outline),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 13)),
          ),
          if (_issueId != 0)
            IconButton(
              icon: const Icon(Icons.open_in_new, size: 16),
              tooltip: 'Open in Redmine',
              visualDensity: VisualDensity.compact,
              onPressed: () => openIssue(ref, _issueId),
            ),
          TextButton(
            onPressed: _pickIssue,
            style: TextButton.styleFrom(
                minimumSize: const Size(0, 32),
                padding: const EdgeInsets.symmetric(horizontal: 10)),
            child: const Text('Change'),
          ),
        ],
      ),
    );
  }

  Widget _activityField(List<Activity> activities) {
    final ids = activities.map((a) => a.id).toSet();
    final value = ids.contains(_activityId) ? _activityId : null;
    return DropdownButtonFormField<int>(
      initialValue: value,
      isExpanded: true,
      items: [
        for (final a in activities)
          DropdownMenuItem(value: a.id, child: Text(a.name)),
      ],
      onChanged: (v) => setState(() => _activityId = v ?? _activityId),
    );
  }

  Widget _dateField() {
    return InkWell(
      onTap: _pickDate,
      borderRadius: BorderRadius.circular(11),
      child: Container(
        height: 48,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        alignment: Alignment.centerLeft,
        decoration: BoxDecoration(
          color: Theme.of(context).inputDecorationTheme.fillColor,
          borderRadius: BorderRadius.circular(11),
          border: Border.all(color: Theme.of(context).colorScheme.outline),
        ),
        child: Text(_dateLabel(_date), style: const TextStyle(fontSize: 13)),
      ),
    );
  }

  static const _months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
  ];
  static String _dateLabel(DateTime d) => '${_months[d.month - 1]} ${d.day}';

  static int _parseIssueId(String taskLabel) {
    final m = RegExp(r'#(\d+)').firstMatch(taskLabel);
    return m == null ? 0 : int.parse(m.group(1)!);
  }

  static String _parseIssueSubject(String taskLabel) {
    final i = taskLabel.indexOf(':');
    return i > 0 ? taskLabel.substring(i + 1).trim() : '';
  }

  static DateTime? _parseTime(String hhmm, DateTime date) {
    final m = RegExp(r'^\s*(\d{1,2}):(\d{2})\s*$').firstMatch(hhmm);
    if (m == null) return null;
    final h = int.parse(m.group(1)!);
    final min = int.parse(m.group(2)!);
    if (h > 23 || min > 59) return null;
    return DateTime(date.year, date.month, date.day, h, min);
  }

  static String _fmt(Duration d) {
    final h = d.inHours;
    final m = d.inMinutes % 60;
    final s = d.inSeconds % 60;
    return '$h:${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }
}
