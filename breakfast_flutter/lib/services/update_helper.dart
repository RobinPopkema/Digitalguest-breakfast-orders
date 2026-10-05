import 'dart:async';
import 'dart:io';

// Normal mode is intentional: Windows PowerShell can silently exit when Dart
// starts it detached. The child keeps running after this process exits.
Future<Process> launchUpdateHelper(
  File helper,
  File config,
  Directory work,
) async {
  final process = await Process.start(
    '${Platform.environment['SystemRoot']}/System32/WindowsPowerShell/v1.0/powershell.exe',
    [
      '-NoProfile',
      '-NonInteractive',
      '-WindowStyle',
      'Hidden',
      '-ExecutionPolicy',
      'Bypass',
      '-File',
      helper.path,
      '-Config',
      config.path,
    ],
    mode: ProcessStartMode.normal,
    // Never inherit the install directory: Windows holds a directory handle
    // for a process's working directory, preventing the folder swap.
    workingDirectory: work.path,
  );
  unawaited(process.stdout.pipe(File('${work.path}/stdout.log').openWrite()));
  unawaited(process.stderr.pipe(File('${work.path}/stderr.log').openWrite()));
  return process;
}
