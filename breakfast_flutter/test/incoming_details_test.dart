import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:html/parser.dart' as html;
import 'package:breakfast_orders/model.dart';
import 'package:breakfast_orders/services/email_parser.dart';
import 'package:breakfast_orders/services/email_preview.dart';
import 'package:breakfast_orders/services/email_service.dart';
import 'package:breakfast_orders/services/store.dart';

import 'fixtures.dart';

void main() {
  test('Reservation is separated from room for inline HTML and saved pending imports', () {
    final text = source().replaceFirst('Room: 8', 'Room: 16 Res No.: 18052');
    final parsed = parseOrderEmail(text);
    expect(parsed['room'], '16');
    expect(parsed['guest']['reservation'], '18052');
    final old = <String, dynamic>{
      'room': '16 Res No.: 18052',
      'text': parsed['text'],
      'guest': {'name': 'Sample'},
    };
    expect(guestCabin(old), '16');
    expect(guestDetails(old)['reservation'], '18052');
    expect(
      parseGuest('Guest Info Name: Sample Res No.: ABC-42 Total 0')['name'],
      'Sample',
    );
    expect(
      parseGuest(
        'Guest Info Name: Sample Res No.: ABC-42 Total 0',
      )['reservation'],
      'ABC-42',
    );
    final markup =
        '<p>Guest Info</p><table><tr><td>Room: 16</td><td>Res No.: 18052</td></tr></table>';
    expect(parseGuest(htmlText(markup))['reservation'], '18052');
  });
  test(
    'Accommodation numbers never learn cabin aliases from manual selections',
    () {
      final dir = Directory.systemTemp.createTempSync('breakfast-cabin-alias-');
      addTearDown(() => dir.deleteSync(recursive: true));
      var data = fixture();
      data['safeCabins'] = [
        {'id': 'panorama-1', 'name': 'Panorama 1'},
        {'id': 'igloo-1', 'name': 'Igloo 1'},
      ];
      final store = Store(dir);
      EmailService create() => EmailService(
        store,
        readOrders: () => data,
        writeOrders: (next) => data = next,
      );
      var service = create();
      addTearDown(() => service.dispose());
      expect(service.matchingCabin({'room': 'panorama 1'}), 'panorama-1');
      expect(service.matchingCabin({'room': 'IGLOO 1'}), 'igloo-1');
      for (final name in ['1', '01', 'Panorama', 'P 1', 'panorama1']) {
        expect(service.matchingCabin({'room': name}), isNull);
      }
      service.imports['queue'] = [
        {
          ...parseOrderEmail(source()),
          'id': 'number-only',
          'key': 'number-only',
          'room': '1',
        },
      ];
      service.accept({
        'id': 'number-only',
        'safeCabinId': 'panorama-1',
        'mode': 'quick',
        'confirmed': true,
      });
      expect(data['orders'][0]['room'], 'Panorama 1');
      expect(service.imports['aliases'].containsKey('1'), isFalse);
      service.dispose();
      service = create();
      expect(service.matchingCabin({'room': '1'}), isNull);
      // Even an existing menu alias cannot be used as a cabin alias.
      service.imports['aliases']['1'] = 'panorama-1';
      expect(service.matchingCabin({'room': '1'}), isNull);
    },
  );
  test('HTML table cells separate guest labels and values', () {
    final text = htmlText(
      '<h2>Guest Info</h2><table><tr><td>Name:</td><td>Sample Guest</td></tr><tr><td>Email:</td><td>guest@example.com</td></tr><tr><td>Phone:</td><td>+31 123</td></tr></table>',
    );
    expect(parseGuest(text), {
      'name': 'Sample Guest',
      'email': 'guest@example.com',
      'phone': '+31 123',
    });
  });
  test('Guest contacts are extracted from inline and multiline guest sections', () {
    for (final separator in ['\n', ' ']) {
      final parsed = parseOrderEmail(
        source().replaceAll(
          'Name: Sample\nRoom: 8',
          'Name: Robin Sample${separator}Email: guest@example.com${separator}Phone: +31 6 12345678${separator}Room: 8',
        ),
      );
      expect(parsed['guest'], {
        'name': 'Robin Sample',
        'email': 'guest@example.com',
        'phone': '+31 6 12345678',
      });
      expect(parsed['room'], '8');
    }
    expect(parseGuest('Name: Outside\nEmail: sender@example.com'), isEmpty);
    expect(
      parseGuest(
        'Guest Info\nName:\nEmail: guest@example.com\nRoom: 8',
      )['name'],
      '',
    );
  });

  test('HTML MIME retains formatting and decodes guest contact entities', () {
    final markup =
        '<h1>New Order Request</h1><p>Request received at: today</p><p>1 x 8:00 - 8:30</p><p>2 x Croissant</p><p>Guest Info Name: Robin &amp; Sam Email: guest@example.com Phone: +31 123 Room: 8</p>';
    final parsed = parseOrderEmail(
      'From: <$defaultSender>\r\nSubject: Order request received\r\nContent-Type: text/html; charset=utf-8\r\n\r\n$markup',
    );
    expect(parsed['html'], markup);
    expect(parsed['guest']['name'], 'Robin & Sam');
    expect(parsed['guest']['email'], 'guest@example.com');
    expect(parsed['guest']['phone'], '+31 123');
  });

  test('Cabin matching is exact apart from case and outer spaces; ambiguous names are not selected', () {
    final dir = Directory.systemTemp.createTempSync('breakfast-matches-');
    addTearDown(() => dir.deleteSync(recursive: true));
    final data = fixture();
    data['safeCabins'].add({'id': 'named', 'name': 'Cabin Oak'});
    final service = EmailService(
      Store(dir),
      readOrders: () => data,
      writeOrders: (_) {},
    );
    addTearDown(service.dispose);
    expect(service.matchingCabin({'room': ' CABIN oak '}), 'named');
    expect(service.matchingCabin({'room': 'Cabin'}), isNull);
    expect(service.matchingCabin({'room': '08'}), isNull);
    expect(service.matchingCabin({'room': ''}), isNull);
    data['safeCabins'].add({'id': 'duplicate', 'name': 'cabin oak'});
    expect(service.matchingCabin({'room': 'Cabin Oak'}), isNull);
  });

  test('Quick and revised acceptance retain contact and source across storage reloads', () {
    for (final mode in ['quick', 'review']) {
      final dir = Directory.systemTemp.createTempSync('breakfast-contact-');
      addTearDown(() => dir.deleteSync(recursive: true));
      final store = Store(dir)..saveOrders(fixture());
      final service = EmailService(
        store,
        readOrders: store.loadOrders,
        writeOrders: store.saveOrders,
      );
      addTearDown(service.dispose);
      final entry = {
        ...parseOrderEmail(source()),
        'id': 'pending',
        'key': 'mail-key',
        'html': '<p>Original email</p>',
      };
      // Older queued emails can recover contacts from their saved text.
      entry.remove('guest');
      service.imports['queue'] = [entry];
      service.accept({
        'id': 'pending',
        'safeCabinId': '8',
        'confirmed': true,
        'mode': mode,
        'slot': slots.first,
        'lines': [
          {'itemId': 'croissant', 'qty': 2},
        ],
      });
      final saved = store.loadOrders()['orders'][0];
      expect(saved['guest']['name'], 'Sample');
      expect(saved['emailSource']['html'], '<p>Original email</p>');
      expect(saved['emailSource']['text'], entry['text']);
      expect(service.queue, isEmpty);
    }
  });

  test('Email preview preserves tables and styles while removing active content and remote resources', () {
    final output = EmailPreview.document({
      'html': '<html><head><style>td{color:red}</style><meta http-equiv="refresh" content="0;url=https://example.com"></head><body onload="alert(1)"><script>alert(1)</script><table style="width:100%"><tr><td>Breakfast</td></tr></table><img src="https://example.com/pixel"><a href="javascript:alert(1)">Link</a><iframe srcdoc="bad"></iframe><form action="https://example.com"><input></form></body></html>',
    });
    final doc = html.parse(output);
    expect(doc.querySelector('table')?.attributes['style'], 'width:100%');
    expect(doc.querySelectorAll('style').last.text, 'td{color:red}');
    expect(
      doc.querySelectorAll('script,iframe,form,input,[onload],[src],[href]'),
      isEmpty,
    );
    expect(doc.querySelector('meta[http-equiv="refresh"]'), isNull);
    expect(
      doc
          .querySelector('meta[http-equiv="Content-Security-Policy"]')
          ?.attributes['content'],
      contains("default-src 'none'"),
    );
    final fallback = html.parse(
      EmailPreview.document({'text': '<script>Guest text</script>'}),
    );
    expect(fallback.querySelector('pre')?.text, '<script>Guest text</script>');
    expect(fallback.querySelectorAll('script'), isEmpty);
  });
}
