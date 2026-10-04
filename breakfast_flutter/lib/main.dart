import 'dart:io';
import 'dart:convert';

import 'package:flutter/material.dart';

import 'controller.dart';
import 'services/store.dart';
import 'services/native.dart';
import 'services/printing.dart';
import 'model.dart';
import 'ui/home.dart';
import 'ui/expressive_theme.dart';

void main(List<String> args) async {
  WidgetsFlutterBinding.ensureInitialized();
  final smoke = args.where((a) => a.startsWith('--smoke-test=')).firstOrNull;
  if (smoke != null) {
    final target = File(smoke.substring(13));
    try {
      final protected = await Native.encrypt('breakfast-native-test');
      if (await Native.decrypt(protected) != 'breakfast-native-test') {
        throw StateError('Credential round trip failed');
      }
      final data = emptyData();
      data['orders'] = [
        {
          'id': 'smoke',
          'room': '8',
          'slot': slots.first,
          'comment': 'Native smoke test',
          'lines': [],
        },
      ];
      final print = await Printing.prepare(data, 'orders', {});
      await target.writeAsString(
        jsonEncode({
          'ok': true,
          'dpapiRoundTrip': true,
          'printFile': print.path,
        }),
      );
      exit(0);
    } catch (e) {
      await target.writeAsString(jsonEncode({'ok': false, 'error': '$e'}));
      exit(1);
    }
  }
  try {
    final profile = args
        .where((a) => a.startsWith('--profile='))
        .firstOrNull
        ?.substring(10);
    final app = AppController(Store.open(profile: profile));
    runApp(BreakfastApp(app));
    app.email.start();
    app.updates.start();
  } catch (error) {
    runApp(
      MaterialApp(
        theme: breakfastTheme(),
        home: Scaffold(
          body: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 600),
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.error_outline, size: 48),
                    const SizedBox(height: 20),
                    const Text(
                      'Breakfast Orders could not open',
                      style: TextStyle(fontSize: 24),
                    ),
                    const SizedBox(height: 16),
                    SelectableText('$error'),
                    const SizedBox(height: 16),
                    const Text(
                      'Your original data has not been changed. Close another open instance or restore the affected profile backup, then restart.',
                    ),
                    const SizedBox(height: 20),
                    FilledButton(
                      onPressed: () => exit(1),
                      child: const Text('Close'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class BreakfastApp extends StatelessWidget {
  const BreakfastApp(this.app, {super.key});
  final AppController app;
  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: app,
    builder: (context, _) => MaterialApp(
      title: 'Breakfast Orders',
      debugShowCheckedModeBanner: false,
      theme: breakfastTheme(),
      darkTheme: breakfastTheme(brightness: Brightness.dark),
      themeMode: app.darkMode ? ThemeMode.dark : ThemeMode.light,
      builder: (context, child) => Theme(
        data: breakfastTheme(
          reduceMotion: MediaQuery.disableAnimationsOf(context),
          brightness: Theme.of(context).brightness,
        ),
        child: child!,
      ),
      home: HomePage(app),
    ),
  );
}
