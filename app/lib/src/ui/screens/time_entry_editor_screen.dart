import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/time_entry.dart';
import '../../state/providers.dart';

/// Time-entry editor (FP-44). Mirrors the Qt `timeentryeditorwidget`: edit
/// description, duration, tags and billable, and delete the entry. Edits are
/// pushed to the core by GUID (`toggl_set_time_entry_*`), which re-emits the
/// updated list via `on_time_entry_list`.
class TimeEntryEditorScreen extends ConsumerStatefulWidget {
  const TimeEntryEditorScreen({super.key, required this.entry});

  final TimeEntry entry;

  @override
  ConsumerState<TimeEntryEditorScreen> createState() =>
      _TimeEntryEditorScreenState();
}

class _TimeEntryEditorScreenState extends ConsumerState<TimeEntryEditorScreen> {
  late final TextEditingController _description =
      TextEditingController(text: widget.entry.description);
  late final TextEditingController _duration =
      TextEditingController(text: widget.entry.duration);
  late final TextEditingController _tags =
      TextEditingController(text: widget.entry.tags);
  late bool _billable = widget.entry.billable;

  @override
  void dispose() {
    _description.dispose();
    _duration.dispose();
    _tags.dispose();
    super.dispose();
  }

  void _save() {
    final core = ref.read(coreServiceProvider);
    final guid = widget.entry.guid;
    core.setDescription(guid, _description.text);
    core.setDuration(guid, _duration.text);
    core.setTags(guid, _tags.text);
    core.setBillable(guid, _billable);
    Navigator.of(context).maybePop();
  }

  Future<void> _delete() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete entry?'),
        content: const Text('This cannot be undone.'),
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
    if (confirm == true) {
      ref.read(coreServiceProvider).deleteEntry(widget.entry.guid);
      if (mounted) Navigator.of(context).maybePop();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Edit entry'),
        actions: [
          IconButton(
              icon: const Icon(Icons.delete_outline), onPressed: _delete),
          IconButton(icon: const Icon(Icons.check), onPressed: _save),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (widget.entry.projectLabel.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Text(widget.entry.projectLabel,
                  style: Theme.of(context).textTheme.titleMedium),
            ),
          TextField(
            controller: _description,
            decoration: const InputDecoration(
                labelText: 'Description', border: OutlineInputBorder()),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _duration,
            decoration: const InputDecoration(
                labelText: 'Duration', border: OutlineInputBorder()),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _tags,
            decoration: const InputDecoration(
                labelText: 'Tags (comma separated)',
                border: OutlineInputBorder()),
          ),
          const SizedBox(height: 12),
          SwitchListTile(
            title: const Text('Billable'),
            value: _billable,
            onChanged: (v) => setState(() => _billable = v),
          ),
        ],
      ),
    );
  }
}
