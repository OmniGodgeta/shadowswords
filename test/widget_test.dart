// The app is a single fullscreen WebView; there's little to unit-test without a
// platform WebView implementation. This just guards the site URL constant.

import 'package:flutter_test/flutter_test.dart';
import 'package:shadowswords/main.dart';

void main() {
  test('kSiteUrl is a valid https URL', () {
    final uri = Uri.parse(kSiteUrl);
    expect(uri.hasScheme, isTrue);
    expect(uri.scheme, 'https');
    expect(uri.host, isNotEmpty);
  });
}
