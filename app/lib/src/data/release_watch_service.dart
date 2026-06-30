import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:pub_semver/pub_semver.dart';

import 'http_log.dart';

class ReleaseInfo {
  const ReleaseInfo({
    required this.tagName,
    required this.htmlUrl,
    this.name,
    this.publishedAt,
  });

  final String tagName;
  final String htmlUrl;
  final String? name;
  final DateTime? publishedAt;
}

class ReleaseWatchService {
  ReleaseWatchService({
    http.Client? client,
    this.logger,
    this.timeout = const Duration(seconds: 8),
  }) : _client = client ?? http.Client(),
       _ownsClient = client == null;

  final http.Client _client;
  final bool _ownsClient;
  final HttpLogger? logger;
  final Duration timeout;

  static const Map<String, String> _ghHeaders = {
    'Accept': 'application/vnd.github+json',
    'X-GitHub-Api-Version': '2022-11-28',
    'User-Agent': 'redtick-release-watch',
  };

  Future<ReleaseInfo?> fetchLatestRelease(String repository) async {
    final uri = latestReleaseUri(repository);
    if (uri == null) return null;

    final sw = Stopwatch()..start();
    try {
      final response = await _client
          .get(uri, headers: _ghHeaders)
          .timeout(timeout);
      _log(uri, resp: response, elapsed: sw.elapsed);
      if (response.statusCode != 200) return null;

      final decoded = jsonDecode(response.body);
      if (decoded is! Map<String, dynamic>) return null;

      final tagName = decoded['tag_name'];
      final htmlUrl = decoded['html_url'];
      if (tagName is! String ||
          tagName.trim().isEmpty ||
          htmlUrl is! String ||
          htmlUrl.trim().isEmpty) {
        return null;
      }

      final name = decoded['name'];
      final publishedAt = decoded['published_at'];
      return ReleaseInfo(
        tagName: tagName.trim(),
        htmlUrl: htmlUrl.trim(),
        name: name is String && name.trim().isNotEmpty ? name.trim() : null,
        publishedAt: publishedAt is String
            ? DateTime.tryParse(publishedAt)?.toUtc()
            : null,
      );
    } on Object catch (e) {
      _log(uri, elapsed: sw.elapsed, error: e);
      return null;
    }
  }

  void _log(Uri uri, {http.Response? resp, required Duration elapsed,
      Object? error}) {
    final lg = logger;
    if (lg == null || !lg.enabled) return;
    lg.record(
      method: 'GET',
      url: uri.toString(),
      requestHeaders: _ghHeaders,
      statusCode: resp?.statusCode,
      responseHeaders: resp?.headers,
      responseBody: resp?.body,
      elapsed: elapsed,
      error: error,
    );
  }

  ReleaseInfo? updateFor({
    required String currentTag,
    required ReleaseInfo? latest,
  }) {
    if (latest == null) return null;
    return isUpdateAvailable(currentTag: currentTag, latestTag: latest.tagName)
        ? latest
        : null;
  }

  static Uri? latestReleaseUri(String repository) {
    final repo = repository.trim();
    if (!RegExp(r'^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$').hasMatch(repo)) {
      return null;
    }
    final parts = repo.split('/');
    return Uri.https(
      'api.github.com',
      '/repos/${parts[0]}/${parts[1]}/releases/latest',
    );
  }

  static bool isUpdateAvailable({
    required String currentTag,
    required String latestTag,
  }) {
    final current = parseTagVersion(currentTag);
    final latest = parseTagVersion(latestTag);
    if (current == null || latest == null) return false;
    return latest > current;
  }

  static Version? parseTagVersion(String tag) {
    var value = tag.trim();
    if (value.isEmpty || value == 'dev') return null;
    if (value.startsWith('refs/tags/')) {
      value = value.substring('refs/tags/'.length);
    }
    if (value.startsWith('v') || value.startsWith('V')) {
      value = value.substring(1);
    }
    if (value.isEmpty || value.endsWith('-dev')) return null;
    try {
      return Version.parse(value);
    } on FormatException {
      return null;
    }
  }

  void dispose() {
    if (_ownsClient) _client.close();
  }
}
