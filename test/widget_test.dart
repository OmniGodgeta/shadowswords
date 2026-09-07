import 'package:flutter_test/flutter_test.dart';
import 'package:shadowswords/main.dart';

void main() {
  test('kSiteUrl is a valid https URL', () {
    final uri = Uri.parse(kSiteUrl);
    expect(uri.scheme, 'https');
    expect(uri.host, isNotEmpty);
  });

  group('isVersionNewer', () {
    test('detects a newer patch / minor / major', () {
      expect(isVersionNewer('1.0.1', '1.0.0'), isTrue);
      expect(isVersionNewer('1.1.0', '1.0.9'), isTrue);
      expect(isVersionNewer('2.0.0', '1.9.9'), isTrue);
    });
    test('same or older is not newer', () {
      expect(isVersionNewer('1.0.0', '1.0.0'), isFalse);
      expect(isVersionNewer('1.0.0', '1.0.1'), isFalse);
      expect(isVersionNewer('1.0.0', '1.1.0'), isFalse);
    });
    test('tolerates short / noisy strings', () {
      expect(isVersionNewer('1.1', '1.0.5'), isTrue);
      expect(isVersionNewer('1.0', '1.0.0'), isFalse);
    });
  });
}
