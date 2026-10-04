import 'package:enough_mail/enough_mail.dart';

import '../model.dart';

abstract class MailTransport {
  Future<void> connect(Json config, String password);
  Future<List<String>> folders();
  Future<Json> examine(String folder);
  Future<List<int>> search(String criteria);
  Future<List<MimeMessage>> metadata(List<int>? uids);
  Future<MimeMessage?> body(int uid);
  Future<void> close();
}

class ImapTransport implements MailTransport {
  final ImapClient client = ImapClient(
    isLogEnabled: false,
    defaultResponseTimeout: const Duration(seconds: 30),
    defaultWriteTimeout: const Duration(seconds: 15),
  );
  @override
  Future<void> connect(Json config, String password) async {
    await client
        .connectToServer(config['host'], config['port'], isSecure: true)
        .timeout(const Duration(seconds: 15));
    await client.login(config['user'], password);
  }

  @override
  Future<List<String>> folders() async =>
      (await client.listMailboxes(recursive: true))
          .where((m) => !m.isNotSelectable)
          .map((m) => m.path)
          .toList();
  @override
  Future<Json> examine(String folder) async {
    final available = await client.listMailboxes(recursive: true);
    final mailbox = available
        .where((m) => m.path == folder && !m.isNotSelectable)
        .firstOrNull;
    if (mailbox == null) {
      throw StateError(
        'The selected folder is unavailable. Choose it from the folder list.',
      );
    }
    final box = await client.examineMailbox(mailbox);
    return {'uidValidity': box.uidValidity, 'exists': box.messagesExists};
  }

  @override
  Future<List<int>> search(String criteria) async =>
      (await client.uidSearchMessages(
        searchCriteria: criteria,
        responseTimeout: const Duration(seconds: 30),
      )).matchingSequence?.toList() ??
      [];
  @override
  Future<List<MimeMessage>> metadata(List<int>? uids) async {
    if (uids != null && uids.isEmpty) return [];
    final result = uids == null
        ? await client.fetchMessages(
            MessageSequence.fromAll(),
            '(UID RFC822.SIZE INTERNALDATE)',
          )
        : await client.uidFetchMessages(
            MessageSequence.fromIds(uids, isUid: true),
            '(UID RFC822.SIZE INTERNALDATE)',
          );
    return result.messages;
  }

  @override
  Future<MimeMessage?> body(int uid) async => (await client.uidFetchMessage(
    uid,
    '(UID INTERNALDATE BODY.PEEK[])',
  )).messages.firstOrNull;
  @override
  Future<void> close() async {
    try {
      await client.logout().timeout(const Duration(seconds: 3));
    } catch (_) {
      await client.disconnect();
    }
  }
}

DateTime? receiptDate(String? text) {
  if (text == null) return null;
  final m = RegExp(
    r'(\d{1,2})-([A-Za-z]{3})-(\d{4}) (\d{2}):(\d{2}):(\d{2}) ([+-])(\d{2})(\d{2})',
  ).firstMatch(text);
  if (m == null) return null;
  final month =
      [
        'jan',
        'feb',
        'mar',
        'apr',
        'may',
        'jun',
        'jul',
        'aug',
        'sep',
        'oct',
        'nov',
        'dec',
      ].indexOf(m[2]!.toLowerCase()) +
      1;
  if (month == 0) return null;
  final offset =
      (int.parse(m[8]!) * 60 + int.parse(m[9]!)) * (m[7] == '-' ? -1 : 1);
  return DateTime.utc(
    int.parse(m[3]!),
    month,
    int.parse(m[1]!),
    int.parse(m[4]!),
    int.parse(m[5]!),
    int.parse(m[6]!),
  ).subtract(Duration(minutes: offset));
}
