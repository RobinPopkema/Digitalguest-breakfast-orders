import 'dart:io';
import 'dart:ui' show PointerDeviceKind;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:breakfast_orders/main.dart';
import 'package:breakfast_orders/controller.dart';
import 'package:breakfast_orders/model.dart';
import 'package:breakfast_orders/services/store.dart';

import 'fixtures.dart';

void main() {
  late Directory dir;
  late AppController app;
  setUp(() {
    dir = Directory.systemTemp.createTempSync('breakfast-ui-');
    final store = Store(dir);
    store.saveOrders(fixture());
    app = AppController(store);
  });
  tearDown(() {
    app.dispose();
    dir.deleteSync(recursive: true);
  });
  Future<void> open(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1240, 850);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(BreakfastApp(app));
    await tester.pumpAndSettle();
  }

  testWidgets(
    'Dragging an expanded category collapses its contents and reopens on release',
    (tester) async {
      await open(tester);
      await tester.tap(find.text('Settings'));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('edit-croissant')), findsOneWidget);
      final gesture = await tester.startGesture(
        tester.getCenter(find.byKey(const ValueKey('drag-category-bakery'))),
        kind: PointerDeviceKind.mouse,
      );
      // Move before a frame: the old implementation captured the expanded height.
      await gesture.moveBy(const Offset(0, 25));
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump();
      expect(find.byKey(const ValueKey('edit-croissant')), findsNothing);
      expect(find.byKey(const ValueKey('edit-butter')), findsNothing);
      expect(
        tester
            .getSize(find.byKey(const ValueKey('category-drag-preview')))
            .height,
        lessThanOrEqualTo(61),
      );
      await gesture.up();
      await tester.pump(const Duration(milliseconds: 16));
      expect(find.byKey(const ValueKey('edit-croissant')), findsNothing);
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('edit-croissant')), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'Expanded category moves as a compact row and reopens at its new position',
    (tester) async {
      app.edit((data) {
        data['categories'].add({'id': 'drinks', 'name': 'Drinks', 'color': 2});
        data['items'].add({
          'id': 'coffee',
          'name': 'Coffee',
          'categoryId': 'drinks',
        });
      });
      await open(tester);
      await tester.tap(find.text('Settings'));
      await tester.pumpAndSettle();
      final gesture = await tester.startGesture(
        tester.getCenter(find.byKey(const ValueKey('drag-category-bakery'))),
        kind: PointerDeviceKind.mouse,
      );
      await gesture.moveBy(const Offset(0, 25));
      await tester.pump();
      await tester.pump();
      final target =
          tester.getCenter(find.byKey(const ValueKey('drag-category-drinks'))) +
          const Offset(0, 90);
      await gesture.moveTo(target);
      await tester.pump(const Duration(milliseconds: 400));
      expect(
        tester
            .getSize(find.byKey(const ValueKey('category-drag-preview')))
            .height,
        lessThanOrEqualTo(61),
      );
      expect(find.byKey(const ValueKey('edit-croissant')), findsNothing);
      await gesture.up();
      await tester.pump(const Duration(milliseconds: 16));
      expect(find.byKey(const ValueKey('edit-croissant')), findsNothing);
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('edit-croissant')), findsOneWidget);
      await tester.tap(find.text('Save all changes'));
      await tester.pumpAndSettle();
      expect(rows(app.data['categories']).map((c) => c['id']), [
        'drinks',
        'bakery',
      ]);
      expect(findById(app.data['items'], 'croissant')!['categoryId'], 'bakery');
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'Quick handle clicks and cancelled mouse drags restore the category',
    (tester) async {
      await open(tester);
      await tester.tap(find.text('Settings'));
      await tester.pumpAndSettle();
      for (final startDrag in [false, true]) {
        final gesture = await tester.startGesture(
          tester.getCenter(find.byKey(const ValueKey('drag-category-bakery'))),
          kind: PointerDeviceKind.mouse,
        );
        if (startDrag) {
          await gesture.moveBy(const Offset(0, 25));
          await tester.pump();
          await tester.pump();
          await gesture.cancel();
        } else {
          await gesture.up();
        }
        await tester.pumpAndSettle();
        expect(find.byKey(const ValueKey('edit-croissant')), findsOneWidget);
        expect(tester.takeException(), isNull);
      }
    },
  );

  testWidgets(
    'Category visibility preserves item choices and hides new-order entries',
    (tester) async {
      findById(app.data['items'], 'butter')!['available'] = false;
      await open(tester);
      await tester.tap(find.text('Settings'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('available-bakery')));
      await tester.tap(find.text('Save all changes'));
      await tester.pumpAndSettle();
      expect(findById(app.data['categories'], 'bakery')!['available'], isFalse);
      expect(
        itemAvailable(findById(app.data['items'], 'croissant')!, app.data),
        isFalse,
      );
      await tester.tap(find.text('New order').first);
      await tester.pumpAndSettle();
      expect(find.text('Croissant'), findsNothing);
      await tester.tap(find.byTooltip('Close'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Settings'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('available-bakery')));
      await tester.tap(find.text('Save all changes'));
      await tester.pumpAndSettle();
      expect(
        itemAvailable(findById(app.data['items'], 'croissant')!, app.data),
        isTrue,
      );
      expect(
        itemAvailable(findById(app.data['items'], 'butter')!, app.data),
        isFalse,
      );
      expect(app.store.loadOrders()['categories'], app.data['categories']);
    },
  );

  testWidgets(
    'Selected orders merge after confirmation and retain original details',
    (tester) async {
      app.edit(
        (data) => data['orders'] = <Json>[
          for (var i = 0; i < 3; i++)
            {
              'id': 'merge$i',
              'room': '${8 + i}',
              'slot': slots[i],
              'comment': 'Note $i',
              'guest': {'name': 'Guest $i'},
              'emailSource': {'key': 'mail$i', 'text': 'Email $i'},
              'lines': <Json>[
                lineFor(data['items'][0], data['categories'][0], i + 1),
              ],
            },
        ],
      );
      await open(tester);
      expect(find.text('Merge selected (3)'), findsNothing);
      await tester.tap(find.byType(Checkbox).first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Merge selected (3)'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(app.data['orders'].length, 3);
      await tester.tap(find.text('Merge selected (3)'));
      await tester.pumpAndSettle();
      await tester.tap(find.byType(DropdownButtonFormField<String>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('2. 9 · ${slots[1]}').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Merge orders'));
      await tester.pumpAndSettle();
      final merged = app.store.loadOrders()['orders'].single as Json;
      expect(merged['room'], '9');
      expect(merged['slot'], slots[1]);
      expect(merged['lines'].single['qty'], 6);
      expect(merged['mergedOrders'].length, 3);
      expect(merged['comment'], contains('Note 0'));
      expect(orderHasEmailKey(merged, 'mail0'), isTrue);
      expect(orderHasEmailKey(merged, 'mail2'), isTrue);
      expect(find.text('Original orders (3)'), findsOneWidget);
      expect(find.text('Merge selected (3)'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'Startup update opens About once and installation waits for confirmation',
    (tester) async {
      await open(tester);
      expect(find.text('Update available'), findsNothing);
      app.updates.available = {'version': 'v2.0.27', 'notes': 'Example fixes'};
      app.updates.startupNoticePending = true;
      app.updates.changed();
      await tester.pumpAndSettle();
      expect(find.text('Update available'), findsNothing);
      expect(find.text('A new version is available'), findsOneWidget);
      await tester.tap(find.text('Update and restart'));
      await tester.pumpAndSettle();
      expect(find.text('Update to v2.0.27?'), findsOneWidget);
      expect(find.text('Update and restart'), findsNWidgets(2));
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(app.updates.installing, isFalse);
      expect(find.text('A new version is available'), findsOneWidget);
      await tester.tap(find.byTooltip('Close'));
      await tester.pumpAndSettle();
      app.updates.changed();
      await tester.pumpAndSettle();
      expect(find.text('A new version is available'), findsNothing);
    },
  );

  testWidgets('Startup notice waits for order editing to close', (
    tester,
  ) async {
    await open(tester);
    await tester.tap(find.text('New order').first);
    await tester.pumpAndSettle();
    app.updates.available = {'version': 'v9.0.0', 'notes': 'Fixes'};
    app.updates.startupNoticePending = true;
    app.updates.changed();
    await tester.pumpAndSettle();
    expect(find.text('A new version is available'), findsNothing);
    await tester.tap(find.byTooltip('Close'));
    await tester.pumpAndSettle();
    expect(find.text('A new version is available'), findsOneWidget);
  });

  testWidgets(
    'Pending cabin selector shows guest input and reservation details',
    (tester) async {
      app.email.imports['queue'] = [
        {
          'id': 'reservation-test',
          'kind': 'breakfast',
          'room': 'Panorama 16',
          'slot': slots.first,
          'comment': '',
          'lines': [
            {'name': 'Croissant', 'qty': 1},
          ],
          'warnings': [],
          'key': 'reservation-test',
          'guest': {'name': 'Guest', 'reservation': 'ABC-42'},
        },
      ];
      await open(tester);
      expect(find.text('ABC-42'), findsOneWidget);
      final selector = find.byKey(
        const ValueKey('cabin-reservation-test-null'),
      );
      final field = tester.widget<DropdownButton<String>>(
        find.descendant(
          of: selector,
          matching: find.byType(DropdownButton<String>),
        ),
      );
      expect((field.hint as Text).data, 'Panorama 16');
      expect(
        field.style!.color,
        Theme.of(tester.element(selector)).colorScheme.error,
      );
      await tester.tap(selector);
      await tester.pumpAndSettle();
      await tester.tap(find.text('8').last);
      await tester.pumpAndSettle();
      final selected = find.byKey(const ValueKey('cabin-reservation-test-8'));
      expect(
        tester
            .widget<DropdownButton<String>>(
              find.descendant(
                of: selected,
                matching: find.byType(DropdownButton<String>),
              ),
            )
            .style!
            .color,
        Theme.of(tester.element(selected)).colorScheme.onSurface,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'Availability is staged, persisted and prevents adding unavailable items',
    (tester) async {
      await open(tester);
      await tester.tap(find.text('Settings'));
      await tester.pumpAndSettle();
      final toggle = find.byKey(const ValueKey('available-croissant'));
      await tester.tap(toggle);
      await tester.pumpAndSettle();
      expect(itemAvailable(app.data['items'][0]), isTrue);
      await tester.tap(find.text('Save all changes'));
      await tester.pumpAndSettle();
      expect(itemAvailable(app.store.loadOrders()['items'][0]), isFalse);
      await tester.tap(find.text('New order').first);
      await tester.pumpAndSettle();
      expect(find.text('Unavailable'), findsOneWidget);
      expect(
        tester
            .widget<IconButton>(
              find.byWidgetPredicate(
                (w) => w is IconButton && w.tooltip == 'Add one Croissant',
              ),
            )
            .onPressed,
        isNull,
      );
      expect(
        tester
            .widget<IconButton>(
              find.byWidgetPredicate(
                (w) => w is IconButton && w.tooltip == 'Add one Butter',
              ),
            )
            .onPressed,
        isNotNull,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'Cabin pills can be searched, renamed and deleted without changing order history',
    (tester) async {
      await open(tester);
      await tester.tap(find.text('Settings'));
      await tester.pumpAndSettle();
      expect(find.text('Categories'), findsNothing);
      expect(find.byKey(const ValueKey('settings-section-0')), findsOneWidget);
      await tester.tap(find.text('Cabins'));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('cabin-pill-8')), findsOneWidget);
      await tester.tap(find.byTooltip('Edit cabin 8'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('edit-cabin-name')),
        '9',
      );
      await tester.tap(find.text('Save cabin'));
      await tester.pumpAndSettle();
      expect(find.text('This cabin already exists.'), findsOneWidget);
      await tester.enterText(
        find.byKey(const ValueKey('edit-cabin-name')),
        'Panorama 8',
      );
      await tester.tap(find.text('Save cabin'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('search-cabins')),
        'panorama',
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('cabin-pill-8')), findsOneWidget);
      expect(find.byKey(const ValueKey('cabin-pill-9')), findsNothing);
      await tester.enterText(find.byKey(const ValueKey('search-cabins')), '');
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Delete cabin 9'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Remove'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Save all changes'));
      await tester.pumpAndSettle();
      expect(app.data['safeCabins'], [
        {'id': '8', 'name': 'Panorama 8'},
      ]);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'Order overview follows menu grouping without rewriting saved lines',
    (tester) async {
      app.edit((data) {
        data['categories'].add({
          'id': 'yoghurt',
          'name': 'Yoghurt',
          'color': 2,
        });
        data['items'].addAll([
          {'id': 'granola', 'name': 'Granola', 'categoryId': 'bakery'},
          {'id': 'yoghurt', 'name': 'Yoghurt', 'categoryId': 'yoghurt'},
        ]);
        data['orders'] = [
          {
            'id': 'grouped',
            'room': '8',
            'slot': slots.first,
            'comment': '',
            'lines': [
              lineFor(data['items'][0], data['categories'][0], 1),
              lineFor(data['items'][3], data['categories'][1], 2),
              lineFor(data['items'][2], data['categories'][0], 3),
              {
                'itemId': 'gone',
                'name': 'Removed item',
                'categoryId': 'bakery',
                'categoryName': 'Bakery',
                'categoryColor': 0,
                'qty': 4,
              },
            ],
          },
        ];
      });
      final before = clone(app.data);
      await open(tester);
      expect(
        tester.getTopLeft(find.byTooltip('Expand order 8')).dx -
            tester.getTopRight(find.byTooltip('Edit order for 8')).dx,
        greaterThanOrEqualTo(8),
      );
      await tester.tap(find.byTooltip('Expand order 8'));
      await tester.pumpAndSettle();
      final granola = tester.getTopLeft(find.text('Granola')).dy;
      final yoghurt = tester.getTopLeft(find.text('Yoghurt').last).dy;
      expect(granola, lessThan(yoghurt));
      expect(
        tester.getTopLeft(find.text('Removed item')).dy,
        lessThan(yoghurt),
      );
      expect(app.data, before);
      expect(
        orderedOrderLines(
          app.data,
          app.data['orders'][0],
        ).map((line) => line['qty']),
        [1, 3, 4, 2],
      );
      app.edit(
        (data) =>
            data['categories'] = rows(data['categories']).reversed.toList(),
      );
      await tester.pumpAndSettle();
      expect(
        tester.getTopLeft(find.text('Yoghurt').last).dy,
        lessThan(tester.getTopLeft(find.text('Granola')).dy),
      );
      expect(app.data['orders'], before['orders']);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'Review only maps unmatched products and preserves every source quantity',
    (tester) async {
      app.email.imports['queue'] = [
        {
          'id': 'review',
          'key': 'review-key',
          'kind': 'breakfast',
          'room': '8',
          'slot': slots.first,
          'comment': '',
          'warnings': [],
          'lines': [
            {'name': 'Croissant', 'qty': 2},
            {'name': 'Unknown spread', 'qty': 3},
          ],
        },
      ];
      await open(tester);
      await tester.tap(find.byTooltip('Review & map'));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('review-line-0')), findsNothing);
      expect(find.byKey(const ValueKey('review-line-1')), findsOneWidget);
      expect(find.text('× 3'), findsOneWidget);
      expect(find.widgetWithText(TextFormField, 'Qty'), findsNothing);
      expect(find.text('Add a menu item'), findsNothing);
      await tester.tap(find.byKey(const ValueKey('map-1')));
      await tester.pumpAndSettle();
      expect(find.text('Bakery'), findsWidgets);
      await tester.tap(find.text('Butter').last);
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byType(CheckboxListTile));
      await tester.tap(find.byType(CheckboxListTile));
      await tester.tap(find.text('Accept breakfast order'));
      await tester.pumpAndSettle();
      final lines = rows(app.data['orders'][0]['lines']);
      expect(lines.map((l) => l['name']), ['Croissant', 'Butter']);
      expect(lines.map((l) => l['qty']), [2, 3]);
      expect(app.email.queue, isEmpty);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'Category accordion retains edits and rejects cross-category item drops',
    (tester) async {
      app.edit((data) {
        data['categories'].add({'id': 'drinks', 'name': 'Drinks', 'color': 7});
        data['items'].add({
          'id': 'coffee',
          'name': 'Coffee',
          'categoryId': 'drinks',
        });
      });
      await open(tester);
      await tester.tap(find.text('Settings'));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('edit-croissant')), findsOneWidget);
      expect(find.byKey(const ValueKey('edit-coffee')), findsNothing);
      final drop = tester.widget<DragTarget<String>>(
        find.byKey(const ValueKey('drop-bakery-end')),
      );
      final foreign = DragTargetDetails<String>(
        data: 'coffee',
        offset: Offset.zero,
      );
      expect(drop.onWillAcceptWithDetails!(foreign), isFalse);
      drop.onAcceptWithDetails!(foreign);
      await tester.enterText(
        find.byKey(const ValueKey('edit-croissant')),
        'Fresh croissant',
      );
      await tester.tap(find.byKey(const ValueKey('toggle-category-drinks')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('edit-croissant')), findsNothing);
      expect(find.byKey(const ValueKey('edit-coffee')), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('toggle-category-drinks')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('edit-coffee')), findsNothing);
      await tester.tap(find.byKey(const ValueKey('toggle-category-bakery')));
      await tester.pumpAndSettle();
      expect(find.text('Fresh croissant'), findsOneWidget);
      await tester.tap(find.text('Save all changes'));
      await tester.pumpAndSettle();
      expect(findById(app.data['items'], 'coffee')!['categoryId'], 'drinks');
      expect(
        findById(app.data['items'], 'croissant')!['name'],
        'Fresh croissant',
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('Menu sections and item drag order persist after saving', (
    tester,
  ) async {
    app.edit((data) {
      data['categories'].add({'id': 'drinks', 'name': 'Drinks', 'color': 7});
      data['items'].add({
        'id': 'coffee',
        'name': 'Coffee',
        'categoryId': 'drinks',
      });
    });
    await open(tester);
    await tester.tap(find.text('Settings'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('settings-section-0')));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<ReorderableListView>(
            find.byKey(const ValueKey('category-sections')),
          )
          .itemCount,
      2,
    );
    expect(find.byKey(const ValueKey('item-section-bakery')), findsOneWidget);
    expect(find.byKey(const ValueKey('item-section-drinks')), findsOneWidget);
    final drag = await tester.startGesture(
      tester.getCenter(find.byKey(const ValueKey('drag-item-butter'))),
    );
    await tester.pump();
    await drag.moveBy(const Offset(0, -25));
    await tester.pump(const Duration(milliseconds: 100));
    await drag.moveTo(
      tester.getTopLeft(find.byKey(const ValueKey('drop-bakery-croissant'))) +
          const Offset(80, 24),
    );
    await tester.pump(const Duration(milliseconds: 400));
    await drag.up();
    await tester.pumpAndSettle();
    expect(
      tester.getTopLeft(find.byKey(const ValueKey('edit-butter'))).dy,
      lessThan(
        tester.getTopLeft(find.byKey(const ValueKey('edit-croissant'))).dy,
      ),
    );
    await tester.ensureVisible(
      find.byKey(const ValueKey('drag-category-bakery')),
    );
    await tester.pumpAndSettle();
    final from = tester.getCenter(
      find.byKey(const ValueKey('drag-category-drinks')),
    );
    final categoryDrag = await tester.startGesture(from);
    await tester.pump();
    await categoryDrag.moveBy(const Offset(0, -25));
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.byKey(const ValueKey('edit-croissant')), findsNothing);
    expect(find.byKey(const ValueKey('edit-butter')), findsNothing);
    final target =
        tester.getCenter(find.byKey(const ValueKey('drag-category-bakery'))) +
        const Offset(0, -20);
    for (var step = 1; step <= 15; step++) {
      await categoryDrag.moveTo(Offset.lerp(from, target, step / 15)!);
      await tester.pump(const Duration(milliseconds: 30));
    }
    await tester.pump(const Duration(milliseconds: 400));
    final preview = tester.getRect(
      find.byKey(const ValueKey('category-drag-preview')),
    );
    expect(preview.top, lessThanOrEqualTo(target.dy));
    expect(preview.bottom, greaterThanOrEqualTo(target.dy));
    await categoryDrag.up();
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('edit-coffee')), findsOneWidget);
    await tester.tap(find.text('Save all changes'));
    await tester.pumpAndSettle();
    expect(rows(app.data['categories']).map((c) => c['id']), [
      'drinks',
      'bakery',
    ]);
    expect(
      rows(app.data['items'])
          .where((i) => i['categoryId'] == 'bakery')
          .map((i) => i['id']),
      ['butter', 'croissant'],
    );
    expect(app.store.loadOrders()['items'], app.data['items']);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'Check interval slider preserves saved values and retains changes in the settings draft',
    (tester) async {
      app.email.config['intervalMinutes'] = 137;
      await open(tester);
      await tester.tap(find.text('Settings'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Email'));
      await tester.pumpAndSettle();
      expect(find.text('Check every 137 minutes'), findsOneWidget);
      final slider = tester.widget<Slider>(
        find.byKey(const ValueKey('check-interval-slider')),
      );
      slider.onChanged!(4);
      await tester.pumpAndSettle();
      expect(find.text('Check every 5 minutes'), findsOneWidget);
      await tester.tap(find.byTooltip('Close'));
      await tester.pumpAndSettle();
      expect(app.settingsDraft['intervalMinutes'], '5');
      expect(app.email.interval, 137);
      await tester.tap(find.text('Settings'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Email'));
      await tester.pumpAndSettle();
      expect(find.text('Check every 5 minutes'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'Bulk categories prefer unused colors and rotate after the palette is full',
    (tester) async {
      await open(tester);
      final initial = rows(app.data['categories'])
          .map((c) => (c['color'] as num).toInt())
          .toList();
      await tester.tap(find.text('Settings'));
      await tester.pumpAndSettle();
      for (var i = 0; i < palette.length + 2; i++) {
        await tester.enterText(
          find.byKey(const ValueKey('add-categories')),
          'Extra $i',
        );
        await tester.testTextInput.receiveAction(TextInputAction.done);
        await tester.pumpAndSettle();
      }
      await tester.tap(find.text('Save all changes'));
      await tester.pumpAndSettle();
      final counts = List.filled(palette.length, 0);
      for (final color in initial) {
        counts[color]++;
      }
      int? previous;
      for (final category in rows(
        app.data['categories'],
      ).skip(initial.length)) {
        final color = (category['color'] as num).toInt();
        expect(color, isNot(previous));
        final least = counts.reduce((a, b) => a < b ? a : b);
        expect(counts[color], least);
        counts[color]++;
        previous = color;
      }
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'Dark mode applies immediately and persists independently of orders',
    (tester) async {
      await open(tester);
      final original = clone(app.data);
      expect(find.byKey(const ValueKey('last-update-time')), findsNothing);
      final heights = [
        tester.getSize(find.widgetWithText(FilledButton, 'Get orders')).height,
        tester.getSize(find.widgetWithText(OutlinedButton, 'Settings')).height,
        tester
            .getSize(find.widgetWithText(FilledButton, 'New order').first)
            .height,
        tester.getSize(find.widgetWithText(TextButton, 'Print')).height,
      ];
      expect(heights, everyElement(44));
      await tester.tap(find.text('Settings'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(SwitchListTile, 'Dark mode'));
      await tester.pumpAndSettle();
      expect(
        Theme.of(tester.element(find.text('Dark mode'))).brightness,
        Brightness.dark,
      );
      expect(app.data, original);
      final reopened = AppController(Store(dir));
      expect(reopened.darkMode, isTrue);
      reopened.dispose();
      await tester.tap(find.widgetWithText(SwitchListTile, 'Dark mode'));
      await tester.pumpAndSettle();
      expect(
        Theme.of(tester.element(find.text('Dark mode'))).brightness,
        Brightness.light,
      );
      expect(
        app.store.read('appearance-settings.json', {})['darkMode'],
        isFalse,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'New orders select an exact cabin and persist editable guest details',
    (tester) async {
      app.edit(
        (d) => d['safeCabins'] = [
          {'id': 'p', 'name': 'Panorama 1'},
          {'id': 'i', 'name': 'Igloo 1'},
        ],
      );
      await open(tester);
      await tester.tap(find.text('New order').first);
      await tester.pumpAndSettle();
      expect(find.widgetWithText(TextField, 'Accommodation'), findsNothing);
      await tester.tap(find.text('Save order'));
      await tester.pumpAndSettle();
      expect(app.data['orders'], isEmpty);
      await tester.tap(find.byKey(const ValueKey('order-cabin')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Igloo 1').last);
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('guest-name')),
        'Robin Guest',
      );
      await tester.enterText(
        find.byKey(const ValueKey('guest-email')),
        'guest@example.com',
      );
      await tester.enterText(
        find.byKey(const ValueKey('guest-phone')),
        '+31 6 12345678',
      );
      await tester.tap(
        find.byWidgetPredicate(
          (w) => w is IconButton && w.tooltip == 'Add one Croissant',
        ),
      );
      await tester.pump();
      await tester.tap(find.text('Save order'));
      await tester.pumpAndSettle();
      expect(app.data['orders'].length, 1);
      expect(app.data['orders'][0]['room'], 'Igloo 1');
      expect(DateTime.tryParse(app.data['orders'][0]['createdAt']), isNotNull);
      expect(find.text(orderDateLabel(app.data['orders'][0])), findsOneWidget);
      expect(app.data['orders'][0]['lines'][0]['qty'], 1);
      expect(app.data['safeCabins'].length, 2);
      expect(find.text('Igloo 1'), findsOneWidget);
      expect(app.data['orders'][0]['guest'], {
        'name': 'Robin Guest',
        'email': 'guest@example.com',
        'phone': '+31 6 12345678',
      });
      await tester.tap(find.byTooltip('Edit order for Igloo 1'));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<TextField>(find.byKey(const ValueKey('guest-name')))
            .controller!
            .text,
        'Robin Guest',
      );
      await tester.enterText(
        find.byKey(const ValueKey('guest-email')),
        'updated@example.com',
      );
      await tester.tap(find.text('Save order'));
      await tester.pumpAndSettle();
      expect(app.data['orders'][0]['guest']['email'], 'updated@example.com');
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'Category swatches open a color grid and entry widths match edits',
    (tester) async {
      await open(tester);
      await tester.tap(find.text('Settings'));
      await tester.pumpAndSettle();
      expect(
        tester.getSize(find.byKey(const ValueKey('add-categories'))).width,
        tester.getSize(find.byKey(const ValueKey('edit-bakery'))).width,
      );
      await tester.tap(find.byTooltip('Category color: Sky blue').last);
      await tester.pumpAndSettle();
      for (final color in colorNames) {
        expect(find.byTooltip(color), findsOneWidget);
      }
      await tester.tap(find.byTooltip('Peach'));
      await tester.pumpAndSettle();
      expect(find.byTooltip('Category color: Peach'), findsWidgets);
      expect(find.byTooltip('Peach'), findsNothing);
      await tester.tap(find.byKey(const ValueKey('settings-section-0')));
      await tester.pumpAndSettle();
      expect(
        tester.getSize(find.byKey(const ValueKey('add-items'))).width,
        tester.getSize(find.byKey(const ValueKey('edit-croissant'))).width,
      );
      await tester.tap(find.text('Save all changes'));
      await tester.pumpAndSettle();
      expect(app.data['categories'][0]['color'], 1);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets('Toolbar print and delete actions follow selection', (
    tester,
  ) async {
    app.edit(
      (d) => d['orders'] = [
        for (final room in ['8', '9'])
          {
            'id': room,
            'room': room,
            'slot': slots.first,
            'comment': '',
            'lines': [lineFor(d['items'][0], d['categories'][0], 1)],
          },
      ],
    );
    await open(tester);
    await tester.tap(find.byTooltip('Print options'));
    await tester.pumpAndSettle();
    expect(find.text('Orders only'), findsOneWidget);
    expect(find.text('All printouts'), findsNothing);
    expect(find.text('Items overview'), findsNothing);
    expect(find.text('Timetable'), findsOneWidget);
    await tester.tapAt(const Offset(5, 5));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(Checkbox).at(1));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Print options'));
    await tester.pumpAndSettle();
    expect(find.text('Print (1) orders'), findsOneWidget);
    expect(find.text('Orders only'), findsNothing);
    await tester.tapAt(const Offset(5, 5));
    await tester.pumpAndSettle();
    expect(find.text('Clear all orders'), findsNothing);
    await tester.tap(find.text('Delete selected (1)'));
    await tester.pumpAndSettle();
    expect(find.text('Delete 1 orders?'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(app.data['orders'].length, 2);
    await tester.tap(find.text('Delete selected (1)'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
    await tester.pumpAndSettle();
    expect(app.data['orders'].length, 1);
    expect(app.data['orders'][0]['room'], '9');
    expect(find.text('Delete selected (1)'), findsNothing);
    await tester.tap(find.text('Clear all orders'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
    await tester.pumpAndSettle();
    expect(app.data['orders'], isEmpty);
    await tester.tap(find.text('Settings'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('settings-section-3')));
    await tester.pumpAndSettle();
    expect(find.text('Back up data'), findsOneWidget);
    expect(find.text('Restore data'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  testWidgets(
    'Editing preserves unavailable quantities, email metadata and removed items',
    (tester) async {
      app.edit((d) {
        d['items'][0]['available'] = false;
        d['orders'] = [
          {
            'id': 'order',
            'room': '8',
            'slot': slots.first,
            'comment': 'Note',
            'emailSource': {'key': 'source-key'},
            'lines': [
              lineFor(d['items'][0], d['categories'][0], 2),
              {
                'itemId': 'gone',
                'name': 'Removed item',
                'qty': 3,
                'categoryId': 'old',
                'categoryName': 'Old',
                'categoryColor': 4,
              },
            ],
          },
        ];
      });
      await open(tester);
      await tester.tap(find.byTooltip('Edit order for 8'));
      await tester.pumpAndSettle();
      expect(find.widgetWithText(TextField, 'Accommodation'), findsNothing);
      await tester.tap(find.byKey(const ValueKey('order-cabin')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('9').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Save order'));
      await tester.pumpAndSettle();
      expect(app.data['orders'][0]['emailSource']['key'], 'source-key');
      expect(app.data['orders'][0]['lines'].length, 2);
      expect(app.data['orders'][0]['lines'][0]['qty'], 2);
      expect(app.data['orders'][0]['room'], '9');
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'Pending emails remain outside accepted orders and require safe cabin',
    (tester) async {
      app.email.imports['queue'] = [
        {
          'id': 'e',
          'kind': 'breakfast',
          'room': 'Guest cabin',
          'slot': slots.first,
          'comment': 'Outside',
          'lines': [
            {'name': 'Croissant', 'qty': 2},
          ],
          'warnings': [],
          'key': 'mail-key',
        },
      ];
      await open(tester);
      expect(find.text('Orders · 0'), findsOneWidget);
      expect(find.text('Pending orders · 1'), findsOneWidget);
      final button = tester.widget<IconButton>(
        find.byWidgetPredicate(
          (w) => w is IconButton && w.tooltip == 'Accept breakfast order',
        ),
      );
      expect(button.onPressed, isNull);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'Menu dialog supports bulk edit without changing existing data on cancel',
    (tester) async {
      await open(tester);
      await tester.tap(find.text('Settings'));
      await tester.pumpAndSettle();

      await tester.pumpAndSettle();
      await tester.enterText(
        find.widgetWithText(TextField, 'Category name'),
        'Changed',
      );
      await tester.tap(find.byKey(const ValueKey('settings-section-2')));
      await tester.pumpAndSettle();
      expect(find.widgetWithText(TextField, 'IMAP server'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('settings-section-0')));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<TextField>(find.byKey(const ValueKey('edit-bakery')))
            .controller!
            .text,
        'Changed',
      );
      await tester.tap(find.byTooltip('Close'));
      await tester.pumpAndSettle();
      expect(app.data['categories'][0]['name'], 'Bakery');
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'Email settings retain draft fields but clear the password on close',
    (tester) async {
      await open(tester);
      await tester.tap(find.text('Settings'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Email'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.widgetWithText(TextField, 'IMAP server'),
        'imap.example.com',
      );
      await tester.enterText(
        find.widgetWithText(TextField, 'Password or app password'),
        'secret',
      );
      await tester.tap(find.byTooltip('Close'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Settings'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Email'));
      await tester.pumpAndSettle();
      expect(find.text('imap.example.com'), findsOneWidget);
      expect(find.text('secret'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'Enter adds repeated menu entries and retains focus and category',
    (tester) async {
      await open(tester);
      await tester.tap(find.text('Settings'));
      await tester.pumpAndSettle();

      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('settings-section-0')));
      await tester.pumpAndSettle();
      final input = find.byKey(const ValueKey('add-items'));
      for (final name in ['Toast', 'Jam']) {
        await tester.enterText(input, name);
        await tester.testTextInput.receiveAction(TextInputAction.done);
        await tester.pumpAndSettle();
        final field = tester.widget<TextField>(input);
        expect(field.controller!.text, isEmpty);
        expect(field.focusNode!.hasFocus, isTrue);
        expect(find.text(name), findsOneWidget);
      }
      await tester.enterText(input, '  toast  ');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();
      expect(
        find.text('This name already exists in this category.'),
        findsOneWidget,
      );
      await tester.enterText(input, '');
      await tester.tap(find.text('Save all changes'));
      await tester.pumpAndSettle();
      expect(rows(app.data['items']).map((e) => e['name']), [
        'Croissant',
        'Butter',
        'Toast',
        'Jam',
      ]);
      expect(
        rows(app.data['items']).every((e) => e['categoryId'] == 'bakery'),
        isTrue,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'Matched cabin is preselected and contact survives quick acceptance and editing',
    (tester) async {
      app.edit((d) => d['safeCabins'].add({'id': 'oak', 'name': 'Cabin Oak'}));
      app.email.imports['queue'] = [
        {
          'id': 'contact',
          'key': 'contact-key',
          'kind': 'breakfast',
          'room': 'cabin OAK',
          'slot': slots.first,
          'comment': '',
          'warnings': [],
          'lines': [
            {'name': 'Croissant', 'qty': 1},
          ],
          'guest': {
            'name': 'Sam',
            'email': 'sam@example.com',
            'phone': '+31 123',
          },
        },
      ];
      await open(tester);
      expect(find.text('Sam'), findsOneWidget);
      expect(find.text('sam@example.com'), findsOneWidget);
      expect(find.text('+31 123'), findsOneWidget);
      expect(find.text('cabin OAK'), findsOneWidget);
      expect(find.byKey(const ValueKey('cabin-contact-oak')), findsOneWidget);
      await tester.tap(find.byTooltip('Accept breakfast order'));
      await tester.pumpAndSettle();
      expect(app.email.queue, isEmpty);
      expect(app.data['orders'][0]['room'], 'Cabin Oak');
      expect(find.text('Sam'), findsOneWidget);
      expect(find.text('sam@example.com'), findsOneWidget);
      expect(find.text('+31 123'), findsOneWidget);
      await tester.tap(find.byTooltip('Expand order Cabin Oak'));
      await tester.pumpAndSettle();
      expect(find.text('sam@example.com'), findsOneWidget);
      await tester.tap(find.byTooltip('Edit order for Cabin Oak'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Save order'));
      await tester.pumpAndSettle();
      expect(app.data['orders'][0]['guest']['email'], 'sam@example.com');
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'Expressive controls retain search focus and work with reduced motion',
    (tester) async {
      tester.platformDispatcher.accessibilityFeaturesTestValue =
          const FakeAccessibilityFeatures(disableAnimations: true);
      addTearDown(
        tester.platformDispatcher.clearAccessibilityFeaturesTestValue,
      );
      await open(tester);
      await tester.tap(find.text('New order').first);
      await tester.pumpAndSettle();
      final search = find.widgetWithText(
        TextField,
        'Search items or categories',
      );
      await tester.enterText(search, 'Croissant');
      await tester.tap(
        find.byWidgetPredicate(
          (w) => w is IconButton && w.tooltip == 'Add one Croissant',
        ),
      );
      await tester.pumpAndSettle();
      final field = tester.widget<TextField>(search);
      expect(field.focusNode!.hasFocus, true);
      expect(
        field.controller!.selection,
        const TextSelection(baseOffset: 0, extentOffset: 9),
      );
      await tester.tap(find.byTooltip('Remove one Croissant'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('order-cabin')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('8').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Save order'));
      await tester.pumpAndSettle();
      expect(app.data['orders'][0]['lines'], isEmpty);
      await tester.tap(find.byTooltip('Expand order 8'));
      await tester.pump();
      expect(find.byTooltip('Collapse order 8'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}
