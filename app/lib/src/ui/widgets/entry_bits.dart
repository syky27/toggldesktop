import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../models/time_entry.dart';
import '../../state/providers.dart';
import '../theme.dart';

/// Parse a `#rrggbb` project color to a [Color].
Color? entryDotColor(String colorHex) {
  final hex = colorHex.replaceAll('#', '');
  if (hex.length == 6) {
    final v = int.tryParse(hex, radix: 16);
    if (v != null) return Color(0xFF000000 | v);
  }
  return null;
}

/// `#4821` from a `#4821: subject` task label.
String issueRef(TimeEntry e) {
  final tl = e.taskLabel;
  if (tl.isEmpty) return '';
  final i = tl.indexOf(':');
  return i > 0 ? tl.substring(0, i) : tl;
}

/// The numeric issue id from a `#4821: subject` task label (0 if none).
int issueNumber(TimeEntry e) {
  final m = RegExp(r'#(\d+)').firstMatch(e.taskLabel);
  return m == null ? 0 : int.parse(m.group(1)!);
}

/// `#4821 · Acme Web` — the design's row sub-line (kept for plain-text uses).
String entrySubline(TimeEntry e) {
  final ref = issueRef(e);
  final proj = e.projectLabel;
  if (ref.isEmpty) return proj;
  if (proj.isEmpty) return ref;
  return '$ref · $proj';
}

/// Open a Redmine issue in the browser.
Future<void> openIssue(WidgetRef ref, int issueId) async {
  final url = ref.read(coreServiceProvider).issueUrl(issueId);
  if (url.isEmpty) return;
  final uri = Uri.parse(url);
  if (await canLaunchUrl(uri)) {
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }
}

class ProjectDot extends StatelessWidget {
  const ProjectDot(this.colorHex, {super.key, this.size = 9});
  final String colorHex;
  final double size;

  @override
  Widget build(BuildContext context) {
    final c = entryDotColor(colorHex) ??
        Theme.of(context).extension<RedtickTokens>()!.faint;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(color: c, shape: BoxShape.circle),
    );
  }
}

/// `#issue · project` where the `#issue` is a clickable link to Redmine.
class EntrySubline extends ConsumerWidget {
  const EntrySubline({super.key, required this.entry});
  final TimeEntry entry;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cs = Theme.of(context).colorScheme;
    final muted = TextStyle(color: cs.onSurfaceVariant, fontSize: 12.5);
    final num = issueNumber(entry);
    final proj = entry.projectLabel;

    if (num == 0) {
      return Text(proj,
          maxLines: 1, overflow: TextOverflow.ellipsis, style: muted);
    }
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        InkWell(
          onTap: () => openIssue(ref, num),
          borderRadius: BorderRadius.circular(4),
          child: Text('#$num',
              style: muted.copyWith(
                  color: cs.primary, fontWeight: FontWeight.w600)),
        ),
        if (proj.isNotEmpty)
          Flexible(
            child: Text(' · $proj',
                maxLines: 1, overflow: TextOverflow.ellipsis, style: muted),
          ),
      ],
    );
  }
}

/// Project dot + clickable `#issue · project` — the timer hero / rows.
class IssueChip extends StatelessWidget {
  const IssueChip({super.key, required this.entry});
  final TimeEntry entry;

  @override
  Widget build(BuildContext context) {
    if (entrySubline(entry).isEmpty) return const SizedBox.shrink();
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        ProjectDot(entry.color, size: 8),
        const SizedBox(width: 6),
        Flexible(child: EntrySubline(entry: entry)),
      ],
    );
  }
}
