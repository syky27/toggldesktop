import 'package:flutter/material.dart';

import '../../models/time_entry.dart';

/// A single time-entry row (FP-43). Issue-first layout with the description
/// underneath, the formatted duration trailing, and a continue action — mirrors
/// the Qt `timeentrycellwidget` (issue-first rows, clickable Redmine links).
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

  Color? _dotColor() {
    final hex = entry.color.replaceAll('#', '');
    if (hex.length == 6) {
      final v = int.tryParse(hex, radix: 16);
      if (v != null) return Color(0xFF000000 | v);
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final dot = _dotColor();
    return ListTile(
      onTap: onTap,
      leading: dot == null
          ? const Icon(Icons.circle_outlined, size: 12)
          : Icon(Icons.circle, size: 12, color: dot),
      title: Text(
        entry.projectLabel.isNotEmpty ? entry.projectLabel : '(no project)',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: entry.description.isEmpty
          ? null
          : Text(entry.description,
              maxLines: 1, overflow: TextOverflow.ellipsis),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (entry.unsynced)
            const Padding(
              padding: EdgeInsets.only(right: 8),
              child: Icon(Icons.sync_problem, size: 16),
            ),
          Text(entry.duration),
          IconButton(
            icon: const Icon(Icons.play_arrow),
            tooltip: 'Continue',
            onPressed: onContinue,
          ),
        ],
      ),
    );
  }
}
