import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:enough_mail/enough_mail.dart';
import 'package:html/parser.dart' as html;

import '../model.dart';

const defaultSender = 'noreply@e.maildigitalguest.com';

/// Read only the labelled guest section, never the notification sender.
Json parseGuest(String text) {
  final sections = text.split(RegExp('Guest Info', caseSensitive: false));
  if (sections.length < 2) return {};
  final section = sections[1];
  String field(String label) =>
      RegExp(
        '\\b(?:$label)\\s*:[ \\t]*([^\\n]*?)(?=\\s+(?:Name|E-?mail|Phone(?: number)?|Telephone|Mobile|Room|Res No\\.?|Reservation(?: number| no\\.?)?|Total)\\b|\\n|\$)',
        caseSensitive: false,
      ).firstMatch(section)?[1]?.trim() ??
      '';
  return {
    'name': field('Name'),
    'email': field('E-?mail'),
    'phone': field('Phone(?: number)?|Telephone|Mobile'),
    if (field(r'Res No\.?|Reservation(?: number| no\.?)?').isNotEmpty)
      'reservation': field(r'Res No\.?|Reservation(?: number| no\.?)?'),
  };
}

String sourceText(Json entry) =>
    '${entry['text'] ?? entry['emailSource']?['text'] ?? ''}';
Json guestDetails(Json entry) {
  final saved = entry['guest'] is Json ? entry['guest'] as Json : null;
  if (saved == null) return parseGuest(sourceText(entry));
  if (saved.containsKey('reservation')) return saved;
  final reservation = parseGuest(sourceText(entry))['reservation'];
  return {...saved, 'reservation': ?reservation};
}

// Repair only the known reservation spillover in older pending imports.
String guestCabin(Json entry) {
  final room = '${entry['room'] ?? ''}';
  return room
      .split(
        RegExp(
          r'\s+(?:Res No\.?|Reservation(?: number| no\.?)?)\s*:',
          caseSensitive: false,
        ),
      )
      .first
      .trim();
}

Json? parseTime(String text) {
  final m = RegExp(r'^(\d{1,2})[.:](\d{2})\s*[-–—]\s*(\d{1,2})[.:](\d{2})$')
      .firstMatch(text.trim());
  if (m == null) return null;
  final n = List.generate(4, (i) => int.parse(m[i + 1]!));
  if (n[0] > 23 || n[2] > 23 || n[1] > 59 || n[3] > 59) return null;
  return {
    'slot':
        '${n[0].toString().padLeft(2, '0')}:${m[2]}–${n[2].toString().padLeft(2, '0')}:${m[4]}',
    'start': n[0] * 60 + n[1],
  };
}

String htmlText(String source) {
  final document = html.parse(
    source
        .replaceAll(RegExp(r'</t[dh]\s*>', caseSensitive: false), ' ')
        .replaceAll(RegExp(r'<br\s*/?>', caseSensitive: false), '\n')
        .replaceAll(
          RegExp(r'</(?:p|div|tr|li|h[1-6])\s*>', caseSensitive: false),
          '\n\n',
        ),
  );
  for (final node in document.querySelectorAll('script,style')) {
    node.remove();
  }
  return document.body?.text ?? '';
}

Json parseOrderEmail(String source, [String sender = defaultSender]) =>
    parseMessage(MimeMessage.parseFromText(source), sender, source: source);
Json parseMessage(MimeMessage mail, String sender, {String? source}) {
  if (!(mail.from ?? []).any((a) => normalize(a.email) == normalize(sender)) ||
      normalize(mail.decodeSubject()) != 'order request received') {
    return {'kind': 'ignore', 'reason': 'Other email'};
  }
  final markup = mail.decodeTextHtmlPart();
  var text = (mail.decodeTextPlainPart() ?? htmlText(markup ?? '')).replaceAll(
    '\r',
    '',
  );
  if (text.length > 150000) text = text.substring(0, 150000);
  final raw = mail.mimeData;
  final originalBytes = source != null
      ? utf8.encode(source)
      : raw is BinaryMimeData
      ? raw.data
      : utf8.encode(raw is TextMimeData ? raw.text : mail.renderMessage());
  final messageId =
      mail.getHeaderValue('message-id') ??
      sha256.convert(originalBytes).toString();
  final base = <String, dynamic>{
    'room': '',
    'slot': '',
    'comment': '',
    'lines': <Json>[],
    'warnings': <String>[],
    'text': text,
    if (markup != null && markup.trim().isNotEmpty) 'html': markup,
    'guest': parseGuest(text),
    'subject': mail.decodeSubject(),
    'receivedAt': mail.decodeDate()?.toUtc().toIso8601String(),
    'messageId': messageId,
  };
  if (!RegExp('New Order Request', caseSensitive: false).hasMatch(text)) {
    return {
      ...base,
      'kind': 'review',
      'warnings': [
        'The DigitalGuest format was not recognized. Check the source email.',
      ],
    };
  }
  final parts = text.split(
    RegExp(r'Request received at:[^\n]*(?:\n|$)', caseSensitive: false),
  );
  final section = parts.length > 1
      ? parts[1]
            .split(
              RegExp(
                r'Order comment|Guest Info|\n\s*Total\b',
                caseSensitive: false,
              ),
            )
            .first
      : '';
  final lines = <Json>[], times = <Json>[];
  for (final raw in section.split('\n')) {
    final match = RegExp(
      r'^(\d+)\s*[x×]\s+(.+?)(?:\s+\d+[.,]\d{2}\s+[A-Z]{3})?\s*$',
    ).firstMatch(raw.trim());
    if (match == null) continue;
    final qty = int.tryParse(match[1]!) ?? 0, name = match[2]!.trim();
    if (qty < 1 || qty > 10000) continue;
    final time = parseTime(name);
    if (time != null) {
      times.add(time);
    } else {
      lines.add({'name': name, 'qty': qty});
    }
  }
  final dinner = RegExp(
    r'^(?:Dinner|Evening meal)(?: order)?\s*:?\s*$',
    multiLine: true,
    caseSensitive: false,
  ).hasMatch(section);
  final breakfast = RegExp(
    r'^Breakfast(?: order)?\s*:?\s*$',
    multiLine: true,
    caseSensitive: false,
  ).hasMatch(section);
  if ((dinner && !breakfast) ||
      (!breakfast &&
          times.isNotEmpty &&
          times.every((t) => t['start'] >= 660))) {
    return {'kind': 'ignore', 'reason': 'Dinner order'};
  }
  final slot = times.length == 1 && slots.contains(times[0]['slot'])
      ? times[0]['slot'] as String
      : '';
  final warnings = <String>[];
  if (slot.isEmpty) {
    warnings.add(
      'No single supported breakfast delivery slot was found. Confirm this is breakfast and choose its delivery time.',
    );
  }
  final guest = text.split(RegExp('Guest Info', caseSensitive: false));
  final room =
      RegExp(
        r'\bRoom:\s*([^\n]+?)(?=\s+(?:Name|Email|Phone|Res No\.?|Reservation(?: number| no\.?)?|Total)\b|\n|$)',
        caseSensitive: false,
      ).firstMatch(guest.length > 1 ? guest[1] : '')?[1]?.trim() ??
      '';
  if (room.isEmpty) warnings.add('Accommodation number is missing.');
  if (lines.isEmpty) {
    warnings.add('No order items could be read. Check the source email.');
  }
  var comment =
      RegExp(
        r'Order comment\s*([\s\S]*?)Guest Info',
        caseSensitive: false,
      ).firstMatch(text)?[1]?.trim() ??
      '';
  if (normalize(comment) == 'no comment') comment = '';
  final requestId = RegExp(r'[?&](?:amp;)?requestId=([a-zA-Z0-9_-]+)')
      .firstMatch(markup ?? text)?[1];
  return {
    ...base,
    'kind': slot.isNotEmpty && !dinner ? 'breakfast' : 'review',
    'room': room,
    'slot': slot,
    'comment': comment,
    'lines': lines,
    'warnings': warnings,
    'requestId': ?requestId,
  };
}
