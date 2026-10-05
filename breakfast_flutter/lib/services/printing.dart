import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';

import '../model.dart';
import 'browser.dart';

class Printing {
  static Future<String> document(
    Json data,
    String mode,
    Set<String> selected,
  ) async {
    final css = await rootBundle.loadString('assets/print/layout.css');
    final renderer = await rootBundle.loadString('assets/print/render.js');
    final layout = await rootBundle.loadString('assets/print/print-layout.js');
    final payload =
        jsonEncode({
              ...data,
              'orders': [
                for (final order in rows(data['orders']))
                  {
                    'id': order['id'],
                    'room': order['room'],
                    'slot': order['slot'],
                    'comment': order['comment'],
                    'lines': orderedOrderLines(data, order),
                  },
              ],
              'printMode': mode,
              'printSelection': selected.toList(),
            })
            .replaceAll('<', r'\u003c')
            .replaceAll('>', r'\u003e')
            .replaceAll('&', r'\u0026');
    return '''<!doctype html><html><head><meta charset="utf-8"><title>Breakfast Orders — Print</title><style>$css
@media screen {html,body{margin:0;background:#edf3f6;font-family:'Segoe UI',sans-serif}.browserbar{min-height:100vh;display:grid;place-items:center}.browserbar button{padding:14px 24px;border:0;border-radius:8px;background:#0b647b;color:white;font:600 16px 'Segoe UI',sans-serif;cursor:pointer}.browserbar button:disabled{opacity:.5}#printArea{position:absolute;left:-100000px;top:0;visibility:hidden}}
@media print {#printArea{position:static!important;left:auto;top:auto;width:auto;visibility:visible!important;pointer-events:auto}.browserbar{display:none!important}.printpage{margin:0}body{background:white}}
</style></head><body><div class="browserbar"><button onclick="window.print()" id="browserPrint" disabled>Preparing…</button></div><div id="printArea" class="print"></div><script type="application/json" id="order-data">$payload</script><script>$renderer\n$layout
window.addEventListener('afterprint',()=>window.close());
window.addEventListener('load',async()=>{try{await document.fonts.ready;paginateOrderSlips();paginateTotals();paginateTimetable();document.getElementById('browserPrint').disabled=false;document.getElementById('browserPrint').textContent='Print / Save PDF';requestAnimationFrame(()=>requestAnimationFrame(()=>window.print()))}catch(error){document.getElementById('browserPrint').textContent='Could not prepare print pages: '+error.message}},{once:true});</script></body></html>''';
  }

  static Future<File> prepare(
    Json data,
    String mode,
    Set<String> selected,
  ) async {
    if (rows(data['orders']).isEmpty) {
      throw StateError('Add at least one order first.');
    }
    if (mode == 'selected' && selected.isEmpty) {
      throw StateError('Select at least one order first.');
    }
    final directory = Directory(
      '${Directory.systemTemp.path}/Breakfast-Orders-Flutter-Print-Previews',
    )..createSync(recursive: true);
    final file = File(
      '${directory.path}/Breakfast-Orders-${DateTime.now().millisecondsSinceEpoch}.html',
    );
    await file.writeAsString(await document(data, mode, selected));
    for (final old in directory.listSync().whereType<File>()) {
      if (RegExp(r'Breakfast-Orders-\d+\.html$').hasMatch(old.path) &&
          DateTime.now().difference(old.statSync().modified).inDays > 7) {
        try {
          old.deleteSync();
        } catch (_) {}
      }
    }
    return file;
  }

  static Future<void> print(
    Json data,
    String mode,
    Set<String> selected,
  ) async {
    final file = await prepare(data, mode, selected);
    await openPreview(file, purpose: 'print');
  }
}
