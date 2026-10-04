import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import 'model.dart';
import 'services/email_service.dart';
import 'services/native.dart';
import 'services/store.dart';
import 'services/updates.dart';

class AppController extends ChangeNotifier {
  AppController(this.store) {
    data = store.loadOrders();
    _appearance = store.read('appearance-settings.json', {});
    if (data['sortUiVersion'] != 2) {
      data['viewSort'] = 'room';
      data['sortUiVersion'] = 2;
      store.saveOrders(data);
    }
    email = EmailService(store, readOrders: () => data, writeOrders: commit);
    email.addListener(notifyListeners);
    updates.addListener(notifyListeners);
  }
  final Store store;
  final Updates updates = Updates();
  late Json data;
  late EmailService email;
  Json settingsDraft = {};
  late Json _appearance;
  bool get darkMode => _appearance['darkMode'] == true;
  void setDarkMode(bool enabled) {
    final next = {..._appearance, 'darkMode': enabled};
    store.write('appearance-settings.json', next);
    _appearance = next;
    notifyListeners();
  }

  void commit(Json next) {
    store.saveOrders(next);
    data = next;
    notifyListeners();
  }

  void edit(void Function(Json) change) {
    final next = clone(data);
    change(next);
    commit(next);
  }

  Future<void> backup() async {
    final path = await Native.chooseFile(save: true);
    if (path == null) return;
    await File(path).writeAsString(
      const JsonEncoder.withIndent('  ').convert({
        'format': 'breakfast-orders-backup',
        'version': 1,
        'exportedAt': DateTime.now().toUtc().toIso8601String(),
        'data': data,
      }),
      flush: true,
    );
  }

  Future<Json?> chooseRestore() async {
    final path = await Native.chooseFile();
    if (path == null) return null;
    final value = jsonDecode(await File(path).readAsString());
    return validateData(
      value is Json && value['format'] == 'breakfast-orders-backup'
          ? value['data']
          : value,
    );
  }

  @override
  void dispose() {
    email.removeListener(notifyListeners);
    email.dispose();
    updates.removeListener(notifyListeners);
    updates.dispose();
    store.close();
    super.dispose();
  }
}
