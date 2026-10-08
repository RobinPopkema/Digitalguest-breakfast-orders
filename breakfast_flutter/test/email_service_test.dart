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
  test('Get today’s orders restores deleted orders but skips confirmed and pending orders', () async {
    await service.saveSettings(input);
    await service.check();
    final original = clone(service.queue.single);
    service.accept({
      'id': original['id'],
      'safeCabinId': '8',
      'confirmed': true,
      'mode': 'quick',
    });
    await service.check(reimport: true);
    expect(service.queue, isEmpty);
    expect(data['orders'], hasLength(1));
    data['orders'] = <Json>[];
    await service.check(reimport: true);
    expect(service.queue, hasLength(1));
    expect(service.queue.single['id'], isNot(original['id']));
    expect(service.queue.single['key'], original['key']);
    expect(service.queue.single['lines'], original['lines']);
    await service.check(reimport: true);
    await service.check();
    expect(service.queue, hasLength(1));
  });

  test('One older-day order can be reimported without changing normal deduplication', () async {
    mail.add(10, source(id: 'older'), '30-Sep-2026 08:00:00 +0000');
    mail.add(11, source(id: 'older'), '30-Sep-2026 08:00:00 +0000');
    await service.saveSettings(input);
    final before = clone(service.imports);
    mail.rejectSearch =
        2; // Older-day recovery also supports the read-only fallback.
    final candidates = await service.reimportCandidates(DateTime(2026, 9, 30));
    expect(candidates, hasLength(1));
    expect(service.imports, before);
    expect(candidates.single['receivedAt'], '2026-09-30T08:00:00.000Z');
    expect(service.reimportSelected(candidates), 1);
    expect(service.quickReady(service.queue.single), isTrue);
    expect(service.reimportSelected(candidates), 0);
    final received = service.queue.single['receivedAt'];
    service.dismiss(service.queue.single['id']);
    expect(service.reimportSelected(candidates), 1);
    expect(service.queue.single['receivedAt'], received);
    expect(service.queue.single.containsKey('importUidKey'), isFalse);
    expect(service.queue.single.containsKey('importAccount'), isFalse);
    await service.check();
    expect(
      service.queue,
      hasLength(2),
    ); // Today's separate order is still found normally.
  });

  test('Multi-select reimport rechecks merged orders and duplicates at commit time', () async {
    mail.add(10, source(id: 'second'), '01-Oct-2026 09:00:00 +0000');
    mail.add(11, source(id: 'third'), '01-Oct-2026 10:00:00 +0000');
    await service.saveSettings(input);
    final candidates = await service.reimportCandidates(clock);
    expect(candidates, hasLength(3));
    data['orders'] = <Json>[
      {
        'mergedOrders': [
          {
            'mergedOrders': [
              {
                'emailSource': {'key': candidates.first['key']},
              },
            ],
          },
        ],
      },
    ];
    expect(
      service.importBlockReason(candidates.first['key']),
      'Already in orders',
    );
    expect(service.reimportSelected([...candidates, ...candidates]), 2);
    expect(service.queue, hasLength(2));
    expect(
      service.importBlockReason(candidates.last['key']),
      'Already pending',
    );
    expect(service.reimportSelected(candidates), 0);
  });

  test(
    'Today’s explicit import reads more than the normal 100-message batch',
    () async {
      mail.messages.clear();
      for (var i = 0; i < 105; i++) {
        mail.add(i + 1, source(id: 'bulk-$i'), '01-Oct-2026 08:00:00 +0000');
      }
      await service.saveSettings(input);
      await service.check(reimport: true);
      expect(service.error, isFalse, reason: service.message);
      expect(service.queue, hasLength(105));
      await service.check();
      expect(service.queue, hasLength(105));
    },
  );

  test('Changing the mailbox after loading prevents stale reimports', () async {
    await service.saveSettings(input);
    final candidates = await service.reimportCandidates(clock);
    final before = clone(service.imports);
    service.config['folder'] = 'Different folder';
    expect(() => service.reimportSelected(candidates), throwsStateError);
    expect(service.imports, before);
  });

  test(
    'Bulk approval keeps warnings and invalid or unmatched orders pending',
    () async {
      await service.saveSettings(input);
      await service.check();
      final original = clone(service.queue.single);
      Json entry(String id, Json changes) => {
        ...clone(original),
        'id': id,
        'key': id,
        ...changes,
      };
      service.imports['queue'] = <Json>[
        entry('ready', {}),
        entry('warning', {
          'warnings': ['Check the source email'],
        }),
        entry('cabin', {'room': 'unknown'}),
        entry('time', {'slot': 'invalid'}),
        entry('item', {
          'lines': [
            {'name': 'Unknown product', 'qty': 1},
          ],
        }),
        entry('quantity', {
          'lines': [
            {'name': 'Croissant', 'qty': 0},
          ],
        }),
        entry('kind', {'kind': 'review'}),
      ];
      final ready = service.queue.first;
      data = clone(data);
      data['categories'][0]['available'] = false;
      expect(service.bulkReady(ready), isFalse);
      data['categories'][0]['available'] = true;
      expect(
        service.acceptReady(
          service.queue.map((e) => e['id'] as String).toSet(),
        ),
        1,
      );
      expect(rows(data['orders']), hasLength(1));
      expect(data['orders'][0]['comment'], original['comment']);
      expect(data['orders'][0]['lines'][0]['qty'], 2);
      expect(service.queue.map((e) => e['id']), [
        'warning',
        'cabin',
        'time',
        'item',
        'quantity',
        'kind',
      ]);
      expect(store.read('email-imports.json', {})['queue'], service.queue);
    },
  );

  test(
    'Bulk approval respects selection and an explicitly reviewed cabin',
    () async {
      await service.saveSettings(input);
      await service.check();
      final original = clone(service.queue.single);
      service.imports['queue'] = <Json>[
        {
          ...clone(original),
          'id': 'selected',
          'key': 'selected',
          'room': 'ambiguous',
        },
        {...clone(original), 'id': 'outside', 'key': 'outside'},
      ];
      expect(service.acceptReady({'selected'}), 0);
      expect(service.acceptReady({'selected'}, cabinIds: {'selected': '9'}), 1);
      expect(data['orders'][0]['room'], '9');
      expect(service.queue.single['id'], 'outside');
      expect(service.acceptReady({'selected'}), 0);
    },
  );

  test('Bulk dismiss preserves seen history, aliases and unrelated pending entries', () async {
    await service.saveSettings(input);
    await service.check();
    final original = clone(service.queue.single);
    service.imports['queue'].add({
      ...clone(original),
      'id': 'keep',
      'key': 'keep',
    });
    final seen = clone(service.imports['seen']);
    final aliases = clone(service.imports['aliases']);
    expect(service.dismissMany({original['id'], 'missing'}), 1);
    expect(service.queue.single['id'], 'keep');
    expect(service.dismissMany({original['id']}), 0);
    expect(service.imports['seen'], seen);
    expect(service.imports['aliases'], aliases);
    await service.check();
    expect(service.queue.single['id'], 'keep');
    expect(data['orders'], isEmpty);
  });

  test('Pending sorting supports all order modes and stable ready grouping without mutating the queue', () async {
    await service.saveSettings(input);
    await service.check();
    final original = clone(service.queue.single);
    data = clone(data);
    data['safeCabins'] = <Json>[
      for (final room in ['2', '3', '10']) {'id': room, 'name': room},
    ];
    service.imports['queue'] = <Json>[
      {
        ...clone(original),
        'id': 'a',
        'room': '10',
        'slot': slots[1],
        'receivedAt': '2026-10-03T08:00:00Z',
      },
      {
        ...clone(original),
        'id': 'b',
        'room': '2',
        'slot': slots[0],
        'receivedAt': '2026-10-01T08:00:00Z',
      },
      {
        ...clone(original),
        'id': 'c',
        'room': '3',
        'slot': slots[2],
        'receivedAt': '2026-10-02T08:00:00Z',
        'warnings': ['Review source'],
      },
    ];
    final before = clone(service.imports);
    final expected = {
      'room': ['b', 'c', 'a'],
      'room-desc': ['a', 'c', 'b'],
      'delivery': ['b', 'a', 'c'],
      'delivery-desc': ['c', 'a', 'b'],
      'newest': ['a', 'c', 'b'],
      'oldest': ['b', 'c', 'a'],
    };
    for (final option in expected.entries) {
      data['pendingViewSort'] = option.key;
      expect(service.sortedPending().map((e) => e['id']), option.value);
    }
    data['pendingViewSort'] = 'room';
    data['pendingReadyPosition'] = 'top';
    expect(service.sortedPending().map((e) => e['id']), ['b', 'a', 'c']);
    data['pendingReadyPosition'] = 'bottom';
    expect(service.sortedPending().map((e) => e['id']), ['c', 'b', 'a']);
    expect(service.imports, before);
    service.queue.last['warnings'] = <String>[];
    expect(service.sortedPending().map((e) => e['id']), ['b', 'c', 'a']);
    expect(data['viewSort'], 'room');
  });

  test('Hidden categories block automatic and explicit imports without losing item flags', () async {
    await service.saveSettings(input);
    await service.check();
    final entry = service.queue.first;
    data = clone(data);
    final category = findById(data['categories'], 'bakery')!;
    category['available'] = false;
    expect(service.matches(entry), ['', '']);
    expect(service.quickReady(entry), isFalse);
    expect(
      () => service.accept({
        'id': entry['id'],
        'safeCabinId': '8',
        'confirmed': true,
        'slot': entry['slot'],
        'lines': [
          {'sourceIndex': 0, 'itemId': 'croissant', 'qty': 2},
          {'sourceIndex': 1, 'itemId': 'butter', 'qty': 1},
        ],
      }),
      throwsStateError,
    );
    expect(service.queue.length, 1);
    findById(data['items'], 'butter')!['available'] = false;
    category['available'] = true;
    expect(service.matches(entry), ['croissant', '']);
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
