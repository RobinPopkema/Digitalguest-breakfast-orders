import 'dart:convert';
import 'dart:io';
import 'dart:ffi';

import 'package:ffi/ffi.dart';

import '../model.dart';

// ReplaceFile semantics on Windows: readers see either the old or new whole file.
void replaceFile(String source, String target) {
  if (!Platform.isWindows) {
    File(source).renameSync(target);
    return;
  }
  final move = DynamicLibrary.open('kernel32.dll')
      .lookupFunction<
        Int32 Function(Pointer<Utf16>, Pointer<Utf16>, Uint32),
        int Function(Pointer<Utf16>, Pointer<Utf16>, int)
      >('MoveFileExW');
  final a = source.toNativeUtf16(), b = target.toNativeUtf16();
  try {
    if (move(a, b, 0x1 | 0x8) == 0) {
      throw FileSystemException('Could not atomically replace file', target);
    }
  } finally {
    calloc.free(a);
    calloc.free(b);
  }
}

class Store {
  Store(this.directory);
  final Directory directory;
  RandomAccessFile? _lock;
  String? migrationNotice;
  static Store open({String? profile, String? importFrom}) {
    final roaming = Platform.environment['APPDATA'];
    if (profile == null && roaming == null) {
      throw StateError('Windows profile directory is unavailable.');
    }
    final store = Store(
      Directory(profile ?? '$roaming/Breakfast Orders Flutter'),
    );
    store.directory.createSync(recursive: true);
    store._lock = File('${store.directory.path}/.profile.lock')
        .openSync(mode: FileMode.append);
    try {
      store._lock!.lockSync(FileLock.exclusive);
    } catch (_) {
      store._lock!.closeSync();
      throw StateError('This data profile is already open in another window.');
    }
    if ((profile == null || importFrom != null) &&
        !store.file('migration-complete.json').existsSync()) {
      final legacy = Store(
        Directory(importFrom ?? '$roaming/Breakfast Orders'),
      );
      // Copy, never move or modify, the old profile. Credentials require re-entry.
      for (final name in [
        'breakfast-orders.json',
        'email-imports.json',
        'email-settings.json',
      ]) {
        if (!store.file(name).existsSync() && legacy.file(name).existsSync()) {
          final data = legacy.read(
            name,
            {},
            validator: name == 'breakfast-orders.json' ? validateData : null,
          );
          if (name == 'email-settings.json') {
            data.remove('secret');
            data.remove('flutterSecret');
            data['enabled'] = false;
          }
          store.write(name, data);
          store.migrationNotice = 'Your existing orders and email review history were copied. The original app data is unchanged. Re-enter your email password to resume checks.';
        }
      }
      store.write('migration-complete.json', {
        'completedAt': DateTime.now().toUtc().toIso8601String(),
      });
    }
    return store;
  }

  File file(String name) => File('${directory.path}/$name');
  Json read(String name, Json fallback, {Json Function(dynamic)? validator}) {
    if (!file(name).existsSync()) return clone(fallback);
    Json decode(File f) {
      final data = jsonDecode(f.readAsStringSync());
      return validator != null ? validator(data) : data as Json;
    }

    try {
      return decode(file(name));
    } catch (_) {
      if (file('$name.bak').existsSync()) return decode(file('$name.bak'));
      rethrow;
    }
  }

  void write(
    String name,
    Json data, {
    bool daily = false,
    Json Function(dynamic)? validator,
  }) {
    validator?.call(data);
    directory.createSync(recursive: true);
    final current = file(name), temp = file('$name.tmp');
    temp.writeAsStringSync(jsonEncode(data), flush: true);
    if (current.existsSync()) {
      var valid = false;
      try {
        final old = jsonDecode(current.readAsStringSync());
        validator?.call(old);
        valid = true;
      } catch (_) {
        /* Keep the last valid backup. */
      }
      if (valid) {
        current.copySync('${current.path}.bak');
        if (daily) {
          final backups = Directory('${directory.path}/backups')
            ..createSync(recursive: true);
          final day = DateTime.now().toUtc().toIso8601String().substring(0, 10);
          final target = File('${backups.path}/$day.json');
          if (!target.existsSync()) current.copySync(target.path);
          final entries =
              backups
                  .listSync()
                  .whereType<File>()
                  .where(
                    (f) => RegExp(r'\d{4}-\d{2}-\d{2}\.json$').hasMatch(f.path),
                  )
                  .toList()
                ..sort((a, b) => a.path.compareTo(b.path));
          for (final old in entries.take(
            entries.length > 30 ? entries.length - 30 : 0,
          )) {
            old.deleteSync();
          }
        }
      }
    }
    replaceFile(temp.path, current.path);
  }

  Json loadOrders() =>
      read('breakfast-orders.json', emptyData(), validator: validateData);
  void saveOrders(Json data) => write(
    'breakfast-orders.json',
    data,
    daily: true,
    validator: validateData,
  );
  void close() {
    _lock?.unlockSync();
    _lock?.closeSync();
    _lock = null;
  }
}
