@TestOn('vm')
library;

// Pure parsing of the `redtick://start?issue=N&host=H` browser deep link. No
// plugin/platform — just the `parseStartTimerLink` function.

import 'package:flutter_test/flutter_test.dart';
import 'package:redtick/src/platform/deep_link.dart';

void main() {
  test('parses issue + host', () {
    final cmd = parseStartTimerLink(
        Uri.parse('redtick://start?issue=23409&host=servicedesk.sumanet.cz'));
    expect(cmd, isNotNull);
    expect(cmd!.issueId, 23409);
    expect(cmd.host, 'servicedesk.sumanet.cz');
  });

  test('host is optional', () {
    final cmd = parseStartTimerLink(Uri.parse('redtick://start?issue=7'));
    expect(cmd, isNotNull);
    expect(cmd!.issueId, 7);
    expect(cmd.host, isNull);
  });

  test('empty host is treated as null', () {
    final cmd = parseStartTimerLink(Uri.parse('redtick://start?issue=7&host='));
    expect(cmd, isNotNull);
    expect(cmd!.host, isNull);
  });

  test('rejects non-positive / non-numeric / missing issue', () {
    expect(parseStartTimerLink(Uri.parse('redtick://start?issue=0')), isNull);
    expect(parseStartTimerLink(Uri.parse('redtick://start?issue=-3')), isNull);
    expect(parseStartTimerLink(Uri.parse('redtick://start?issue=abc')), isNull);
    expect(parseStartTimerLink(Uri.parse('redtick://start')), isNull);
  });

  test('rejects a foreign scheme', () {
    expect(parseStartTimerLink(Uri.parse('https://start?issue=1')), isNull);
    expect(parseStartTimerLink(Uri.parse('toggl://start?issue=1')), isNull);
  });

  test('rejects an unknown action (host)', () {
    expect(parseStartTimerLink(Uri.parse('redtick://stop?issue=1')), isNull);
    expect(parseStartTimerLink(Uri.parse('redtick://open?issue=1')), isNull);
  });
}
