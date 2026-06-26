import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:redtick/src/data/release_watch_service.dart';
import 'package:redtick/src/state/release_watch.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('ReleaseWatchService version comparison', () {
    test('detects a newer semver tag', () {
      expect(
        ReleaseWatchService.isUpdateAvailable(
          currentTag: 'v1.0.0',
          latestTag: 'v1.0.1',
        ),
        isTrue,
      );
    });

    test('does not update for equal or older tags', () {
      expect(
        ReleaseWatchService.isUpdateAvailable(
          currentTag: 'v1.0.1',
          latestTag: 'v1.0.1',
        ),
        isFalse,
      );
      expect(
        ReleaseWatchService.isUpdateAvailable(
          currentTag: 'v1.0.2',
          latestTag: 'v1.0.1',
        ),
        isFalse,
      );
    });

    test('ignores dev or invalid current tags', () {
      expect(
        ReleaseWatchService.isUpdateAvailable(
          currentTag: 'dev',
          latestTag: 'v1.0.1',
        ),
        isFalse,
      );
      expect(
        ReleaseWatchService.isUpdateAvailable(
          currentTag: 'feature-dev',
          latestTag: 'v1.0.1',
        ),
        isFalse,
      );
      expect(
        ReleaseWatchService.isUpdateAvailable(
          currentTag: 'not-a-version',
          latestTag: 'v1.0.1',
        ),
        isFalse,
      );
    });
  });

  group('ReleaseWatchService GitHub response handling', () {
    test('parses a 200 latest release response', () async {
      final service = ReleaseWatchService(
        client: MockClient((request) async {
          expect(
            request.url.toString(),
            'https://api.github.com/repos/syky27/redtick/releases/latest',
          );
          return http.Response(
            '{"tag_name":"v1.2.0","html_url":"https://github.com/syky27/redtick/releases/tag/v1.2.0","name":"Redtick 1.2","published_at":"2026-06-26T12:00:00Z"}',
            200,
          );
        }),
      );

      final release = await service.fetchLatestRelease('syky27/redtick');

      expect(release, isNotNull);
      expect(release!.tagName, 'v1.2.0');
      expect(release.htmlUrl, contains('/releases/tag/v1.2.0'));
      expect(release.name, 'Redtick 1.2');
      expect(release.publishedAt, DateTime.utc(2026, 6, 26, 12));
    });

    test(
      'fails silent for error statuses, malformed JSON, and timeout',
      () async {
        for (final status in <int>[403, 404]) {
          final service = ReleaseWatchService(
            client: MockClient(
              (request) async => http.Response('nope', status),
            ),
          );
          expect(await service.fetchLatestRelease('syky27/redtick'), isNull);
        }

        final malformed = ReleaseWatchService(
          client: MockClient((request) async => http.Response('{', 200)),
        );
        expect(await malformed.fetchLatestRelease('syky27/redtick'), isNull);

        final timeout = ReleaseWatchService(
          timeout: const Duration(milliseconds: 1),
          client: MockClient((request) async {
            await Future<void>.delayed(const Duration(milliseconds: 20));
            return http.Response('{}', 200);
          }),
        );
        expect(await timeout.fetchLatestRelease('syky27/redtick'), isNull);
      },
    );
  });

  group('ReleaseWatchNotifier persistence', () {
    test('dismisses one tag and shows a newer tag', () async {
      SharedPreferences.setMockInitialValues({});
      var latestTag = 'v1.0.1';
      final service = ReleaseWatchService(
        client: MockClient(
          (request) async => http.Response(
            '{"tag_name":"$latestTag","html_url":"https://github.com/syky27/redtick/releases/tag/$latestTag"}',
            200,
          ),
        ),
      );
      final container = ProviderContainer(
        overrides: [
          releaseWatchMetadataProvider.overrideWithValue(
            const ReleaseWatchMetadata(
              currentTag: 'v1.0.0',
              repository: 'syky27/redtick',
            ),
          ),
          releaseWatchDesktopProvider.overrideWithValue(true),
          releaseWatchAutoCheckProvider.overrideWithValue(false),
          releaseWatchServiceProvider.overrideWithValue(service),
          releaseWatchClockProvider.overrideWithValue(
            () => DateTime.utc(2026, 6, 26, 12),
          ),
        ],
      );
      addTearDown(container.dispose);

      await container.read(releaseWatchProvider.notifier).checkNow();
      expect(
        container.read(releaseWatchProvider).visibleRelease?.tagName,
        'v1.0.1',
      );

      await container.read(releaseWatchProvider.notifier).dismiss('v1.0.1');
      expect(container.read(releaseWatchProvider).visibleRelease, isNull);

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('release_watch_dismissed_tag'), 'v1.0.1');

      latestTag = 'v1.0.2';
      await container.read(releaseWatchProvider.notifier).checkNow();
      expect(
        container.read(releaseWatchProvider).visibleRelease?.tagName,
        'v1.0.2',
      );
    });
  });
}
