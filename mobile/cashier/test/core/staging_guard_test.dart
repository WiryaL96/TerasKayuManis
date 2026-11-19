import 'package:flutter_test/flutter_test.dart';

import '../live/public_contract_test.dart' show stagingConfig;

void main() {
  test('live fixture refuses production and mismatched staging', () {
    final fixture = <String, dynamic>{
      'environment': 'staging',
      'apiBase': 'https://staging.example.test/api/core/',
      'stagingHost': 'staging.example.test',
      'supabaseUrl': 'https://abcdefghijklmnopqrst.supabase.co',
      'stagingProjectRef': 'abcdefghijklmnopqrst',
      'publicKey': 'sb_publishable_test',
    };
    expect(stagingConfig(fixture).pollingOnly, isTrue);
    for (final change in [
      {'apiBase': 'https://teraskayumanis.vercel.app/api/core/'},
      {
        'supabaseUrl': 'https://aiptdjypuccoakyfvdyl.supabase.co',
        'stagingProjectRef': 'aiptdjypuccoakyfvdyl',
      },
      {'environment': 'production'},
      {'stagingHost': 'another.example.test'},
    ]) {
      expect(
        () => stagingConfig({...fixture, ...change}),
        throwsFormatException,
      );
    }
  });
}
