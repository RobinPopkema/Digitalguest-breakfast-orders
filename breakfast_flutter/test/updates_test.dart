import 'package:flutter_test/flutter_test.dart';
import 'package:breakfast_orders/model.dart';
import 'package:breakfast_orders/services/updates.dart';

class CountingUpdates extends Updates {
  int checks = 0;
  @override
  Future<void> check() async {
    checks++;
    available = {'version': 'v9.0.0'};
  }
}

void main() {
  testWidgets('Automatic updates check once at startup, never periodically', (
    tester,
  ) async {
    final updates = CountingUpdates();
    addTearDown(updates.dispose);
    updates.start();
    updates.start();
    await tester.pump();
    expect(updates.checks, 1);
    expect(updates.startupNoticePending, isTrue);
    updates.startupNoticePending = false;
    await tester.pump(const Duration(hours: 9));
    expect(updates.checks, 1);
    await updates.check();
    expect(updates.checks, 2);
    expect(updates.startupNoticePending, isFalse);
  });

  Json release() => {
    'draft': false,
    'prerelease': false,
    'tag_name': 'v2.0.34',
    'body': 'Fixes',
    'assets': [
      {
        'name': 'Breakfast-Orders-Flutter-2.0.34-Windows.zip',
        'size': 123,
        'browser_download_url': 'https://github.com/RobinPopkema/Digitalguest-breakfast-orders/releases/download/v2.0.34/Breakfast-Orders-Flutter-2.0.34-Windows.zip',
        'digest': 'sha256:${'a' * 64}',
      },
    ],
  };
  test(
    'Update versions compare numerically and reject previews and downgrades',
    () {
      expect(newerVersion('v2.0.100', '2.0.26'), isTrue);
      for (final version in ['2.0.26', '2.0.9', '2.1.0-beta', 'invalid']) {
        expect(newerVersion(version, '2.0.26'), isFalse);
      }
    },
  );
  test('Only complete releases with a verified Windows asset are offered', () {
    expect(
      eligibleUpdate(release(), updateRepository, appVersion)?['version'],
      'v2.0.34',
    );
    for (final key in ['draft', 'prerelease']) {
      expect(
        eligibleUpdate(release()..[key] = true, updateRepository, appVersion),
        isNull,
      );
    }
    for (final change in [
      {'digest': null},
      {'size': 0},
      {'name': 'Source.zip'},
      {
        'browser_download_url': 'http://github.com/RobinPopkema/Digitalguest-breakfast-orders/releases/download/x',
      },
      {
        'browser_download_url':
            'https://github.com/other/repo/releases/download/x',
      },
    ]) {
      final value = clone(release());
      value['assets'][0].addAll(change);
      expect(eligibleUpdate(value, updateRepository, appVersion), isNull);
    }
  });
}
