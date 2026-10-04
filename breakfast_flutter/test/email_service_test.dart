import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:enough_mail/enough_mail.dart';
import 'package:breakfast_orders/model.dart';
import 'package:breakfast_orders/services/email_service.dart';
import 'package:breakfast_orders/services/mail_transport.dart';
import 'package:breakfast_orders/services/store.dart';

import 'fixtures.dart';

class FakeMail implements MailTransport {
  final messages = <MimeMessage>[];
  final fetched = <int>[], criteria = <String>[];
  int rejectSearch = 0;
  bool rejectMetadata = false;
  void add(int uid, String text, String date) {
    final message = MimeMessage.parseFromText(text)
      ..uid = uid
      ..internalDate = date
      ..size = text.length;
    messages.add(message);
  }

  @override
  Future<void> connect(Json config, String password) async {
    expectSync(config['port'], 993);
    expectSync(password, 'test-password');
  }

  @override
  Future<List<String>> folders() async => ['INBOX/DIGITAL GUEST'];
  @override
  Future<Json> examine(String folder) async {
    expectSync(folder, 'INBOX/DIGITAL GUEST');
    return {'uidValidity': 10, 'exists': messages.length};
  }

  @override
  Future<List<int>> search(String c) async {
    criteria.add(c);
    if (rejectSearch-- > 0) throw StateError('SEARCH rejected');
    return messages.map((m) => m.uid!).toList();
  }

  @override
  Future<List<MimeMessage>> metadata(List<int>? ids) async {
    if (rejectMetadata) throw StateError('Metadata access rejected');
    return messages.where((m) => ids == null || ids.contains(m.uid)).toList();
  }

  @override
  Future<MimeMessage?> body(int uid) async {
    fetched.add(uid);
    return messages.where((m) => m.uid == uid).firstOrNull;
  }

  @override
  Future<void> close() async {}
}

void main() {
  late Directory dir;
  late Store store;
  late FakeMail mail;
  late Json data;
  late EmailService service;
  late DateTime clock;
  final input = <String, dynamic>{
    'host': 'imap.example.com',
    'port': 993,
    'user': 'orders@example.com',
    'password': 'test-password',
    'folder': 'INBOX/DIGITAL GUEST',
    'intervalMinutes': 5,
    'enabled': false,
  };
  EmailService create() => EmailService(
    store,
    readOrders: () => data,
    writeOrders: (next) => data = next,
    transport: () => mail,
    now: () => clock,
    encrypt: (s) async => 'protected:$s',
    decrypt: (s) async => s.substring(10),
  );
  setUp(() {
    dir = Directory.systemTemp.createTempSync('breakfast-email-');
    store = Store(dir);
    mail = FakeMail();
    data = fixture();
    clock = DateTime(2026, 10, 1, 12);
    mail.add(1, source(), '01-Oct-2026 08:00:00 +0000');
    mail.add(
      2,
      source(time: '18:00 - 18:30', id: 'dinner'),
      '01-Oct-2026 08:00:00 +0000',
    );
    mail.add(3, source(), '01-Oct-2026 08:00:00 +0000');
    service = create();
  });
  tearDown(() {
    service.dispose();
    dir.deleteSync(recursive: true);
  });
  test('Indexed matching retains ambiguity and unavailable alias rules', () {
    data = clone(data);
    data['items'].add({
      'id': 'other',
      'name': 'CROISSANT',
      'categoryId': 'bakery',
    });
    final entry = <String, dynamic>{
      'lines': [
        {'name': 'Croissant', 'qty': 1},
      ],
    };
    expect(service.matches(entry), ['']);
    service.imports['aliases']['croissant'] = 'croissant';
    expect(service.matches(entry), ['croissant']);
    data['items'][0]['available'] = false;
    expect(service.matches(entry), ['']);
    data['items'][0]['categoryId'] = 'removed';
    expect(service.matches(entry), ['other']);
  });

  test(
    'Unavailable items require replacement without learning a temporary alias',
    () async {
      await service.saveSettings(input);
      await service.check();
      final entry = service.queue.first;
      expect(service.quickReady(entry), isTrue);
      data = clone(data);
      data['items'][0]['available'] = false;
      expect(service.matches(entry), ['', 'butter']);
      expect(service.quickReady(entry), isFalse);
      final review = <String, dynamic>{
        'id': entry['id'],
        'safeCabinId': '8',
        'confirmed': true,
        'slot': entry['slot'],
        'lines': [
          {'sourceIndex': 0, 'itemId': 'croissant', 'qty': 2},
          {'sourceIndex': 1, 'itemId': 'butter', 'qty': 1},
        ],
      };
      expect(() => service.accept(review), throwsStateError);
      expect(service.queue.length, 1);
      review['lines'][0]['itemId'] = 'butter';
      service.accept(review);
      expect(data['orders'][0]['lines'][0]['qty'], 3);
      expect(service.imports['aliases']['croissant'], isNull);
      data['items'][0]['available'] = true;
      expect(service.matches(entry), ['croissant', 'butter']);
    },
  );

  test(
    'Checks deduplicate, exclude dinner and persist pending imports',
    () async {
      await service.saveSettings(input);
      await service.check();
      expect(service.error, false);
      expect(service.queue.length, 1);
      expect(data['orders'], isEmpty);
      service.dispose();
      service = create();
      await service.check();
      expect(service.queue.length, 1);
      expect(mail.fetched, [1, 2, 3]);
      service.dismiss(service.queue.first['id']);
      await service.check();
      expect(service.queue, isEmpty);
    },
  );
  test(
    'Only local-today receipts download bodies, with midnight rollover',
    () async {
      mail.messages.clear();
      mail.add(10, source(id: 'old'), '30-Sep-2026 00:00:00 +0000');
      mail.add(11, source(id: 'today'), '01-Oct-2026 08:00:00 +0000');
      mail.add(12, source(id: 'tomorrow'), '02-Oct-2026 08:00:00 +0000');
      await service.saveSettings(input);
      await service.check();
      expect(mail.fetched, [11]);
      clock = DateTime(2026, 10, 2, 12);
      await service.check();
      expect(mail.fetched, [11, 12]);
      expect(service.queue.length, 2);
    },
  );
  test(
    'Rejected SEARCH retries dates then compatibility metadata scan',
    () async {
      mail.rejectSearch = 2;
      await service.saveSettings(input);
      await service.check();
      expect(service.error, false);
      expect(mail.criteria.length, 2);
      expect(mail.criteria[0], contains('FROM'));
      expect(mail.criteria[1], isNot(contains('FROM')));
      expect(service.message, contains('Compatibility'));
      expect(service.queue.length, 1);
    },
  );
  test('Rejected metadata does not mutate duplicate tracking', () async {
    mail.rejectSearch = 2;
    mail.rejectMetadata = true;
    await service.saveSettings(input);
    await service.check();
    expect(service.error, true);
    expect(service.message, contains('Metadata access rejected'));
    expect(service.imports['seen'], isEmpty);
  });
  test('Empty mailbox succeeds without search', () async {
    mail.messages.clear();
    await service.saveSettings(input);
    await service.check();
    expect(service.error, false);
    expect(mail.criteria, isEmpty);
  });
  test('Quick approval revalidates safe cabin and mappings', () async {
    await service.saveSettings(input);
    await service.check();
    final entry = service.queue.first;
    expect(
      () => service.accept({
        'id': entry['id'],
        'safeCabinId': 'missing',
        'mode': 'quick',
        'confirmed': true,
      }),
      throwsStateError,
    );
    service.accept({
      'id': entry['id'],
      'safeCabinId': '9',
      'mode': 'quick',
      'confirmed': true,
    });
    expect(data['orders'][0]['room'], '9');
    expect(data['orders'][0]['emailSource']['guestCabin'], '8');
    expect(data['orders'][0]['lines'][0]['qty'], 2);
    expect(data['rooms'], ['old untrusted cabin']);
    expect(service.queue, isEmpty);
  });
  test(
    'Unmatched items cannot be accepted quickly; revision learns aliases',
    () async {
      await service.saveSettings(input);
      await service.check();
      final entry = service.queue.first;
      entry['lines'][0]['name'] = 'Pastry';
      expect(service.quickReady(entry), false);
      expect(
        () => service.accept({
          'id': entry['id'],
          'safeCabinId': '9',
          'mode': 'quick',
          'confirmed': true,
        }),
        throwsStateError,
      );
      service.accept({
        'id': entry['id'],
        'safeCabinId': '9',
        'slot': slots[2],
        'confirmed': true,
        'lines': [
          {'itemId': 'croissant', 'qty': 3, 'sourceIndex': 0},
        ],
      });
      expect(service.imports['aliases']['pastry'], 'croissant');
      expect(data['orders'][0]['lines'][0]['qty'], 3);
    },
  );
  test('Interrupted acceptance retry does not create another order', () async {
    await service.saveSettings(input);
    await service.check();
    final entry = clone(service.queue.first);
    service.accept({
      'id': entry['id'],
      'safeCabinId': '9',
      'mode': 'quick',
      'confirmed': true,
    });
    service.imports['queue'].add(entry);
    service.accept({
      'id': entry['id'],
      'safeCabinId': '9',
      'mode': 'quick',
      'confirmed': true,
    });
    expect(data['orders'].length, 1);
    expect(service.queue, isEmpty);
  });
  test(
    'Credential/account/interval validation and protected storage',
    () async {
      await service.saveSettings(input);
      expect(
        store.file('email-settings.json').readAsStringSync(),
        isNot(contains('"password"')),
      );
      expect(
        () => service.settings({...input, 'password': '', 'user': 'other'}),
        throwsFormatException,
      );
      expect(
        () => service.settings({...input, 'intervalMinutes': 0}),
        throwsFormatException,
      );
      expect(
        () => service.settings({...input, 'host': 'https://invalid'}),
        throwsFormatException,
      );
      expect(await service.folders({...input, 'folder': ''}), [
        'INBOX/DIGITAL GUEST',
      ]);
    },
  );
  test('Receipt timezone is converted to the actual instant', () {
    expect(
      receiptDate('01-Oct-2026 00:30:00 +0200'),
      DateTime.utc(2026, 9, 30, 22, 30),
    );
  });
  testWidgets(
    'Countdown follows the scheduled timer, manual checks and pause',
    (tester) async {
      await service.saveSettings(input);
      expect(service.nextAutomaticCheck, isNull);
      service.config['enabled'] = true;
      service.start();
      await tester.pump();
      final due = clock.add(const Duration(minutes: 5));
      expect(service.nextAutomaticCheck, due);
      clock = clock.add(const Duration(minutes: 2));
      await tester.pump(const Duration(minutes: 2));
      expect(service.automaticCheckRemaining, const Duration(minutes: 3));
      await service.check(resetTimer: true);
      expect(service.nextAutomaticCheck, clock.add(const Duration(minutes: 5)));
      final checked = service.lastChecked;
      clock = clock.add(const Duration(minutes: 3));
      await tester.pump(const Duration(minutes: 3));
      expect(service.lastChecked, checked);
      clock = clock.add(const Duration(minutes: 2));
      await tester.pump(const Duration(minutes: 2));
      await tester.pump();
      expect(service.nextAutomaticCheck, clock.add(const Duration(minutes: 5)));
      expect(service.error, false, reason: service.message);
      expect(service.busy, false, reason: service.message);
      expect(service.lastChecked, clock);
      service.pause();
      expect(service.nextAutomaticCheck, isNull);
      expect(service.automaticCheckRemaining, isNull);
      clock = clock.add(const Duration(minutes: 5));
      await tester.pump(const Duration(minutes: 5));
      expect(service.lastChecked, clock.subtract(const Duration(minutes: 5)));
    },
  );
}
