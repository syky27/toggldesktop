import 'package:flutter_test/flutter_test.dart';
import 'package:redtick/src/models/time_entry.dart';

TimeEntry _entry({required int durationInSeconds}) => TimeEntry(
      id: 1,
      guid: 'g',
      description: 'd',
      durationInSeconds: durationInSeconds,
      duration: '00:00',
      projectLabel: 'p',
      taskLabel: '',
      clientLabel: '',
      color: '#ff0000',
      tags: '',
      billable: false,
      started: 0,
      ended: 0,
      startTimeString: '',
      endTimeString: '',
      isHeader: false,
      dateHeader: '',
      dateDuration: '',
      unsynced: false,
      error: '',
      activityId: 0,
    );

void main() {
  test('TimeEntry.isRunning reflects the core duration convention', () {
    // The core encodes a running entry as a negative duration (-startTime).
    expect(_entry(durationInSeconds: -1700000000).isRunning, isTrue);
    expect(_entry(durationInSeconds: 3600).isRunning, isFalse);
  });
}
