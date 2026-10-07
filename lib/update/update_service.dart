import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:open_filex/open_filex.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// A published GitHub release that is newer than the running build.
class ReleaseInfo {
  const ReleaseInfo({
    required this.tagName,
    required this.name,
    required this.body,
    required this.apkUrl,
    required this.apkSize,
  });

  final String tagName;
  final String? name;
  final String body;

  /// Direct download URL of the universal APK asset, if one was published.
  final String? apkUrl;
  final int? apkSize;

  bool get hasApk => apkUrl != null;

  String get version => UpdateService._stripTag(tagName);
}

/// Checks GitHub Releases for a newer build, downloads it, and hands it to
/// the Android package installer.
///
/// Releases are public and unauthenticated on purpose: embedding a token in
/// the APK would leak it to anyone who unpacks the app.
class UpdateService {
  UpdateService._();

  static const String repoOwner = 'tear360';
  static const String repoName = 'liber';

  /// GitHub answers 403 to anonymous callers who exceed the rate limit, so
  /// the app only probes every few hours.
  static const Duration checkInterval = Duration(hours: 6);
  static const String _lastCheckKey = 'update_last_check';

  static String get releasesUrl =>
      'https://github.com/$repoOwner/$repoName/releases/latest';

  static Map<String, String> get _headers => <String, String>{
        'Accept': 'application/vnd.github+json',
        'User-Agent': 'Liber-Android-Updater',
        'X-GitHub-Api-Version': '2022-11-28',
      };

  /// Returns the newest release newer than the running version, or null when
  /// the app is up to date (or the check was skipped or failed).
  static Future<ReleaseInfo?> checkForUpdate({bool force = false}) async {
    if (!force && !await _shouldCheck()) return null;

    final info = await PackageInfo.fromPlatform();
    final current = parseVersion(info.version);
    if (current == null) return null;

    final client = http.Client();
    try {
      final response = await client.get(
        Uri.parse(
          'https://api.github.com/repos/$repoOwner/$repoName/releases/latest',
        ),
        headers: _headers,
      );
      await _markChecked();

      if (response.statusCode != 200) return null;
      final decoded = jsonDecode(utf8.decode(response.bodyBytes));
      if (decoded is! Map<String, dynamic>) return null;

      final release = _toRelease(decoded);
      if (release == null) return null;

      final latest = parseVersion(release.tagName);
      if (latest == null || _compare(latest, current) <= 0) return null;
      return release;
    } catch (_) {
      // An update check must never break startup; silently stay current.
      return null;
    } finally {
      client.close();
    }
  }

  /// Downloads the APK, reporting progress as a 0..1 ratio.
  static Future<File> download(
    ReleaseInfo release, {
    void Function(double progress)? onProgress,
  }) async {
    final url = release.apkUrl;
    if (url == null) {
      throw StateError('Cette version ne contient pas de fichier APK.');
    }

    final dir = await getApplicationDocumentsDirectory();
    final target = Directory(p.join(dir.path, 'updates'));
    await target.create(recursive: true);
    final file = File(p.join(target.path, 'liber-${release.version}.apk'));

    final client = http.Client();
    try {
      final request = http.Request('GET', Uri.parse(url));
      request.headers.addAll(_headers);
      request.headers['Accept'] = 'application/octet-stream';

      final response = await client.send(request);
      if (response.statusCode != 200) {
        throw HttpException(
          'Téléchargement impossible (HTTP ${response.statusCode}).',
        );
      }

      final total = response.contentLength ?? release.apkSize ?? 0;
      var received = 0;
      final sink = file.openWrite();
      try {
        await for (final chunk in response.stream) {
          sink.add(chunk);
          received += chunk.length;
          if (total > 0) {
            onProgress?.call((received / total).clamp(0.0, 1.0));
          }
        }
      } finally {
        await sink.close();
      }

      if (total > 0 && received < total) {
        throw const HttpException('Téléchargement interrompu.');
      }
      return file;
    } finally {
      client.close();
    }
  }

  /// Asks Android to install the downloaded package. Returns false when the
  /// user backs out or no installer can handle the file.
  static Future<bool> install(File file) async {
    if (!await file.exists()) return false;
    final result = await OpenFilex.open(
      file.path,
      type: 'application/vnd.android.package-archive',
    );
    return result.type == ResultType.done;
  }

  static ReleaseInfo? _toRelease(Map<String, dynamic> json) {
    final tag = json['tag_name'];
    if (tag is! String || tag.isEmpty) return null;

    String? apkUrl;
    int? apkSize;
    final assets = json['assets'];
    if (assets is List) {
      for (final raw in assets) {
        if (raw is! Map<String, dynamic>) continue;
        final name = raw['name'];
        if (name is! String || !name.toLowerCase().endsWith('.apk')) continue;
        apkUrl = raw['browser_download_url'] as String?;
        final size = raw['size'];
        if (size is int) apkSize = size;
        break;
      }
    }

    return ReleaseInfo(
      tagName: tag,
      name: json['name'] is String ? json['name'] as String : null,
      body: json['body'] is String ? json['body'] as String : '',
      apkUrl: apkUrl,
      apkSize: apkSize,
    );
  }

  static Future<bool> _shouldCheck() async {
    final prefs = await SharedPreferences.getInstance();
    final last = prefs.getInt(_lastCheckKey);
    if (last == null) return true;
    final elapsed = DateTime.now().millisecondsSinceEpoch - last;
    return elapsed >= checkInterval.inMilliseconds;
  }

  static Future<void> _markChecked() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_lastCheckKey, DateTime.now().millisecondsSinceEpoch);
  }

  static String _stripTag(String tag) {
    var value = tag.trim();
    if (value.startsWith('v') || value.startsWith('V')) {
      value = value.substring(1);
    }
    return value;
  }

  /// Parses `v1.2.3` into `[1, 2, 3]`, or null when it is not a version.
  ///
  /// Build metadata after `+` is dropped so `1.0.0+7` and `1.0.0` are the
  /// same release, and a non-numeric segment terminates the parse.
  static List<int>? parseVersion(String raw) {
    var value = _stripTag(raw);
    final build = value.indexOf('+');
    if (build >= 0) value = value.substring(0, build);
    if (value.isEmpty) return null;
    final parts = value.split('.');
    final numbers = <int>[];
    for (final part in parts) {
      final parsed = int.tryParse(part);
      if (parsed == null) break;
      numbers.add(parsed);
    }
    return numbers.isEmpty ? null : numbers;
  }

  static int _compare(List<int> a, List<int> b) {
    final length = a.length > b.length ? a.length : b.length;
    for (var i = 0; i < length; i++) {
      final left = i < a.length ? a[i] : 0;
      final right = i < b.length ? b[i] : 0;
      if (left != right) return left.compareTo(right);
    }
    return 0;
  }
}
