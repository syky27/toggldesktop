import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import 'redmine_api_client.dart';

/// A durable queue of Redmine writes that failed because the network was down.
/// Each op is replayed (in order) when connectivity returns; ops are idempotent
/// enough (`toggl_guid` on creates, PUT/DELETE on existing ids) that a single
/// replay is safe. Persisted as JSON so a queued stop survives an app restart.
///
/// Scoped to the realistic offline case: a stop/edit/delete that couldn't reach
/// the server. (Starting a timer offline keeps running locally; its finished
/// entry is queued as a `create` on stop.)
class OfflineQueue {
  OfflineQueue([this._fileOverride]);

  final Future<File> Function()? _fileOverride;
  final List<Map<String, dynamic>> _ops = [];
  bool _loaded = false;

  int get length => _ops.length;

  Future<File> _file() async {
    final override = _fileOverride;
    if (override != null) return override();
    final dir = await getApplicationSupportDirectory();
    return File('${dir.path}/redtick_pending.json');
  }

  Future<void> _ensureLoaded() async {
    if (_loaded) return;
    _loaded = true;
    try {
      final f = await _file();
      if (await f.exists()) {
        final decoded = jsonDecode(await f.readAsString());
        if (decoded is List) {
          _ops.addAll(decoded.whereType<Map<String, dynamic>>());
        }
      }
    } catch (_) {/* corrupt/missing → start empty */}
  }

  Future<void> _save() async {
    try {
      final f = await _file();
      await f.writeAsString(jsonEncode(_ops));
    } catch (_) {}
  }

  Future<void> enqueue(Map<String, dynamic> op) async {
    await _ensureLoaded();
    _ops.add(op);
    await _save();
  }

  /// Replay queued ops in order. Stops at the first **network** failure (still
  /// offline — keep them for next time); drops an op that fails for a permanent
  /// reason (e.g. the entry was deleted server-side). Returns #flushed.
  Future<int> replay(RedmineApiClient api) async {
    await _ensureLoaded();
    var flushed = 0;
    while (_ops.isNotEmpty) {
      try {
        await _apply(api, _ops.first);
        _ops.removeAt(0);
        flushed++;
        await _save();
      } on RedmineException catch (e) {
        if (e.kind == RedmineErrorKind.network) break;
        _ops.removeAt(0); // permanent failure → don't retry forever
        await _save();
      }
    }
    return flushed;
  }

  Future<void> _apply(RedmineApiClient api, Map<String, dynamic> op) async {
    DateTime? millis(Object? v) =>
        v is int ? DateTime.fromMillisecondsSinceEpoch(v) : null;
    switch (op['kind']) {
      case 'create':
        await api.createTimeEntry(
          issueId: op['issueId'] as int,
          projectId: op['projectId'] as int,
          hours: (op['hours'] as num).toDouble(),
          spentOn: millis(op['spentOn'])!,
          comments: op['comments'] as String,
          activityId: op['activityId'] as int,
          togglStart: op['togglStart'] as String,
          togglStop: op['togglStop'] as String,
          togglGuid: op['togglGuid'] as String,
          cfStart: op['cfStart'] as int,
          cfStop: op['cfStop'] as int,
          cfGuid: op['cfGuid'] as int,
        );
      case 'update':
        await api.updateTimeEntry(
          id: op['id'] as int,
          hours: (op['hours'] as num?)?.toDouble(),
          comments: op['comments'] as String?,
          activityId: op['activityId'] as int?,
          issueId: op['issueId'] as int?,
          spentOn: millis(op['spentOn']),
          togglStart: op['togglStart'] as String?,
          togglStop: op['togglStop'] as String?,
          cfStart: (op['cfStart'] as int?) ?? 0,
          cfStop: (op['cfStop'] as int?) ?? 0,
        );
      case 'delete':
        await api.deleteTimeEntry(op['id'] as int);
    }
  }
}
