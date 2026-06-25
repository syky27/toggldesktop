import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/redmine_service.dart';
import '../../state/providers.dart';
import '../theme.dart';

/// Opens the issue picker (design §3.7) and returns the chosen issue, or null.
Future<IssueResult?> showIssuePicker(BuildContext context) {
  return showDialog<IssueResult>(
    context: context,
    builder: (_) => const _IssuePickerDialog(),
  );
}

class _IssuePickerDialog extends ConsumerStatefulWidget {
  const _IssuePickerDialog();

  @override
  ConsumerState<_IssuePickerDialog> createState() => _IssuePickerDialogState();
}

class _IssuePickerDialogState extends ConsumerState<_IssuePickerDialog> {
  final _search = TextEditingController();
  IssueScope _scope = IssueScope.mine;
  List<IssueResult> _results = const [];
  bool _loading = true;
  Timer? _debounce;
  int _reqId = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _search.dispose();
    super.dispose();
  }

  void _onQuery(String _) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), _load);
  }

  Future<void> _load() async {
    final id = ++_reqId;
    setState(() => _loading = true);
    final res = await ref
        .read(coreServiceProvider)
        .searchIssues(query: _search.text.trim(), scope: _scope);
    if (!mounted || id != _reqId) return;
    setState(() {
      _results = res;
      _loading = false;
    });
  }

  void _setScope(IssueScope s) {
    if (s == _scope) return;
    setState(() => _scope = s);
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final t = Theme.of(context).extension<RedtickTokens>()!;
    return Dialog(
      backgroundColor: cs.surface,
      shape:
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 460, maxHeight: 520),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: TextField(
                controller: _search,
                autofocus: true,
                onChanged: _onQuery,
                decoration: InputDecoration(
                  prefixIcon: const Icon(Icons.search, size: 18),
                  hintText: '#num or text',
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  _SegBtn('My issues', _scope == IssueScope.mine,
                      () => _setScope(IssueScope.mine)),
                  const SizedBox(width: 8),
                  _SegBtn('Assigned', _scope == IssueScope.assigned,
                      () => _setScope(IssueScope.assigned)),
                  const SizedBox(width: 8),
                  _SegBtn('All visible', _scope == IssueScope.all,
                      () => _setScope(IssueScope.all)),
                ],
              ),
            ),
            const SizedBox(height: 8),
            Divider(height: 1, color: t.hairline),
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : _results.isEmpty
                      ? Center(
                          child: Text('No issues',
                              style: TextStyle(color: cs.onSurfaceVariant)))
                      : ListView.separated(
                          itemCount: _results.length,
                          separatorBuilder: (_, _) =>
                              Divider(height: 1, color: t.hairline),
                          itemBuilder: (context, i) =>
                              _Row(issue: _results[i]),
                        ),
            ),
            Divider(height: 1, color: t.hairline),
            Padding(
              padding: const EdgeInsets.all(10),
              child: Row(
                children: [
                  _Hint('↵', 'Start timer'),
                  const SizedBox(width: 16),
                  _Hint('↑↓', 'Navigate'),
                  const Spacer(),
                  _Hint('esc', 'Close'),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({required this.issue});
  final IssueResult issue;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final t = Theme.of(context).extension<RedtickTokens>()!;
    final dot = t.projectColor(issue.projectId);
    return InkWell(
      onTap: () => Navigator.of(context).pop(issue),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
        child: Row(
          children: [
            Container(
              width: 8,
              height: 8,
              margin: const EdgeInsets.only(top: 4),
              decoration: BoxDecoration(color: dot, shape: BoxShape.circle),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(issue.subject,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontWeight: FontWeight.w600, fontSize: 13.5)),
                  const SizedBox(height: 2),
                  Text('#${issue.id} · ${issue.projectName}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style:
                          TextStyle(color: cs.onSurfaceVariant, fontSize: 12)),
                ],
              ),
            ),
            const SizedBox(width: 10),
            _StatusBadge(name: issue.statusName, closed: issue.closed),
          ],
        ),
      ),
    );
  }
}

class _StatusBadge extends StatelessWidget {
  const _StatusBadge({required this.name, required this.closed});
  final String name;
  final bool closed;

  @override
  Widget build(BuildContext context) {
    if (name.isEmpty) return const SizedBox.shrink();
    final c = _color(name, closed);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: c.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(name,
          style: TextStyle(
              color: c, fontSize: 11, fontWeight: FontWeight.w600)),
    );
  }

  static Color _color(String name, bool closed) {
    final n = name.toLowerCase();
    if (closed || n.contains('closed') || n.contains('rejected')) {
      return const Color(0xFF16A34A);
    }
    if (n.contains('progress')) return const Color(0xFFF59E0B);
    if (n.contains('feedback')) return const Color(0xFF8B5CF6);
    if (n.contains('resolved')) return const Color(0xFF0D9488);
    return const Color(0xFF3B82F6); // New / default
  }
}

class _SegBtn extends StatelessWidget {
  const _SegBtn(this.label, this.selected, this.onTap);
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final t = Theme.of(context).extension<RedtickTokens>()!;
    return Material(
      color: selected ? t.accentSoft : Colors.transparent,
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          child: Text(label,
              style: TextStyle(
                  color: selected ? cs.primary : cs.onSurfaceVariant,
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                  fontSize: 12.5)),
        ),
      ),
    );
  }
}

class _Hint extends StatelessWidget {
  const _Hint(this.key_, this.label);
  final String key_;
  final String label;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final t = Theme.of(context).extension<RedtickTokens>()!;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          decoration: BoxDecoration(
            color: cs.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(5),
            border: Border.all(color: t.hairline),
          ),
          child: Text(key_,
              style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant)),
        ),
        const SizedBox(width: 5),
        Text(label, style: TextStyle(fontSize: 11, color: t.faint)),
      ],
    );
  }
}
