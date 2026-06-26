import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:redtick/src/data/release_watch_service.dart';
import 'package:redtick/src/state/release_watch.dart';
import 'package:redtick/src/ui/theme.dart';
import 'package:redtick/src/ui/widgets/release_update_banner.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  GoogleFonts.config.allowRuntimeFetching = false;

  testWidgets('release banner renders, opens release URL, and dismisses', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});

    Uri? launched;
    late WidgetRef capturedRef;
    final service = ReleaseWatchService(
      client: MockClient(
        (request) async => http.Response(
          '{"tag_name":"v1.0.1","html_url":"https://github.com/syky27/redtick/releases/tag/v1.0.1"}',
          200,
        ),
      ),
    );

    await tester.pumpWidget(
      ProviderScope(
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
          releaseLinkLauncherProvider.overrideWithValue((uri) async {
            launched = uri;
            return true;
          }),
        ],
        child: MaterialApp(
          theme: RedtickTheme.light(),
          home: Scaffold(
            body: Consumer(
              builder: (context, ref, _) {
                capturedRef = ref;
                return const ReleaseUpdateBanner();
              },
            ),
          ),
        ),
      ),
    );

    expect(find.text('Redtick v1.0.1 is available'), findsNothing);

    await capturedRef.read(releaseWatchProvider.notifier).checkNow();
    await tester.pumpAndSettle();

    expect(find.text('Redtick v1.0.1 is available'), findsOneWidget);

    await tester.tap(find.text('View release'));
    await tester.pump();
    expect(
      launched,
      Uri.parse('https://github.com/syky27/redtick/releases/tag/v1.0.1'),
    );

    await tester.tap(find.byIcon(Icons.close));
    await tester.pumpAndSettle();

    expect(find.text('Redtick v1.0.1 is available'), findsNothing);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('release_watch_dismissed_tag'), 'v1.0.1');
  });
}
