import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:breakfast_orders/services/mail_transport.dart';
import 'package:breakfast_orders/services/email_service.dart';
import 'package:breakfast_orders/services/store.dart';
import 'package:breakfast_orders/model.dart';

import 'fixtures.dart';

class LoopbackTransport extends ImapTransport {
  LoopbackTransport(this.port);
  final int port;
  @override
  Future<void> connect(Json config, String password) async {
    await client.connectToServer('127.0.0.1', port, isSecure: false);
    await client.login('test@example.com', 'test-only');
  }
}

void main() {
  for (final refuseMetadata in [false, true]) {
    test('Real Dart IMAP client: SEARCH rejected, metadata ${refuseMetadata ? 'rejected' : 'read-only fallback'}', () async {
      final dir = Directory.systemTemp.createTempSync('breakfast-wire-');
      final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      final sockets = <Socket>[], commands = <String>[];
      final bytes = utf8.encode(source());
      server.listen((socket) {
        sockets.add(socket);
        socket.write('* OK Test server ready\r\n');
        var pending = '';
        socket.listen((data) {
          pending += utf8.decode(data);
          while (pending.contains('\r\n')) {
            final end = pending.indexOf('\r\n'),
                line = pending.substring(0, end);
            pending = pending.substring(end + 2);
            final space = line.indexOf(' ');
            if (space < 0) continue;
            final tag = line.substring(0, space),
                command = line.substring(space + 1);
            if (!command.startsWith('LOGIN')) commands.add(command);
            if (command.startsWith('CAPABILITY')) {
              socket.write(
                '* CAPABILITY IMAP4rev1\r\n$tag OK Capabilities\r\n',
              );
            } else if (command.startsWith('LOGIN')) {
              socket.write('$tag OK Logged in\r\n');
            } else if (command.startsWith('LIST')) {
              socket.write(
                '* LIST () "/" "INBOX/DIGITAL GUEST"\r\n$tag OK Listed\r\n',
              );
            } else if (command.startsWith('EXAMINE')) {
              socket.write(
                '* FLAGS (\\Seen)\r\n* 2 EXISTS\r\n* OK [UIDVALIDITY 10] UIDs valid\r\n* OK [UIDNEXT 103] Next UID\r\n$tag OK [READ-ONLY] Opened\r\n',
              );
            } else if (command.contains('SEARCH')) {
              socket.write('$tag NO Search rejected\r\n');
            } else if (command.startsWith('FETCH')) {
              if (refuseMetadata) {
                socket.write('$tag NO Metadata access rejected\r\n');
              } else {
                socket.write(
                  '* 1 FETCH (UID 101 RFC822.SIZE ${bytes.length} INTERNALDATE "01-Oct-2026 08:00:00 +0000")\r\n* 2 FETCH (UID 102 RFC822.SIZE ${bytes.length} INTERNALDATE "29-Sep-2026 08:00:00 +0000")\r\n$tag OK Metadata fetched\r\n',
                );
              }
            } else if (command.startsWith('UID FETCH 101')) {
              socket.write(
                '* 1 FETCH (UID 101 INTERNALDATE "01-Oct-2026 08:00:00 +0000" BODY[] {${bytes.length}}\r\n',
              );
              socket.add(bytes);
              socket.write(')\r\n$tag OK Message fetched\r\n');
            } else if (command.startsWith('LOGOUT')) {
              socket.write('* BYE Goodbye\r\n$tag OK Logout\r\n');
              socket.close();
            } else {
              socket.write('$tag BAD Unsupported test command\r\n');
            }
          }
        });
      });
      Json data = fixture();
      final service = EmailService(
        Store(dir),
        readOrders: () => data,
        writeOrders: (d) => data = d,
        transport: () => LoopbackTransport(server.port),
        now: () => DateTime(2026, 10, 1, 12),
        encrypt: (s) async => s,
        decrypt: (s) async => s,
      );
      addTearDown(() async {
        service.dispose();
        for (final s in sockets) {
          s.destroy();
        }
        await server.close();
        dir.deleteSync(recursive: true);
      });
      await service.saveSettings({
        'host': 'imap.example.com',
        'port': 993,
        'user': 'test@example.com',
        'password': 'test-only',
        'folder': 'INBOX/DIGITAL GUEST',
        'enabled': false,
      });
      await service.check();
      if (refuseMetadata) {
        expect(service.error, true);
        expect(service.message, contains('Metadata access rejected'));
        expect(service.imports['seen'], isEmpty);
      } else {
        expect(service.error, false, reason: service.message);
        expect(service.queue.length, 1);
        expect(service.queue.first['room'], '8');
        expect(commands.any((c) => c.contains('BODY.PEEK[]')), true);
        expect(
          commands.any(
            (c) => RegExp(r'^(SELECT|.*STORE|.*MOVE|.*EXPUNGE)').hasMatch(c),
          ),
          false,
        );
        expect(commands.any((c) => c.startsWith('UID FETCH 102')), false);
        await service.check();
        expect(commands.where((c) => c.startsWith('UID FETCH 101')).length, 1);
      }
    }, timeout: const Timeout(Duration(seconds: 20)));
  }
}
