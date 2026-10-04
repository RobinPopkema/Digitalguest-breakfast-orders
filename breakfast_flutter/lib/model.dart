import 'dart:convert';
import 'dart:math';

import 'package:unorm_dart/unorm_dart.dart' as unicode;

typedef Json = Map<String, dynamic>;
Json clone(Json value) => jsonDecode(jsonEncode(value)) as Json;
List<Json> rows(dynamic value) => (value as List).cast<Json>();
String normalize(dynamic value) => unicode
    .nfkc('${value ?? ''}')
    .trim()
    .replaceAll(RegExp(r'\s+'), ' ')
    .toLowerCase();
String newId() {
  final bytes = List<int>.generate(16, (_) => Random.secure().nextInt(256));
  bytes[6] = (bytes[6] & 15) | 64;
  bytes[8] = (bytes[8] & 63) | 128;
  final hex = bytes.map((n) => n.toRadixString(16).padLeft(2, '0')).join();
  return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20)}';
}

final slots = List.generate(7, (i) {
  String time(int n) =>
      '${7 + n ~/ 2}'.padLeft(2, '0') + (n.isEven ? ':00' : ':30');
  return '${time(i)}–${time(i + 1)}';
});
const palette = [
  [0xffdbeef9, 0xff145b83],
  [0xfffce9cf, 0xff965600],
  [0xffe0f3e9, 0xff176a43],
  [0xfff2e4fa, 0xff70458c],
  [0xfffce3e5, 0xff973c4c],
  [0xffe0ecf7, 0xff355a9c],
  [0xfffaefd6, 0xff806119],
  [0xffdff4f1, 0xff176e68],
  [0xffedf5ce, 0xff526615],
  [0xffffe6da, 0xff974b2d],
  [0xfff7dff0, 0xff8c3270],
  [0xffd8f3fa, 0xff156b81],
  [0xffe9e3ff, 0xff57439c],
  [0xffeaf0d8, 0xff536631],
  [0xffffe2e0, 0xffa34038],
  [0xffd4f4e7, 0xff116c52],
  [0xffeee1d5, 0xff785133],
  [0xffe1e8ef, 0xff40586f],
  [0xfffff2b8, 0xff80620a],
  [0xffffe0ef, 0xff91365f],
  [0xffdfe8ff, 0xff3c5798],
  [0xffdeece1, 0xff476b4f],
  [0xfff3ebdd, 0xff7b6542],
  [0xffebddec, 0xff754772],
];
const colorNames = [
  'Sky blue',
  'Peach',
  'Mint',
  'Lavender',
  'Rose',
  'Blue',
  'Gold',
  'Teal',
  'Lime',
  'Apricot',
  'Magenta',
  'Aqua',
  'Violet',
  'Olive',
  'Coral',
  'Emerald',
  'Brown',
  'Slate',
  'Yellow',
  'Pink',
  'Indigo',
  'Sage',
  'Sand',
  'Plum',
];
Json emptyData() => {
  'categories': <Json>[],
  'items': <Json>[],
  'orders': <Json>[],
  'rooms': <String>[],
  'safeCabins': <Json>[],
  'viewSort': 'room',
  'sortUiVersion': 2,
};
Json validateData(dynamic value) {
  if (value is! Json ||
      [
        'categories',
        'items',
        'orders',
        'rooms',
      ].any((key) => value[key] is! List)) {
    throw const FormatException(
      'Invalid Breakfast Orders data. No files were changed.',
    );
  }
  for (final key in ['categories', 'items', 'orders', 'safeCabins']) {
    if (key == 'safeCabins' && !value.containsKey(key)) continue;
    if (value[key] is! List) throw FormatException('Invalid $key');
    for (final entry in value[key]) {
      if (entry is! Json || entry['id'] is! String) {
        throw FormatException('Invalid $key entry');
      }
      if (key != 'orders' && entry['name'] is! String) {
        throw FormatException('Invalid $key name');
      }
      if (key == 'safeCabins' && (entry['name'] as String).trim().isEmpty) {
        throw const FormatException('Invalid cabin name');
      }
      if (key == 'items' && entry['categoryId'] is! String) {
        throw const FormatException('Invalid item category');
      }
      if (key == 'orders') {
        if (entry['room'] is! String || entry['lines'] is! List) {
          throw const FormatException('Invalid order');
        }
        for (final line in entry['lines']) {
          if (line is! Json ||
              line['name'] is! String ||
              line['qty'] is! num ||
              !((line['qty'] as num).isFinite)) {
            throw const FormatException('Invalid order line');
          }
        }
      }
    }
  }
  value['safeCabins'] ??= <Json>[];
  return value;
}

Json? findById(dynamic list, dynamic id) =>
    rows(list).where((e) => e['id'] == id).firstOrNull;
bool itemAvailable(Json item) => item['available'] != false;

Json lineFor(Json item, Json category, int quantity) => {
  'itemId': item['id'],
  'name': item['name'],
  'categoryId': category['id'],
  'categoryName': category['name'],
  'categoryColor': category['color'] ?? 0,
  'qty': quantity,
};
// Preserve first-match lookup behavior for legacy data with duplicate IDs.
Map<dynamic, Json> indexById(dynamic list) {
  final index = <dynamic, Json>{};
  for (final entry in rows(list)) {
    index.putIfAbsent(entry['id'], () => entry);
  }
  return index;
}

void updateSnapshots(Json data) {
  final items = indexById(data['items']);
  final categories = indexById(data['categories']);
  for (final order in rows(data['orders'])) {
    for (final line in rows(order['lines'])) {
      final item = items[line['itemId']];
      final category = categories[item?['categoryId'] ?? line['categoryId']];
      if (item != null) {
        line['name'] = item['name'];
        line['categoryId'] = item['categoryId'];
      }
      if (category != null) {
        line['categoryName'] = category['name'];
        line['categoryColor'] = category['color'];
      }
    }
  }
}

final _naturalParts = RegExp(r'\d+|\D+');

int naturalCompare(String a, String b) {
  final pattern = _naturalParts;
  final aa = pattern.allMatches(a.toLowerCase()).map((m) => m[0]!).toList();
  final bb = pattern.allMatches(b.toLowerCase()).map((m) => m[0]!).toList();
  for (var i = 0; i < min(aa.length, bb.length); i++) {
    final x = int.tryParse(aa[i]), y = int.tryParse(bb[i]);
    final result = x != null && y != null
        ? x.compareTo(y)
        : aa[i].compareTo(bb[i]);
    if (result != 0) return result;
  }
  return aa.length.compareTo(bb.length);
}

List<Json> sortedOrders(Json data) {
  final original = rows(data['orders']);
  final mode = data['viewSort'] ?? 'room';
  if (mode == 'newest') return original.reversed.toList();
  if (mode == 'oldest') return [...original];
  final indexes = List.generate(original.length, (i) => i);
  indexes.sort((left, right) {
    final a = original[left], b = original[right];
    final insertion = left.compareTo(right);
    final room = naturalCompare(a['room'], b['room']);
    final time = slots.indexOf(a['slot']).compareTo(slots.indexOf(b['slot']));
    final first = mode == 'room'
        ? room
        : mode == 'room-desc'
        ? -room
        : mode == 'delivery-desc'
        ? -time
        : time;
    final second = '$mode'.startsWith('room') ? time : room;
    return first != 0
        ? first
        : second != 0
        ? second
        : insertion;
  });
  return [for (final index in indexes) original[index]];
}

// Sort a display copy; imported source order and historical lines stay intact.
List<Json> orderedOrderLines(Json data, Json order) {
  final original = rows(order['lines']);
  final categories = <dynamic, int>{
    for (var i = 0; i < data['categories'].length; i++)
      data['categories'][i]['id']: i,
  };
  for (final line in original) {
    categories.putIfAbsent(line['categoryId'], () => categories.length);
  }
  final items = <dynamic, int>{
    for (var i = 0; i < data['items'].length; i++) data['items'][i]['id']: i,
  };
  final indexes = List.generate(original.length, (i) => i);
  indexes.sort((a, b) {
    final left = original[a], right = original[b];
    final category = categories[left['categoryId']]!.compareTo(
      categories[right['categoryId']]!,
    );
    if (category != 0) return category;
    final item = (items[left['itemId']] ?? items.length).compareTo(
      items[right['itemId']] ?? items.length,
    );
    return item != 0 ? item : a.compareTo(b);
  });
  return [for (final index in indexes) original[index]];
}
