import 'dart:io';

// Shared browser preference and launch behavior for local print/email previews.
Future<void> openPreview(File file, {required String purpose}) async {
  final roots = [
    'ProgramFiles',
    'ProgramFiles(x86)',
    'LOCALAPPDATA',
  ].map((name) => Platform.environment[name]).whereType<String>().toList();
  for (final browser in [
    'Microsoft/Edge/Application/msedge.exe',
    'Google/Chrome/Application/chrome.exe',
    'Mozilla Firefox/firefox.exe',
  ]) {
    for (final root in roots) {
      final executable = File('$root/$browser');
      if (!executable.existsSync()) continue;
      await Process.start(executable.path, [
        browser.endsWith('firefox.exe') ? '-new-window' : '--new-window',
        file.uri.toString(),
      ], mode: ProcessStartMode.detached);
      return;
    }
  }
  throw StateError('Install Microsoft Edge, Chrome or Firefox to $purpose.');
}
