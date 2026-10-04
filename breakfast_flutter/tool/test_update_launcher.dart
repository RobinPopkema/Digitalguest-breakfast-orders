import 'dart:io';

import 'package:breakfast_orders/services/update_helper.dart';

Future<void> main(List<String> args) async {
  if (!Platform.isWindows) return;
  if (args.isNotEmpty) {
    final work = Directory(args.first);
    await launchUpdateHelper(
      File('${work.path}/probe.ps1'),
      File('${work.path}/config.json'),
      work,
    );
    for (var i = 0; i < 100; i++) {
      if (File('${work.path}/ready').existsSync()) exit(0);
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
    exit(1);
  }
  final work = Directory.systemTemp.createTempSync(
    'breakfast-helper-launch-test-',
  );
  File('${work.path}/config.json').writeAsStringSync('{}');
  File('${work.path}/probe.ps1').writeAsStringSync(r'''
param([string]$Config)
$work=Split-Path -Parent $Config
'ready' | Set-Content -LiteralPath (Join-Path $work 'ready')
Start-Sleep -Seconds 2
'survived' | Set-Content -LiteralPath (Join-Path $work 'survived')
''');
  final parent = await Process.run(Platform.resolvedExecutable, [
    Platform.script.toFilePath(),
    work.path,
  ]);
  if (parent.exitCode != 0) {
    throw StateError('Helper did not start: ${parent.stderr}');
  }
  for (var i = 0; i < 100 && !File('${work.path}/survived').existsSync(); i++) {
    await Future<void>.delayed(const Duration(milliseconds: 100));
  }
  if (!File('${work.path}/survived').existsSync()) {
    throw StateError('Helper did not survive parent exit.');
  }
  stdout.writeln('Windows update helper starts and survives application exit.');
}
