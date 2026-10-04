import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';

import '../model.dart';
import 'email_parser.dart';
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
                  {...order, 'guest': guestDetails(order)},
              ],
              'printMode': mode,
              'printSelection': selected.toList(),
            })
            .replaceAll('<', r'\u003c')
            .replaceAll('>', r'\u003e')
            .replaceAll('&', r'\u0026');
    return '''<!doctype html><html><head><meta charset="utf-8"><title>Breakfast Orders — Print</title><style>$css
@media screen {html,body{background:#edf3f6;margin:0;min-height:100%;font-family:'Segoe UI',system-ui;color:#142f43}.browserbar{position:sticky;top:0;z-index:1;display:flex;flex-wrap:wrap;align-items:center;justify-content:space-between;gap:12px;padding:16px 24px;background:#d4eaf0;border-bottom:1px solid #cedce4}.browserbar h1{font-size:24px;margin:0}.browserbar p{font-size:14px;margin:0;max-width:650px}.browserbar button{cursor:pointer;min-height:44px;padding:10px 20px;border:0;border-radius:28px;background:#0b647b;color:white;font:600 14px 'Segoe UI',system-ui}.browserbar button:disabled{opacity:.5;cursor:wait}.browserbar button:focus-visible{outline:3px solid #0b647b;outline-offset:3px}#printArea{position:static;visibility:visible;width:max-content;min-width:100%}.printpage{background:white;margin:20px auto!important;box-shadow:0 3px 18px #142f4320}}

@media print {#printArea{position:static!important;left:auto;top:auto;width:auto;visibility:visible!important;pointer-events:auto}.browserbar{display:none!important}.printpage{margin:0}body{background:white}}
</style></head><body><div class="browserbar"><h1>Breakfast orders</h1><p id="printMessage">Preparing your print pages…</p><button onclick="window.print()" id="browserPrint" disabled>Preparing…</button></div><div id="printArea" class="print"></div><script type="application/json" id="order-data">$payload</script><script>$renderer\n$layout
window.addEventListener('load',async()=>{try{await document.fonts.ready;paginateOrderSlips();paginateTotals();paginateTimetable();document.getElementById('browserPrint').disabled=false;document.getElementById('browserPrint').textContent='Print / Save PDF';document.getElementById('printMessage').textContent='Click Print / Save PDF or press Ctrl+P. Choose Save as PDF for a PDF file. Use A4 landscape, 100% scale, and disable headers and footers.';requestAnimationFrame(()=>requestAnimationFrame(()=>window.print()))}catch(error){document.getElementById('printMessage').textContent='Could not prepare print pages: '+error.message}},{once:true});</script></body></html>''';
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
