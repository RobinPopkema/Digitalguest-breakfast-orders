import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';

import 'package:flutter_test/flutter_test.dart';
import 'package:breakfast_orders/model.dart';
import 'package:breakfast_orders/services/store.dart';
import 'package:breakfast_orders/services/email_parser.dart';
import 'package:breakfast_orders/services/printing.dart';

import 'fixtures.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('Order dates use received time, preserve manual timestamps and omit unknown legacy dates', () {
    final received = DateTime.utc(2026, 10, 4, 8, 15);
    final order = <String, dynamic>{
      'emailSource': {'receivedAt': received.toIso8601String()},
      'createdAt': '2026-10-05T08:00:00Z',
    };
    expect(orderDate(order), received.toLocal());
    expect(
      orderDate({'createdAt': received.toIso8601String()}),
      received.toLocal(),
    );
    expect(
      orderDate({
        'receivedAt': 'invalid',
        'createdAt': received.toIso8601String(),
      }),
      received.toLocal(),
    );
    expect(orderDateLabel({}), isEmpty);
    final data = fixture();
    data['orders'].add({
      'id': 'dated',
      'room': '8',
      'slot': slots.first,
      'comment': '',
      'lines': <Json>[],
      'createdAt': received.toIso8601String(),
    });
    expect(
      validateData(clone(data))['orders'][0]['createdAt'],
      received.toIso8601String(),
    );
  });
  test('First-run migration copies data and queue once without changing the original profile', () {
    final root = Directory.systemTemp.createTempSync('breakfast-migration-');
    addTearDown(() => root.deleteSync(recursive: true));
    final original = Store(Directory('${root.path}/old'));
    original.saveOrders(fixture());
    original.write('email-imports.json', {
      'queue': [
        {'id': 'pending'},
      ],
      'seen': {'old-key': true},
      'aliases': {'pastry': 'croissant'},
    });
    original.write('email-settings.json', {
      'host': 'imap.example.com',
      'secret': 'old-encrypted-secret',
      'enabled': true,
    });
    final originalBytes = original
        .file('breakfast-orders.json')
        .readAsBytesSync();
    final target = '${root.path}/new';
    var migrated = Store.open(
      profile: target,
      importFrom: original.directory.path,
    );
    expect(migrated.loadOrders(), fixture());
    expect(migrated.read('email-imports.json', {})['seen']['old-key'], true);
    expect(
      migrated.read('email-settings.json', {}).containsKey('secret'),
      false,
    );
    expect(migrated.read('email-settings.json', {})['enabled'], false);
    final changed = fixture()..['viewSort'] = 'newest';
    migrated.saveOrders(changed);
    migrated.close();
    migrated = Store.open(profile: target, importFrom: original.directory.path);
    expect(migrated.loadOrders()['viewSort'], 'newest');
    migrated.close();
    expect(
      original.file('breakfast-orders.json').readAsBytesSync(),
      originalBytes,
    );
    expect(
      original.read('email-settings.json', {})['secret'],
      'old-encrypted-secret',
    );
  });
  test(
    'Messages without IDs use the original raw-source SHA-256 duplicate key',
    () {
      final raw = source().replaceAll(
        'Message-ID: <order-one@example.com>\r\n',
        '',
      );
      expect(
        parseOrderEmail(raw)['messageId'],
        sha256.convert(utf8.encode(raw)).toString(),
      );
    },
  );
  test('DigitalGuest breakfast preserves all fields', () {
    final p = parseOrderEmail(source());
    expect(p['kind'], 'breakfast');
    expect(p['slot'], '08:00–08:30');
    expect(p['room'], '8');
    expect(p['comment'], 'Leave outside');
    expect(p['lines'], [
      {'name': 'Croissant', 'qty': 2},
      {'name': 'Butter', 'qty': 1},
    ]);
    expect(p['messageId'], '<order-one@example.com>');
  });
  test('Dinner and other senders are excluded', () {
    expect(parseOrderEmail(source(time: '18:00 - 18:30'))['kind'], 'ignore');
    expect(
      parseOrderEmail(source(sender: 'other@example.com'))['kind'],
      'ignore',
    );
  });
  test('Missing, conflicting and unsupported slots need review', () {
    for (final text in [
      source().replaceAll('1 x 8:00 - 8:30\t0.00 NOK', ''),
      source().replaceAll(
        '2 x Croissant',
        '1 x 18:00 - 18:30\t0.00 NOK\n2 x Croissant',
      ),
      source(time: '6:00 - 6:30'),
    ]) {
      final p = parseOrderEmail(text);
      expect(p['kind'], 'review');
      expect(p['slot'], '');
    }
  });
  test('HTML-only MIME preserves inline guest fields', () {
    final text =
        'From: DigitalGuest <noreply@e.maildigitalguest.com>\r\nSubject: Order request received\r\nContent-Type: text/html; charset=utf-8\r\n\r\n<p>New Order Request</p><p>Request received at: 9/28/2026 - 22:09</p><p>1 x 8:00 - 8:30 0.00 NOK</p><p>2 x Croissant 0.00 NOK</p><p>Order comment Leave outside</p><p>Guest Info Name: Sample Email: guest@example.com Phone: 1234 Room: 8</p>';
    final p = parseOrderEmail(text);
    expect(p['room'], '8');
    expect(p['slot'], '08:00–08:30');
    expect(p['comment'], 'Leave outside');
  });
  test('Unicode alias normalization matches original NFKC behavior', () {
    expect(normalize('  ＣＲＯＩＳＳＡＮＴ \t'), 'croissant');
  });
  test('Raw and wrapped backups preserve unknown fields and legacy rooms', () {
    final data = fixture()..['futureMetadata'] = {'hello': 'world'};
    expect(validateData(jsonDecode(jsonEncode(data))), data);
    final old = fixture()..remove('safeCabins');
    expect(validateData(old)['safeCabins'], isEmpty);
    expect(old['rooms'], ['old untrusted cabin']);
  });
  test('Validation rejects malformed data without overwriting storage', () {
    final dir = Directory.systemTemp.createTempSync('breakfast-store-');
    addTearDown(() => dir.deleteSync(recursive: true));
    final store = Store(dir);
    store.saveOrders(fixture());
    expect(() => store.saveOrders({'orders': []}), throwsFormatException);
    expect(store.loadOrders(), fixture());
  });
  test('Atomic saves retain previous valid copy, daily backups and recover corrupt primary', () {
    final dir = Directory.systemTemp.createTempSync('breakfast-store-');
    addTearDown(() => dir.deleteSync(recursive: true));
    final store = Store(dir);
    final old = fixture();
    store.saveOrders(old);
    final next = clone(old)..['viewSort'] = 'newest';
    store.saveOrders(next);
    expect(
      jsonDecode(store.file('breakfast-orders.json.bak').readAsStringSync()),
      old,
    );
    expect(Directory('${dir.path}/backups').listSync().length, 1);
    store.file('breakfast-orders.json').writeAsStringSync('{broken');
    expect(store.loadOrders(), old);
    store.saveOrders(next);
    expect(
      jsonDecode(store.file('breakfast-orders.json.bak').readAsStringSync()),
      old,
    );
  });
  test('All sort modes preserve stable ties and never mutate stored order', () {
    final data = fixture();
    data['orders'] = [
      {'id': 'a', 'room': '10', 'slot': slots[0]},
      {'id': 'b', 'room': '2', 'slot': slots[1]},
      {'id': 'c', 'room': '2', 'slot': slots[1]},
      {'id': 'd', 'room': '2', 'slot': slots[0]},
    ];
    final expected = {
      'room': ['d', 'b', 'c', 'a'],
      'room-desc': ['a', 'd', 'b', 'c'],
      'delivery': ['d', 'a', 'b', 'c'],
      'delivery-desc': ['b', 'c', 'd', 'a'],
      'oldest': ['a', 'b', 'c', 'd'],
      'newest': ['d', 'c', 'b', 'a'],
    };
    for (final mode in expected.entries) {
      data['viewSort'] = mode.key;
      expect(sortedOrders(data).map((order) => order['id']), mode.value);
      expect(rows(data['orders']).map((order) => order['id']), [
        'a',
        'b',
        'c',
        'd',
      ]);
    }
  });

  test('Natural room sorting and insertion order survive edits', () {
    final data = fixture();
    data['orders'] = [
      {'id': 'a', 'room': '10', 'slot': slots[0], 'lines': []},
      {'id': 'b', 'room': '2', 'slot': slots[1], 'lines': []},
    ];
    expect(sortedOrders(data).first['id'], 'b');
    data['viewSort'] = 'newest';
    data['orders'][0]['room'] = '1';
    expect(sortedOrders(data).first['id'], 'b');
    data['viewSort'] = 'oldest';
    expect(sortedOrders(data).first['id'], 'a');
  });
  test(
    'Menu updates affect snapshots while removed items and cabins remain',
    () {
      final data = fixture();
      data['orders'] = [
        {
          'id': 'o',
          'room': '9',
          'lines': [
            lineFor(data['items'][0], data['categories'][0], 2),
            {
              'itemId': 'gone',
              'name': 'Removed',
              'categoryId': 'gone',
              'categoryName': 'Old',
              'categoryColor': 3,
              'qty': 1,
            },
          ],
        },
      ];
      data['categories'][0]['color'] = 15;
      data['items'][0]['name'] = 'Croissants';
      data['safeCabins'][1]['name'] = 'New name';
      updateSnapshots(data);
      expect(data['orders'][0]['room'], '9');
      expect(data['orders'][0]['lines'][0]['name'], 'Croissants');
      expect(data['orders'][0]['lines'][0]['categoryColor'], 15);
      expect(data['orders'][0]['lines'][1]['name'], 'Removed');
    },
  );
  test('Print document includes original measured layout and safely embeds untrusted strings', () async {
    final data = fixture();
    data['orders'] = [
      {
        'id': 'o',
        'room': '</script><script>alert(1)</script>',
        'slot': slots[0],
        'comment': 'A & B',
        'lines': [],
      },
    ];
    final html = await Printing.document(data, 'orders', {});
    expect(
      html,
      contains('paginateOrderSlips();paginateTotals();paginateTimetable();'),
    );
    expect(html, contains('width:297mm;height:210mm;padding:4mm'));
    expect(html, contains('window.print()'));
    expect(html, contains(r'\u003c/script\u003e'));
    expect(html, contains('"printMode":"orders"'));
    expect(html, isNot(contains('</script><script>alert(1)')));
  });
}
