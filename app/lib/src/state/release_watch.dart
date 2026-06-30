import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../data/release_watch_service.dart';
import 'providers.dart';

const _defaultReleaseTag = String.fromEnvironment(
  'REDTICK_RELEASE_TAG',
  defaultValue: 'dev',
);
const _defaultReleaseRepository = String.fromEnvironment(
  'REDTICK_RELEASE_REPOSITORY',
  defaultValue: 'syky27/redtick',
);

const _unset = Object();

/// Result of a manual [ReleaseWatchNotifier.checkForUpdates] call.
enum UpdateCheckStatus { upToDate, updateAvailable, failed, unsupported }

class UpdateCheckOutcome {
  const UpdateCheckOutcome(this.status, {this.release});

  /// What the check found.
  final UpdateCheckStatus status;

  /// The newer release for [UpdateCheckStatus.updateAvailable]; for
  /// [UpdateCheckStatus.unsupported] (e.g. a `dev` build, whose tag can't be
  /// compared) the latest release seen, for display only.
  final ReleaseInfo? release;
}

class ReleaseWatchMetadata {
  const ReleaseWatchMetadata({
    required this.currentTag,
    required this.repository,
  });

  final String currentTag;
  final String repository;
}

class ReleaseWatchState {
  const ReleaseWatchState({
    required this.currentTag,
    required this.repository,
    this.latest,
    this.dismissedTag,
    this.lastCheckedAt,
    this.checking = false,
  });

  factory ReleaseWatchState.initial(ReleaseWatchMetadata metadata) =>
      ReleaseWatchState(
        currentTag: metadata.currentTag,
        repository: metadata.repository,
      );

  final String currentTag;
  final String repository;
  final ReleaseInfo? latest;
  final String? dismissedTag;
  final DateTime? lastCheckedAt;
  final bool checking;

  ReleaseInfo? get visibleRelease {
    final release = latest;
    if (release == null || release.tagName == dismissedTag) return null;
    return release;
  }

  ReleaseWatchState copyWith({
    String? currentTag,
    String? repository,
    Object? latest = _unset,
    Object? dismissedTag = _unset,
    Object? lastCheckedAt = _unset,
    bool? checking,
  }) => ReleaseWatchState(
    currentTag: currentTag ?? this.currentTag,
    repository: repository ?? this.repository,
    latest: identical(latest, _unset) ? this.latest : latest as ReleaseInfo?,
    dismissedTag: identical(dismissedTag, _unset)
        ? this.dismissedTag
        : dismissedTag as String?,
    lastCheckedAt: identical(lastCheckedAt, _unset)
        ? this.lastCheckedAt
        : lastCheckedAt as DateTime?,
    checking: checking ?? this.checking,
  );
}

final releaseWatchMetadataProvider = Provider<ReleaseWatchMetadata>(
  (ref) => const ReleaseWatchMetadata(
    currentTag: _defaultReleaseTag,
    repository: _defaultReleaseRepository,
  ),
);

final releaseWatchDesktopProvider = Provider<bool>(
  (ref) =>
      !kIsWeb && (Platform.isMacOS || Platform.isWindows || Platform.isLinux),
);

final releaseWatchAutoCheckProvider = Provider<bool>((ref) => true);

final releaseWatchClockProvider = Provider<DateTime Function()>(
  (ref) => DateTime.now,
);

final releaseWatchServiceProvider = Provider<ReleaseWatchService>((ref) {
  final service = ReleaseWatchService(logger: ref.watch(httpLoggerProvider));
  ref.onDispose(service.dispose);
  return service;
});

final releaseWatchProvider =
    NotifierProvider<ReleaseWatchNotifier, ReleaseWatchState>(
      ReleaseWatchNotifier.new,
    );

class ReleaseWatchNotifier extends Notifier<ReleaseWatchState> {
  static const checkInterval = Duration(hours: 24);

  static const _kDismissedTag = 'release_watch_dismissed_tag';
  static const _kLastCheckedAt = 'release_watch_last_checked_at';
  static const _kLatestTag = 'release_watch_latest_tag';
  static const _kLatestUrl = 'release_watch_latest_url';
  static const _kLatestName = 'release_watch_latest_name';
  static const _kLatestPublishedAt = 'release_watch_latest_published_at';

  bool _disposed = false;

  @override
  ReleaseWatchState build() {
    _disposed = false;
    ref.onDispose(() => _disposed = true);

    final metadata = ref.watch(releaseWatchMetadataProvider);
    if (ref.watch(releaseWatchAutoCheckProvider)) {
      unawaited(Future<void>.microtask(refreshIfStale));
    }
    return ReleaseWatchState.initial(metadata);
  }

  Future<void> refreshIfStale() => _loadAndMaybeCheck(force: false);

  @visibleForTesting
  Future<void> checkNow() => _loadAndMaybeCheck(force: true);

  /// Force an update check now, bypassing the 24h interval, and report what it
  /// found. Also updates [state] (and therefore the banner) with the result; on
  /// a network failure the previously known update is kept so the banner
  /// doesn't flicker away.
  Future<UpdateCheckOutcome> checkForUpdates() async {
    final metadata = ref.read(releaseWatchMetadataProvider);
    final service = ref.read(releaseWatchServiceProvider);

    if (ReleaseWatchService.latestReleaseUri(metadata.repository) == null) {
      return const UpdateCheckOutcome(UpdateCheckStatus.failed);
    }

    _setState(state.copyWith(checking: true));
    final fetched = await service.fetchLatestRelease(metadata.repository);
    if (_disposed) return const UpdateCheckOutcome(UpdateCheckStatus.failed);

    final prefs = await SharedPreferences.getInstance();
    if (_disposed) return const UpdateCheckOutcome(UpdateCheckStatus.failed);
    final now = ref.read(releaseWatchClockProvider)().toUtc();
    await prefs.setString(_kLastCheckedAt, now.toIso8601String());
    if (fetched != null) {
      await _writeCachedRelease(prefs, fetched);
    }

    // On success recompute; on failure keep the currently shown update so the
    // banner doesn't disappear just because one manual check couldn't reach
    // GitHub.
    final newLatest = fetched != null
        ? service.updateFor(currentTag: metadata.currentTag, latest: fetched)
        : state.latest;
    _setState(
      state.copyWith(latest: newLatest, lastCheckedAt: now, checking: false),
    );

    if (fetched == null) {
      return const UpdateCheckOutcome(UpdateCheckStatus.failed);
    }
    if (newLatest != null) {
      return UpdateCheckOutcome(
        UpdateCheckStatus.updateAvailable,
        release: newLatest,
      );
    }
    if (ReleaseWatchService.parseTagVersion(metadata.currentTag) == null) {
      return UpdateCheckOutcome(UpdateCheckStatus.unsupported, release: fetched);
    }
    return const UpdateCheckOutcome(UpdateCheckStatus.upToDate);
  }

  Future<void> dismiss(String tagName) async {
    final tag = tagName.trim();
    if (tag.isEmpty) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kDismissedTag, tag);
    _setState(state.copyWith(dismissedTag: tag));
  }

  Future<void> _loadAndMaybeCheck({required bool force}) async {
    final metadata = ref.read(releaseWatchMetadataProvider);
    final service = ref.read(releaseWatchServiceProvider);
    final canCheck =
        ref.read(releaseWatchDesktopProvider) &&
        ReleaseWatchService.parseTagVersion(metadata.currentTag) != null &&
        ReleaseWatchService.latestReleaseUri(metadata.repository) != null;

    if (!canCheck) {
      _setState(ReleaseWatchState.initial(metadata));
      return;
    }

    final prefs = await SharedPreferences.getInstance();
    if (_disposed) return;

    final dismissedTag = _emptyToNull(prefs.getString(_kDismissedTag));
    final lastCheckedAt = _parseDate(prefs.getString(_kLastCheckedAt));
    final cached = service.updateFor(
      currentTag: metadata.currentTag,
      latest: _readCachedRelease(prefs),
    );
    _setState(
      state.copyWith(
        currentTag: metadata.currentTag,
        repository: metadata.repository,
        latest: cached,
        dismissedTag: dismissedTag,
        lastCheckedAt: lastCheckedAt,
      ),
    );

    final now = ref.read(releaseWatchClockProvider)().toUtc();
    final isStale =
        lastCheckedAt == null ||
        now.difference(lastCheckedAt.toUtc()) >= checkInterval;
    if (!force && !isStale) return;

    _setState(state.copyWith(checking: true));
    final fetched = await service.fetchLatestRelease(metadata.repository);
    if (_disposed) return;

    await prefs.setString(_kLastCheckedAt, now.toIso8601String());
    if (fetched != null) {
      await _writeCachedRelease(prefs, fetched);
    }

    final latest = service.updateFor(
      currentTag: metadata.currentTag,
      latest: fetched ?? cached,
    );
    _setState(
      state.copyWith(latest: latest, lastCheckedAt: now, checking: false),
    );
  }

  ReleaseInfo? _readCachedRelease(SharedPreferences prefs) {
    final tagName = _emptyToNull(prefs.getString(_kLatestTag));
    final htmlUrl = _emptyToNull(prefs.getString(_kLatestUrl));
    if (tagName == null || htmlUrl == null) return null;
    return ReleaseInfo(
      tagName: tagName,
      htmlUrl: htmlUrl,
      name: _emptyToNull(prefs.getString(_kLatestName)),
      publishedAt: _parseDate(prefs.getString(_kLatestPublishedAt)),
    );
  }

  Future<void> _writeCachedRelease(
    SharedPreferences prefs,
    ReleaseInfo release,
  ) async {
    await prefs.setString(_kLatestTag, release.tagName);
    await prefs.setString(_kLatestUrl, release.htmlUrl);
    await prefs.setString(_kLatestName, release.name ?? '');
    await prefs.setString(
      _kLatestPublishedAt,
      release.publishedAt?.toUtc().toIso8601String() ?? '',
    );
  }

  void _setState(ReleaseWatchState next) {
    if (!_disposed) state = next;
  }

  static String? _emptyToNull(String? value) {
    final trimmed = value?.trim();
    return trimmed == null || trimmed.isEmpty ? null : trimmed;
  }

  static DateTime? _parseDate(String? value) {
    final parsed = value == null ? null : DateTime.tryParse(value);
    return parsed?.toUtc();
  }
}
