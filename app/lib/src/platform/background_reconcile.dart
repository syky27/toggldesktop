import 'dart:io' show Platform;

import 'package:flutter/widgets.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:live_activities/live_activities.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:workmanager/workmanager.dart';

import '../data/redmine_api_client.dart';
import '../data/redmine_service.dart' show kRedmineBaseUrlKey, kRedmineApiKeyKey;
import 'live_timer_android.dart' show kRunningNotificationId;

/// iOS background-task identifier. MUST match `BGTaskSchedulerPermittedIdentifiers`
/// in `ios/Runner/Info.plist` and the `WorkmanagerPlugin.registerPeriodicTask`
/// call in `ios/Runner/AppDelegate.swift`.
const String kReconcileTaskId = 'cz.syky.redtick.reconcile';

const String _appGroupId = 'group.cz.syky.redtick';

/// workmanager entry point. iOS runs this in a background isolate when it grants
/// a BGAppRefresh window. Top-level + `vm:entry-point` so AOT keeps it.
@pragma('vm:entry-point')
void backgroundDispatcher() {
  Workmanager().executeTask((_, _) async {
    await reconcileLiveActivity();
    return true;
  });
}

/// Best-effort cross-device reconcile from the background: if Redmine shows no
/// running timer, end any lingering live surface (iOS Live Activity / Android
/// ongoing notification). This covers the gap the foreground 30 s poll can't —
/// a timer stopped on another device while this phone is locked (the Dart poll
/// is suspended while backgrounded). Never throws.
Future<void> reconcileLiveActivity() async {
  if (!Platform.isIOS && !Platform.isAndroid) return;
  RedmineApiClient? api;
  try {
    WidgetsFlutterBinding.ensureInitialized();

    final prefs = await SharedPreferences.getInstance();
    final base = prefs.getString(kRedmineBaseUrlKey) ?? '';
    final key = await _readApiKey(prefs);
    if (base.isEmpty || key.isEmpty) return; // not logged in → nothing to do

    api = RedmineApiClient(baseUrl: base, apiKey: key);
    final entries = await api.recentTimeEntries();
    if (entries.any(_isOpen)) return; // a timer is still running → leave it

    // Nothing running anywhere → make sure no live surface is stuck.
    await _endStaleSurface();
  } catch (_) {
    // Best-effort; the OS retries on a future window, and a foreground resume
    // refresh is the reliable fallback.
  } finally {
    api?.dispose();
  }
}

/// Tear down a lingering running-timer surface from the background isolate (the
/// UI-isolate controller isn't running here, so act on the platform directly).
Future<void> _endStaleSurface() async {
  if (Platform.isAndroid) {
    // Cancel the ongoing notification by its stable id; no-op if absent.
    await FlutterLocalNotificationsPlugin().cancel(id: kRunningNotificationId);
    return;
  }
  // iOS: end the Live Activity via the shared App Group. endAllActivities is a
  // no-op if none exist.
  final la = LiveActivities();
  await la.init(appGroupId: _appGroupId);
  await la.endAllActivities();
}

Future<String> _readApiKey(SharedPreferences prefs) async {
  try {
    const secure = FlutterSecureStorage(
      aOptions: AndroidOptions(encryptedSharedPreferences: true),
    );
    final v = await secure.read(key: kRedmineApiKeyKey);
    if (v != null && v.isNotEmpty) return v;
  } catch (_) {/* keychain unavailable */}
  return prefs.getString(kRedmineApiKeyKey) ?? '';
}

/// A raw Redmine `time_entry` is *open* (running) when its `toggl_stop` custom
/// field is empty/absent (the cross-device running marker).
bool _isOpen(Map<String, dynamic> e) {
  final cfs = e['custom_fields'];
  if (cfs is! List) return false;
  for (final cf in cfs) {
    if (cf is Map && cf['name'] == 'toggl_stop') {
      final v = cf['value'];
      return v == null || (v is String && v.isEmpty);
    }
  }
  return false;
}
