import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:enough_mail/enough_mail.dart';
import 'package:breakfast_orders/model.dart';
import 'package:breakfast_orders/services/store.dart';
import 'package:breakfast_orders/services/email_service.dart';
import 'package:breakfast_orders/services/mail_transport.dart';
import 'package:breakfast_orders/ui/reimport_orders.dart';

import 'fixtures.dart';

class RecoveryMail implements MailTransport {
  final messages = [
    for (var i = 1; i <= 3; i++)
      MimeMessage.parseFromText(source(id: 'recovery-$i'))
        ..uid = i
        ..internalDate = i == 3
            ? '30-Sep-2026 08:00:00 +0000'
            : '01-Oct-2026 08:00:00 +0000'
        ..size = 1024,
  ];
  @override
  Future<void> connect(Json config, String password) async {}
  @override
  Future<List<String>> folders() async => ['INBOX'];
  @override
  Future<Json> examine(String folder) async => {
    'uidValidity': 1,
    'exists': messages.length,
  };
  @override
  Future<List<int>> search(String criteria) async =>
      messages.map((m) => m.uid!).toList();
  @override
  Future<List<MimeMessage>> metadata(List<int>? uids) async =>
      messages.where((m) => uids == null || uids.contains(m.uid)).toList();
  @override
  Future<MimeMessage?> body(int uid) async =>
      messages.where((m) => m.uid == uid).firstOrNull;
  @override
  Future<void> close() async {}
}

void main() {
  late Directory directory;
  late EmailService email;
  late Json data;
  setUp(() async {
    directory = Directory.systemTemp.createTempSync('breakfast-reimport-');
    data = fixture();
    final mail = RecoveryMail();
    email = EmailService(
      Store(directory),
      readOrders: () => data,
      writeOrders: (value) => data = value,
      transport: () => mail,
      now: () => DateTime(2026, 10, 1, 12),
      encrypt: (s) async => s,
      decrypt: (s) async => s,
    );
    await email.saveSettings({
      'host': 'imap.example.com',
      'user': 'orders@example.com',
      'password': 'test',
      'folder': 'INBOX',
      'enabled': false,
    });
  });
  tearDown(() {
    email.dispose();
    directory.deleteSync(recursive: true);
  });

  Future<void> open(WidgetTester tester) async {
    tester.view.physicalSize = const Size(800, 600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => FilledButton(
              onPressed: () => showDialog<int>(
                context: context,
                builder: (_) => ReimportOrders(email),
              ),
              child: const Text('Open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
  }

  testWidgets(
    'Reimport picker disables existing orders and imports a selected order',
    (tester) async {
      final candidates = await email.reimportCandidates(email.now());
      data['orders'] = <Json>[
        {
          'emailSource': {'key': candidates.first['key']},
        },
      ];
      await open(tester);
      expect(find.text('Already in orders'), findsOneWidget);
      final boxes = tester
          .widgetList<CheckboxListTile>(find.byType(CheckboxListTile))
          .toList();
      expect(boxes.where((box) => box.onChanged == null), hasLength(1));
      await tester.tap(
        find.byKey(ValueKey('reimport-${candidates.last['key']}')),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Import selected (1)'));
      await tester.pumpAndSettle();
      expect(email.queue, hasLength(1));
      expect(email.queue.single['key'], candidates.last['key']);
      expect(data['orders'], hasLength(1));
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('Date picker can import just one order from an earlier day', (
    tester,
  ) async {
    await open(tester);
    await tester.tap(find.byKey(const ValueKey('reimport-date')));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Previous month'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('30'));
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();
    expect(find.byType(CheckboxListTile), findsOneWidget);
    await tester.tap(find.byType(CheckboxListTile));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Import selected (1)'));
    await tester.pumpAndSettle();
    expect(email.queue, hasLength(1));
    expect(email.queue.single['receivedAt'], '2026-09-30T08:00:00.000Z');
    expect(tester.takeException(), isNull);
  });
}
