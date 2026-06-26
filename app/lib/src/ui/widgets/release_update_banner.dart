import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../state/release_watch.dart';
import '../theme.dart';

typedef ReleaseLinkLauncher = Future<bool> Function(Uri uri);

final releaseLinkLauncherProvider = Provider<ReleaseLinkLauncher>(
  (ref) =>
      (uri) => launchUrl(uri, mode: LaunchMode.externalApplication),
);

class ReleaseUpdateBannerHost extends StatelessWidget {
  const ReleaseUpdateBannerHost({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        const ReleaseUpdateBanner(),
        Expanded(child: child),
      ],
    );
  }
}

class ReleaseUpdateBanner extends ConsumerWidget {
  const ReleaseUpdateBanner({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final release = ref.watch(releaseWatchProvider).visibleRelease;
    if (release == null) return const SizedBox.shrink();

    final cs = Theme.of(context).colorScheme;
    final t = Theme.of(context).extension<RedtickTokens>()!;
    final releaseUri = Uri.tryParse(release.htmlUrl);

    return Material(
      color: t.accentSoft,
      child: SafeArea(
        bottom: false,
        child: Container(
          width: double.infinity,
          decoration: BoxDecoration(
            border: Border(bottom: BorderSide(color: t.hairline)),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          child: Row(
            children: [
              Icon(Icons.system_update_alt, size: 18, color: cs.primary),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Redtick ${release.tagName} is available',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: cs.onSurface,
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              TextButton.icon(
                onPressed: releaseUri == null
                    ? null
                    : () => ref.read(releaseLinkLauncherProvider)(releaseUri),
                icon: const Icon(Icons.open_in_new, size: 16),
                label: const Text('View release'),
                style: TextButton.styleFrom(
                  foregroundColor: cs.primary,
                  visualDensity: VisualDensity.compact,
                ),
              ),
              Tooltip(
                message: 'Dismiss',
                child: IconButton(
                  onPressed: () => ref
                      .read(releaseWatchProvider.notifier)
                      .dismiss(release.tagName),
                  icon: const Icon(Icons.close, size: 18),
                  color: cs.onSurfaceVariant,
                  visualDensity: VisualDensity.compact,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
