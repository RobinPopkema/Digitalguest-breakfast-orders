import 'package:breakfast_orders/model.dart';

Json fixture() => {
  'categories': [
    {'id': 'bakery', 'name': 'Bakery', 'color': 0},
  ],
  'items': [
    {'id': 'croissant', 'name': 'Croissant', 'categoryId': 'bakery'},
    {'id': 'butter', 'name': 'Butter', 'categoryId': 'bakery'},
  ],
  'orders': <Json>[],
  'rooms': ['old untrusted cabin'],
  'safeCabins': [
    {'id': '8', 'name': '8'},
    {'id': '9', 'name': '9'},
  ],
  'viewSort': 'room',
  'sortUiVersion': 2,
};
String source({
  String time = '8:00 - 8:30',
  String id = 'order-one',
  String sender = 'noreply@e.maildigitalguest.com',
}) =>
    'From: DigitalGuest <$sender>\r\nSubject: Order request received\r\nMessage-ID: <$id@example.com>\r\nContent-Type: text/plain; charset=utf-8\r\n\r\nNew Order Request\nRequest received at: 9/28/2026 - 22:09\n\n1 x $time\t0.00 NOK\n2 x Croissant\t0.00 NOK\n1 x Butter\t0.00 NOK\n\nOrder comment\nLeave outside\nGuest Info\nName: Sample\nRoom: 8\nTotal 0.00 NOK';
