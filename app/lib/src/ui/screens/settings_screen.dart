import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../state/providers.dart';
import '../../state/theme_mode.dart';
import '../theme.dart';

/// Preferences (design §3.8 / §4): Appearance picker, Redmine account, Tracking.
class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final core = ref.watch(coreServiceProvider);
    final mode = ref.watch(themeModeProvider);
    final cs = Theme.of(context).colorScheme;

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
          ],
        ),
      ),
    );
  }
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
