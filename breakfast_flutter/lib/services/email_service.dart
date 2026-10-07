import 'dart:async';
import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';

import '../model.dart';
import 'email_parser.dart';
import 'mail_transport.dart';
import 'native.dart';
import 'store.dart';

class EmailService extends ChangeNotifier {
  EmailService(
    this.store, {
    required this.readOrders,
    required this.writeOrders,
    MailTransport Function()? transport,
    DateTime Function()? now,
    Future<String> Function(String)? encrypt,
    Future<String> Function(String)? decrypt,
  }) : transport = transport ?? ImapTransport.new,
       now = now ?? DateTime.now,
       encrypt = encrypt ?? Native.encrypt,
       decrypt = decrypt ?? Native.decrypt {
    config = store.read('email-settings.json', {});
    imports = store.read('email-imports.json', {
      'seen': <String, dynamic>{},
      'queue': <Json>[],
      'aliases': <String, dynamic>{},
    });
    if (imports['queue'] is! List ||
        imports['seen'] is! Json ||
        imports['aliases'] is! Json) {
      throw const FormatException(
        'Email import data is invalid. Restore its backup before continuing.',
      );
    }
  }
  final Store store;
  final Json Function() readOrders;
  final void Function(Json) writeOrders;
  final MailTransport Function() transport;
  final DateTime Function() now;
  final Future<String> Function(String) encrypt, decrypt;
  late Json config, imports;
  bool busy = false, error = false;
  String message = 'Email monitoring is off';
  DateTime? lastChecked;
  DateTime? nextAutomaticCheck;
  Duration? get automaticCheckRemaining =>
      nextAutomaticCheck?.difference(now());
  Timer? _timer;
  List<Json> get queue => rows(imports['queue']);
  bool get configured => config['flutterSecret'] is String;
  int get interval =>
      (config['intervalMinutes'] is int &&
          config['intervalMinutes'] >= 1 &&
          config['intervalMinutes'] <= 1440)
      ? config['intervalMinutes']
      : 1;
  void start({bool checkImmediately = true}) {
    _timer?.cancel();
    nextAutomaticCheck = null;
    if (config['enabled'] == true && configured) {
      final started = now(), period = Duration(minutes: interval);
      nextAutomaticCheck = started.add(period);
      _timer = Timer.periodic(period, (timer) {
        nextAutomaticCheck = started.add(period * (timer.tick + 1));
        notifyListeners();
        unawaited(check());
      });
      if (checkImmediately) unawaited(check());
    }
    notifyListeners();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<Json> settings(Json input, {bool needsFolder = true}) async {
    final host = '${input['host'] ?? ''}'.trim(),
        user = '${input['user'] ?? ''}'.trim(),
        folder = '${input['folder'] ?? ''}'.trim();
    final port = int.tryParse('${input['port'] ?? 993}'),
        minutes = int.tryParse('${input['intervalMinutes'] ?? 1}');
    if (host.isEmpty ||
        host.length > 253 ||
        RegExp(r'[\s/:\\]').hasMatch(host)) {
      throw const FormatException('Enter a valid IMAP server hostname.');
    }
    if (port == null || port < 1 || port > 65535) {
      throw const FormatException('TLS port must be from 1 to 65535.');
    }
    if (user.isEmpty) {
      throw const FormatException('Enter the email account / username.');
    }
    if (needsFolder && folder.isEmpty) {
      throw const FormatException('Choose a folder to watch.');
    }
    if (minutes == null || minutes < 1 || minutes > 1440) {
      throw const FormatException(
        'Check interval must be from 1 to 1440 minutes.',
      );
    }
    final sender = normalize(input['sender'] ?? defaultSender);
    if (!RegExp(r'^[^\s@"\\]+@[^\s@"\\]+\.[^\s@"\\]+$').hasMatch(sender)) {
      throw const FormatException('Enter the exact sender email address.');
    }
    String? secret =
        host.toLowerCase() == '${config['host']}'.toLowerCase() &&
            user == config['user']
        ? config['flutterSecret']
        : null;
    if ('${input['password'] ?? ''}'.isNotEmpty) {
      secret = await encrypt(input['password']);
    }
    if (secret == null) {
      throw const FormatException('Enter your mail password or app password.');
    }
    return {
      'host': host,
      'port': port,
      'user': user,
      'folder': folder,
      'intervalMinutes': minutes,
      'sender': sender,
      'enabled': input['enabled'] == true,
      'flutterSecret': secret,
    };
  }

  Future<T> withClient<T>(
    Json cfg,
    Future<T> Function(MailTransport) action,
  ) async {
    final client = transport();
    try {
      final password = await decrypt(cfg['flutterSecret']);
      try {
        await client.connect(cfg, password);
      } catch (_) {
        throw StateError(
          'Could not connect or sign in. Check the server, TLS port, username, password and internet connection.',
        );
      }
      return await action(client);
    } finally {
      try {
        await client.close();
      } catch (_) {
        /* Preserve the operation error. */
      }
    }
  }

  Future<List<String>> folders(Json input) async =>
      withClient(await settings(input, needsFolder: false), (c) => c.folders());
  Future<void> saveSettings(Json input) async {
    if (busy) throw StateError('Wait for the current check to finish.');
    busy = true;
    notifyListeners();
    try {
      final next = await settings(input);
      await withClient(next, (c) => c.examine(next['folder']));
      store.write('email-settings.json', next);
      config = next;
      message =
          'Connected. ${config['enabled'] == true ? 'Automatic checks enabled.' : 'Automatic checks paused.'}';
      error = false;
    } finally {
      busy = false;
      notifyListeners();
    }
    start();
  }

  void pause() {
    final next = {...config, 'enabled': false};
    store.write('email-settings.json', next);
    config = next;
    _timer?.cancel();
    nextAutomaticCheck = null;
    message = 'Automatic email checks are paused.';
    notifyListeners();
  }

  String get account => sha256
      .convert(
        utf8.encode('${config['host'].toLowerCase()}\u0000${config['user']}'),
      )
      .toString();
  Future<void> check({bool resetTimer = false}) async {
    if (busy) return;
    if (!configured) throw StateError('Configure your email account first.');
    if (resetTimer) start(checkImmediately: false);
    busy = true;
    message = 'Checking the selected folder…';
    notifyListeners();
    var imported = 0, ignored = 0;
    try {
      await withClient(config, (client) async {
        final box = await client.examine(config['folder']);
        final base = '$account:${config['folder']}:${box['uidValidity']}:';
        final today = now(),
            start = DateTime(now().year, now().month, now().day),
            end = DateTime(now().year, now().month, now().day + 1);
        String date(DateTime d) =>
            '${d.day}-${['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'][d.month - 1]}-${d.year}';
        final dates =
            'SINCE ${date(DateTime(today.year, today.month, today.day - 1))} BEFORE ${date(DateTime(today.year, today.month, today.day + 2))}';
        List<int>? ids = [];
        if (box['exists'] != 0) {
          try {
            ids = await client.search('$dates FROM "${config['sender']}"');
          } catch (_) {
            try {
              ids = await client.search(dates);
            } catch (_) {
              ids = null;
            }
          }
        }
        final metadata = await client.metadata(
          ids?.where((id) => imports['seen']['$base$id'] != true).toList(),
        );
        if (ids == null && metadata.isEmpty && box['exists'] != 0) {
          throw StateError(
            'Could not read message dates from the selected folder.',
          );
        }
        final messages = metadata.where((m) {
          final received = receiptDate(m.internalDate);
          return m.uid != null &&
              imports['seen']['$base${m.uid}'] != true &&
              received != null &&
              !received.isBefore(start) &&
              received.isBefore(end);
        }).toList();
        for (final meta in messages.take(100)) {
          if (queue.length >= 1000) {
            throw StateError(
              'The review queue is full. Review or dismiss imports first.',
            );
          }
          if ((meta.size ?? 0) > 2 * 1024 * 1024) {
            throw StateError('Email UID ${meta.uid} is larger than 2 MB.');
          }
          final full = await client.body(meta.uid!);
          if (full == null) continue;
          final parsed = parseMessage(full, config['sender']);
          final key =
              '$account:message:${parsed['requestId'] ?? parsed['messageId'] ?? sha256.convert(utf8.encode(full.renderMessage()))}';
          final next = clone(imports);
          next['seen']['$base${meta.uid}'] = true;
          if (next['seen'][key] != true) {
            next['seen'][key] = true;
            if (parsed['kind'] == 'ignore') {
              ignored++;
            } else {
              next['queue'].add({
                ...parsed,
                'id': newId(),
                'key': key,
                'importedAt': now().toUtc().toIso8601String(),
                'receivedAt': receiptDate(meta.internalDate)!
                    .toUtc()
                    .toIso8601String(),
                'folder': config['folder'],
              });
              imported++;
            }
          }
          store.write('email-imports.json', next);
          imports = next;
        }
        message =
            '$imported new orders awaiting review; $ignored dinner/other emails ignored.${ids == null ? ' Compatibility folder scan used.' : ''}${messages.length > 100 ? ' More emails will be checked next time.' : ''}';
      });
      lastChecked = now();
      error = false;
    } catch (e) {
      error = true;
      message = 'Email check failed: $e';
    } finally {
      busy = false;
      notifyListeners();
    }
  }

  List<String> matches(Json entry) {
    final data = readOrders();
    final categories = indexById(data['categories']);
    final eligible = rows(data['items'])
        .where((item) => categories.containsKey(item['categoryId']))
        .toList();
    final byId = indexById(eligible);
    final byName = <String, List<Json>>{};
    for (final item in eligible) {
      (byName[normalize(item['name'])] ??= []).add(item);
    }
    return rows(entry['lines']).map((line) {
      final name = normalize(line['name']);
      final aliased = byId[imports['aliases'][name]];
      if (aliased != null) {
        return itemAvailable(aliased) ? aliased['id'] as String : '';
      }
      final found = byName[name];
      return found != null && found.length == 1 && itemAvailable(found.single)
          ? found.single['id'] as String
          : '';
    }).toList();
  }

  bool quickReady(Json entry, {List<String>? matchedIds}) {
    final ids = matchedIds ?? matches(entry);
    return entry['kind'] == 'breakfast' &&
        slots.contains(entry['slot']) &&
        ids.isNotEmpty &&
        ids.every((id) => id.isNotEmpty);
  }

  String? matchingCabin(Json entry) {
    final room = guestCabin(entry).toLowerCase();
    if (room.isEmpty) return null;
    final matches = rows(readOrders()['safeCabins'])
        .where((c) => '${c['name']}'.trim().toLowerCase() == room)
        .toList();
    return matches.length == 1 ? matches.single['id'] as String : null;
  }

  void dismiss(String id) {
    final next = clone(imports);
    next['queue'].removeWhere((e) => e['id'] == id);
    store.write('email-imports.json', next);
    imports = next;
    notifyListeners();
  }

  void accept(Json input) {
    final entry = queue.where((q) => q['id'] == input['id']).firstOrNull;
    if (entry == null) throw StateError('This email was already reviewed.');
    final data = clone(readOrders());
    if (rows(data['orders']).any((o) => orderHasEmailKey(o, entry['key']))) {
      dismiss(entry['id']);
      return;
    }
    final cabin = findById(data['safeCabins'], input['safeCabinId']);
    if (cabin == null) {
      throw StateError('Select a cabin before confirming.');
    }
    if (input['mode'] == 'quick') {
      if (!quickReady(entry)) throw StateError('This order needs revision.');
      final ids = matches(entry);
      input = {
        ...input,
        'slot': entry['slot'],
        'comment': entry['comment'],
        'lines': List.generate(
          ids.length,
          (i) => {
            'sourceIndex': i,
            'itemId': ids[i],
            'qty': entry['lines'][i]['qty'],
          },
        ),
      };
    }
    if (input['confirmed'] != true || !slots.contains(input['slot'])) {
      throw StateError('Confirm this is breakfast and choose a delivery time.');
    }
    if (input['lines'] is! List ||
        input['lines'].isEmpty ||
        input['lines'].length > 500) {
      throw StateError('Select at least one menu item.');
    }
    final lines = <Json>[],
        aliases = Map<String, dynamic>.from(imports['aliases']);
    for (final selected in rows(input['lines'])) {
      final item = findById(data['items'], selected['itemId']),
          category = findById(data['categories'], item?['categoryId']);
      final qty = selected['qty'];
      if (item != null && !itemAvailable(item)) {
        throw StateError(
          'This item is unavailable. Select an available replacement.',
        );
      }
      if (item == null ||
          category == null ||
          qty is! int ||
          qty < 1 ||
          qty > 10000) {
        throw StateError(
          'Map every item and use a positive whole quantity up to 10000.',
        );
      }
      final line = lines.where((l) => l['itemId'] == item['id']).firstOrNull;
      if (line == null) {
        lines.add(lineFor(item, category, qty));
      } else {
        line['qty'] += qty;
      }
      final index = selected['sourceIndex'];
      if (index is int && index >= 0 && index < entry['lines'].length) {
        final sourceName = normalize(entry['lines'][index]['name']);
        final temporaryReplacement = rows(data['items']).any(
          (candidate) =>
              !itemAvailable(candidate) &&
              (normalize(candidate['name']) == sourceName ||
                  candidate['id'] == aliases[sourceName]),
        );
        if (!temporaryReplacement) aliases[sourceName] = item['id'];
      }
    }
    var comment = '${input['comment'] ?? ''}'.trim();
    if (comment.length > 10000) comment = comment.substring(0, 10000);
    data['orders'].add({
      'id': newId(),
      'room': cabin['name'],
      'slot': input['slot'],
      'comment': comment,
      'lines': lines,
      'safeCabinId': cabin['id'],
      'guest': guestDetails(entry),
      'emailSource': {
        if (entry['html'] is String) 'html': entry['html'],
        if (entry['text'] is String) 'text': entry['text'],
        'guestCabin': guestCabin(entry),
        'key': entry['key'],
        'receivedAt': entry['receivedAt'],
        'reviewedAt': now().toUtc().toIso8601String(),
      },
    });
    writeOrders(data); // Save first: retry after an interrupted queue write cannot duplicate it.
    final next = clone(imports);
    next['queue'].removeWhere((e) => e['id'] == entry['id']);
    next['aliases'] = aliases;
    store.write('email-imports.json', next);
    imports = next;
    notifyListeners();
  }
}
