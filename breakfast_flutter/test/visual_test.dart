import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:breakfast_orders/controller.dart';
import 'package:breakfast_orders/main.dart';
import 'package:breakfast_orders/model.dart';
import 'package:breakfast_orders/services/store.dart';
import 'package:breakfast_orders/services/printing.dart';

import 'fixtures.dart';

void main() {
  testWidgets(
    'Desktop and compact-window layouts remain usable with realistic orders',
    (tester) async {
      final icons = FontLoader('MaterialIcons')
        ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'));
      await icons.load();
      final font = File('C:/Windows/Fonts/segoeui.ttf');
      if (font.existsSync()) {
        final loader = FontLoader('Segoe UI')
          ..addFont(Future.value(ByteData.sublistView(font.readAsBytesSync())));
        await loader.load();
      }
      final dir = Directory.systemTemp.createTempSync('breakfast-visual-');
      final store = Store(dir), data = fixture();
      data['categories'].addAll([
        {'id': 'drinks', 'name': 'Drinks', 'color': 7},
        {'id': 'fresh', 'name': 'Fresh fruit', 'color': 2},
      ]);
      data['items'].addAll([
        {
          'id': 'coffee',
          'name': 'Freshly brewed coffee',
          'categoryId': 'drinks',
        },
        {'id': 'juice', 'name': 'Orange juice', 'categoryId': 'drinks'},
        {'id': 'fruit', 'name': 'Seasonal fruit bowl', 'categoryId': 'fresh'},
      ]);
      data['orders'] = List.generate(
        5,
        (i) => {
          'id': 'o$i',
          'room': ['2', '8', '12', 'Cabin A', 'Cabin B'][i],
          'slot': slots[i % 3],
          if (i == 1)
            'guest': {
              'name': 'Robin Sample',
              'email': 'robin@example.com',
              'phone': '+31 6 12345678',
            },
          'comment': i == 1 ? 'Leave outside the cabin. Thank you!' : '',
          'lines': [
            lineFor(data['items'][0], data['categories'][0], i + 1),
            lineFor(data['items'][2], data['categories'][1], 2),
          ],
        },
      );
      store.saveOrders(data);
      final app = AppController(store);
      app.email.lastChecked = DateTime(2026, 10, 2, 8, 45);
      app.email.nextAutomaticCheck = DateTime.now().add(
        const Duration(seconds: 40),
      );
      app.email.imports['queue'] = [
        {
          'id': 'email',
          'key': 'sample',
          'kind': 'breakfast',
          'room': 'Guest cabin 9',
          'slot': slots[2],
          'comment': 'No butter, please.',
          'lines': [
            {'name': 'Croissant', 'qty': 2},
            {'name': 'Unknown breakfast item', 'qty': 1},
          ],
          'warnings': [],
          'text': 'Anonymous DigitalGuest sample',
          'guest': {
            'name': 'Sam Guest',
            'email': 'sam@example.com',
            'phone': '+47 12345678',
          },
        },
      ];
      final key = GlobalKey();
      addTearDown(() {
        app.dispose();
        dir.deleteSync(recursive: true);
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });
      tester.view.physicalSize = const Size(1240, 850);
      tester.view.devicePixelRatio = 1;
      await tester.pumpWidget(
        RepaintBoundary(key: key, child: BreakfastApp(app)),
      );
      await tester.pumpAndSettle();
      await tester.runAsync(
        () => precacheImage(
          const AssetImage('assets/icon-256.png'),
          key.currentContext!,
        ),
      );
      await tester.pumpAndSettle();
      Future<void> capture(String name) async {
        expect(tester.takeException(), isNull);
        if (!const bool.fromEnvironment('CAPTURE_PREVIEWS')) return;
        await tester.runAsync(() async {
          final image =
              await (key.currentContext!.findRenderObject()
                      as RenderRepaintBoundary)
                  .toImage();
          final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
          Directory('docs/previews').createSync(recursive: true);
          File('docs/previews/$name.png')
              .writeAsBytesSync(bytes!.buffer.asUint8List());
          image.dispose();
        });
      }

      await capture('orders');
      app.setDarkMode(true);
      await tester.pumpAndSettle();
      await capture('dark-orders');
      await tester.tap(find.byTooltip('Expand pending order Guest cabin 9'));
      await tester.tap(find.byTooltip('Expand order 8'));
      await tester.pumpAndSettle();
      await capture('dark-expanded');
      await tester.tap(find.byTooltip('Collapse pending order Guest cabin 9'));
      await tester.tap(find.byTooltip('Collapse order 8'));
      await tester.tap(find.text('New order').first);
      await tester.pumpAndSettle();
      await capture('dark-order-editor');
      await tester.tap(find.byTooltip('Close'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Review & map'));
      await tester.pumpAndSettle();
      await capture('dark-email-review');
      await tester.tap(find.byTooltip('Close'));
      await tester.pumpAndSettle();
      tester.view.physicalSize = const Size(800, 600);
      await tester.pumpAndSettle();
      await capture('dark-compact-orders');
      await tester.tap(find.text('Settings'));
      await tester.pumpAndSettle();
      for (var section = 0; section < 5; section++) {
        await tester.tap(find.byKey(ValueKey('settings-section-$section')));
        await tester.pumpAndSettle();
        await capture('dark-settings-$section');
        if (section == 2) {
          await tester.ensureVisible(find.text('Check every 1 minute'));
          await tester.pumpAndSettle();
          await capture('dark-check-interval');
        }
      }
      await tester.tap(find.byTooltip('Close'));
      await tester.pumpAndSettle();
      app.setDarkMode(false);
      tester.view.physicalSize = const Size(1240, 850);
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Expand pending order Guest cabin 9'));
      await tester.pumpAndSettle();
      await capture('incoming-expanded');
      await tester.tap(find.byTooltip('Collapse pending order Guest cabin 9'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Expand order 8'));
      await tester.tap(find.byType(Checkbox).at(2));
      await tester.pumpAndSettle();
      await capture('orders-expanded');
      await tester.tap(find.byTooltip('Collapse order 8'));
      await tester.tap(find.byType(Checkbox).at(2));
      await tester.pumpAndSettle();
      await tester.tap(find.text('New order').first);
      await tester.pumpAndSettle();
      await capture('order-editor');
      await tester.tap(find.byTooltip('Close'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Review & map'));
      await tester.pumpAndSettle();
      await capture('email-review');
      await tester.tap(find.byTooltip('Close'));
      await tester.pumpAndSettle();
      tester.view.physicalSize = const Size(800, 600);
      await tester.pumpAndSettle();
      await capture('compact-orders');
      await tester.tap(find.text('Settings'));
      await tester.pumpAndSettle();

      await tester.pumpAndSettle();
      await capture('compact-menu');
      await tester.tap(find.byTooltip('Category color: Sky blue').first);
      await tester.pumpAndSettle();
      await capture('category-colors');
      await tester.tap(find.byTooltip('Sky blue'));
      await tester.pumpAndSettle();
      for (var section = 1; section < 5; section++) {
        await tester.tap(find.byKey(ValueKey('settings-section-$section')));
        await tester.pumpAndSettle();
        await capture('compact-settings-$section');
        if (section == 2) {
          await tester.ensureVisible(find.text('Check every 1 minute'));
          await tester.pumpAndSettle();
          await capture('check-interval');
        }
      }
      await tester.tap(find.text('Menu'));
      await tester.pumpAndSettle();
      await capture('compact-menu-items');
      expect(tester.takeException(), isNull);
      await tester.tap(find.byTooltip('Close'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('New order').first);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      if (const bool.fromEnvironment('CAPTURE_PREVIEWS')) {
        await tester.runAsync(() async {
          for (final mode in [
            'all',
            'orders',
            'selected',
            'schedule',
            'totals',
            'timetable',
          ]) {
            File('docs/previews/print-$mode.html')
                .writeAsStringSync(await Printing.document(data, mode, {'o1'}));
          }
          final long = clone(data);
          long['orders'][0]['lines'] = List.generate(
            90,
            (i) => {
              'itemId': 'long$i',
              'name': 'Long item $i with extra details and a dietary note',
              'categoryId': 'bakery',
              'categoryName': 'Bakery',
              'categoryColor': 0,
              'qty': i + 1,
            },
          );
          long['orders'][0]['comment'] =
              'Keep all this comment text when continuing the slip. ' * 80;
          File('docs/previews/print-overflow.html')
              .writeAsStringSync(await Printing.document(long, 'all', {}));
        });
      }
    },
  );
}
