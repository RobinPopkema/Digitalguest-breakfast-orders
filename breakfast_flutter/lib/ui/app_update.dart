import 'package:flutter/material.dart';

import '../controller.dart';
import 'common.dart';

Future<void> installAppUpdate(
  BuildContext context,
  AppController app, {
  bool Function()? beforeInstall,
}) async {
  final release = app.updates.available;
  if (release == null || app.updates.installing) return;
  if (!await confirm(
    context,
    'Update to ${release['version']}?',
    'The app will download the update and restart. Your orders and settings are kept.\n\n${release['notes']}',
    action: 'Update and restart',
  )) {
    return;
  }
  if (!context.mounted || (beforeInstall != null && !beforeInstall())) return;
  showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (_) => PopScope(
      canPop: false,
      child: AlertDialog(
        title: const Text('Installing update'),
        content: ListenableBuilder(
          listenable: app.updates,
          builder: (_, _) => Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              LinearProgressIndicator(
                value: app.updates.progress > 0 && app.updates.progress < 1
                    ? app.updates.progress
                    : null,
              ),
              const SizedBox(height: 16),
              Text(
                app.updates.progress < 1
                    ? 'Downloading update…'
                    : 'Verifying and preparing restart…',
              ),
              const SizedBox(height: 8),
              const Text('Your saved orders and settings will be kept.'),
            ],
          ),
        ),
      ),
    ),
  );
  Object? failure;
  try {
    await app.updates.install(app.store.directory.path);
  } catch (error) {
    failure = error;
  } finally {
    if (context.mounted) Navigator.of(context).pop();
  }
  if (failure != null && context.mounted) showError(context, failure);
}
