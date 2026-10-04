import 'browser.dart';

import 'dart:convert';
import 'dart:io';

import 'package:html/parser.dart' as html;

import '../model.dart';

class EmailPreview {
  static String document(Json entry) {
    final markup = '${entry['html'] ?? ''}';
    final doc = html.parse(
      markup.isEmpty
          ? '<p>HTML was not saved for this email. Showing its saved text.</p><pre>${const HtmlEscape().convert('${entry['text'] ?? ''}')}</pre>'
          : markup,
    );
    // Keep email layout and inline styling, but never active content or remote
    // resources (including tracking pixels). CSP is a second layer of protection.
    for (final node in doc.querySelectorAll(
      'script,iframe,frame,frameset,object,embed,applet,base,link,meta,form,input,button,textarea,select,svg,math,audio,video,source',
    )) {
      node.remove();
    }
    const attributes = {
      'style',
      'class',
      'id',
      'title',
      'alt',
      'width',
      'height',
      'align',
      'valign',
      'bgcolor',
      'color',
      'border',
      'cellpadding',
      'cellspacing',
      'colspan',
      'rowspan',
      'dir',
      'lang',
    };
    for (final node in doc.querySelectorAll('*')) {
      node.attributes.removeWhere(
        (key, value) => !attributes.contains(key.toString().toLowerCase()),
      );
    }
    final styles =
        doc.head
            ?.querySelectorAll('style')
            .map((e) => e.outerHtml)
            .join('\n') ??
        '';
    return '''<!doctype html><html><head><meta charset="utf-8">
<meta http-equiv="Content-Security-Policy" content="default-src 'none'; script-src 'none'; style-src 'unsafe-inline'; img-src 'none'; base-uri 'none'; form-action 'none'">
<meta name="referrer" content="no-referrer"><title>Breakfast Orders — Email</title>
<style>body{font:15px 'Segoe UI',sans-serif;margin:24px;color:#172c26}pre{white-space:pre-wrap;overflow-wrap:anywhere}img{max-width:100%}</style>$styles</head>
${doc.body?.outerHtml ?? '<body></body>'}</html>''';
  }

  static Future<void> show(Json entry) async {
    final directory = Directory(
      '${Directory.systemTemp.path}/Breakfast-Orders-Email-Previews',
    )..createSync(recursive: true);
    final file = File('${directory.path}/email-${newId()}.html');
    await file.writeAsString(document(entry));
    for (final old in directory.listSync().whereType<File>()) {
      if (RegExp(r'email-[a-f0-9-]+\.html$').hasMatch(old.path) &&
          DateTime.now().difference(old.statSync().modified).inDays > 1) {
        try {
          old.deleteSync();
        } catch (_) {}
      }
    }
    await openPreview(file, purpose: 'show email');
  }
}
