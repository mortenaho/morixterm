import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:morixterm/services/app_lock.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('enable, verify, change, and disable app password', () async {
    final lock = AppLock();
    expect(await lock.isEnabled(), isFalse);

    await lock.enable('secret');
    expect(await lock.isEnabled(), isTrue);
    expect(await lock.verify('secret'), isTrue);
    expect(await lock.verify('wrong'), isFalse);

    await lock.changePassword(current: 'secret', next: 'newer');
    expect(await lock.verify('newer'), isTrue);
    expect(await lock.verify('secret'), isFalse);

    await lock.disable('newer');
    expect(await lock.isEnabled(), isFalse);
  });

  test('rejects short passwords', () async {
    final lock = AppLock();
    expect(() => lock.enable('abc'), throwsA(isA<AppLockException>()));
  });
}
