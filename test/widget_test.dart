import 'package:flutter_test/flutter_test.dart';
import 'package:liber/update/update_service.dart';

void main() {
  group('UpdateService.parseVersion', () {
    test('parses release tags with and without a v prefix', () {
      expect(UpdateService.parseVersion('v1.2.3'), <int>[1, 2, 3]);
      expect(UpdateService.parseVersion('1.2.3'), <int>[1, 2, 3]);
      expect(UpdateService.parseVersion('V2.0'), <int>[2, 0]);
      expect(UpdateService.parseVersion('1.0.0+7'), <int>[1, 0, 0]);
    });

    test('returns null for values that are not versions', () {
      expect(UpdateService.parseVersion(''), isNull);
      expect(UpdateService.parseVersion('latest'), isNull);
    });

    test('shorter versions compare as zero-padded', () {
      expect(UpdateService.parseVersion('1.10.0'), <int>[1, 10, 0]);
      expect(UpdateService.parseVersion('v1.10'), <int>[1, 10]);
    });
  });
}
