import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../model.dart';
import 'update_helper.dart';

const appVersion = '2.0.31';
const updateRepository = String.fromEnvironment(
  'UPDATE_REPOSITORY',
  defaultValue: 'RobinPopkema/Digitalguest-breakfast-orders',
);

bool newerVersion(String candidate, String current) {
  List<int>? parts(String value) {
    final match = RegExp(r'^v?(\d+)\.(\d+)\.(\d+)$').firstMatch(value);
    return match == null
        ? null
        : [for (var i = 1; i <= 3; i++) int.parse(match[i]!)];
  }

  final a = parts(candidate), b = parts(current);
  if (a == null || b == null) return false;
  for (var i = 0; i < 3; i++) {
    if (a[i] != b[i]) return a[i] > b[i];
  }
  return false;
}

Json? eligibleUpdate(Json release, String repository, String current) {
  if (release['draft'] != false ||
      release['prerelease'] != false ||
      !newerVersion('${release['tag_name']}', current)) {
    return null;
  }
  for (final asset in rows(release['assets'] ?? [])) {
    final uri = Uri.tryParse('${asset['browser_download_url']}');
    final digest = '${asset['digest']}';
    if (uri == null ||
        uri.scheme != 'https' ||
        uri.host != 'github.com' ||
        !uri.path.startsWith('/$repository/releases/download/') ||
        !RegExp(r'^Breakfast-Orders-Flutter-[\w.\-]+-Windows\.zip$')
            .hasMatch('${asset['name']}') ||
        !RegExp(r'^sha256:[a-fA-F0-9]{64}$').hasMatch(digest) ||
        asset['size'] is! int ||
        asset['size'] <= 0 ||
        asset['size'] > 200000000) {
      continue;
    }
    return {
      ...asset,
      'version': release['tag_name'],
      'notes': release['body'] ?? '',
      'sha256': digest.substring(7).toLowerCase(),
    };
  }
  return null;
}

class Updates extends ChangeNotifier {
  Updates({this.repository = updateRepository});
  final String repository;
  final HttpClient _client = HttpClient()
    ..connectionTimeout = const Duration(seconds: 20);
  Timer? _timer;
  bool _disposed = false, checking = false, installing = false;
  Json? available;
  String? error;
  double progress = 0;
  bool get configured => RegExp(r'^[\w.-]+/[\w.-]+$').hasMatch(repository);
  void changed() {
    if (!_disposed) notifyListeners();
  }

  void start() {
    if (!configured) return;
    unawaited(check());
    _timer?.cancel();
    _timer = Timer.periodic(
      const Duration(hours: 4),
      (_) => unawaited(check()),
    );
  }

  Future<HttpClientResponse> request(Uri uri, {int redirects = 0}) async {
    if (uri.scheme != 'https' ||
        !{
          'api.github.com',
          'github.com',
          'release-assets.githubusercontent.com',
          'objects.githubusercontent.com',
        }.contains(uri.host)) {
      throw StateError('Unexpected update download address.');
    }
    final req = await _client.getUrl(uri).timeout(const Duration(seconds: 30));
    req.followRedirects = false;
    req.headers.set('User-Agent', 'Breakfast-Orders/$appVersion');
    req.headers.set('Accept', 'application/vnd.github+json');
    final response = await req.close().timeout(const Duration(seconds: 30));
    if ({301, 302, 303, 307, 308}.contains(response.statusCode)) {
      final location = response.headers.value('location');
      await response.drain<void>();
      if (location == null || redirects >= 5) {
        throw StateError('Invalid update redirect.');
      }
      return request(uri.resolve(location), redirects: redirects + 1);
    }
    return response;
  }

  Future<void> check() async {
    if (checking || installing || !configured) return;
    checking = true;
    error = null;
    changed();
    try {
      final response = await request(
        Uri.https('api.github.com', '/repos/$repository/releases/latest'),
      );
      if (response.statusCode == 404) {
        available = null;
        await response.drain<void>();
        return;
      }
      if (response.statusCode != 200) {
        await response.drain<void>();
        throw StateError('Update check failed. Try again later.');
      }
      final bytes = <int>[];
      await for (final chunk in response.timeout(const Duration(seconds: 30))) {
        bytes.addAll(chunk);
        if (bytes.length > 2000000) {
          throw StateError('Update response is too large.');
        }
      }
      available = eligibleUpdate(
        jsonDecode(utf8.decode(bytes)) as Json,
        repository,
        appVersion,
      );
    } catch (e) {
      error = '$e';
    } finally {
      checking = false;
      changed();
    }
  }

  Future<void> install(String profile) async {
    final release = available;
    if (release == null || installing) return;
    installing = true;
    progress = 0;
    error = null;
    changed();
    try {
      if (!Platform.isWindows) {
        throw StateError('Automatic installation requires Windows.');
      }
      final work = await Directory.systemTemp.createTemp(
        'Breakfast-Orders-Update-',
      );
      final zip = File('${work.path}/release.zip');
      final response = await request(
        Uri.parse(release['browser_download_url']),
      );
      if (response.statusCode != 200) {
        await response.drain<void>();
        throw StateError('Could not download the update.');
      }
      final sink = zip.openWrite();
      var received = 0;
      try {
        await for (final chunk in response.timeout(
          const Duration(seconds: 60),
        )) {
          received += chunk.length;
          if (received > release['size']) {
            throw StateError('Update size does not match.');
          }
          sink.add(chunk);
          progress = received / release['size'];
          changed();
        }
      } finally {
        await sink.close();
      }
      if (received != release['size'] ||
          (await sha256.bind(zip.openRead()).first).toString() !=
              release['sha256']) {
        throw StateError(
          'Update verification failed. Your application was not changed.',
        );
      }
      final helper = File('${work.path}/install.ps1');
      await helper.writeAsString(
        await rootBundle.loadString('assets/update/install.ps1'),
        flush: true,
      );
      final config = File('${work.path}/update.json');
      await config.writeAsString(
        jsonEncode({
          'pid': pid,
          'install': File(Platform.resolvedExecutable).parent.path,
          'profile': profile,
          'zip': zip.path,
          'sha256': release['sha256'],
        }),
        flush: true,
      );
      final helperProcess = await launchUpdateHelper(helper, config, work);
      int? helperExit;
      unawaited(
        helperProcess.exitCode.then<void>((value) {
          helperExit = value;
        }),
      );
      final ready = File('${work.path}/ready');
      for (var attempt = 0; attempt < 180 && !await ready.exists(); attempt++) {
        if (helperExit != null ||
            await File('${work.path}/error.txt').exists()) {
          throw StateError(
            'Could not prepare the update. Your app is still running. '
            'Details: ${work.path}',
          );
        }
        await Future<void>.delayed(const Duration(milliseconds: 500));
      }
      if (!await ready.exists()) {
        throw StateError(
          'The update helper did not start. Your app is still running.',
        );
      }
      exit(0);
    } catch (e) {
      error = '$e';
      rethrow;
    } finally {
      installing = false;
      changed();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _timer?.cancel();
    _client.close(force: true);
    super.dispose();
  }
}
