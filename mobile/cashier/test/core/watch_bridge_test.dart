import 'dart:async';

import 'package:cashier/core/order_watch.dart';
import 'package:cashier/data/cashier_api.dart';
import 'package:cashier/domain/order_sync.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'api_models_test.dart' show FakeAuth, config;

class LeaseApi extends CashierApi {
  LeaseApi(FakeAuth auth) : super(auth: auth, config: config());
  final pending = Completer<WatchLease>();
  final revoked = <String>[];
  @override
  Future<WatchLease> issueWatch(String deviceId) => pending.future;
  @override
  Future<void> revokeWatch(String token) async {
    revoked.add(token);
  }
}

void main() {
  testWidgets(
    'late lease after logout is revoked and never reaches native start',
    (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      const channel = MethodChannel('id.alrizky.teraskayumanis.cashier/watch');
      const storage = MethodChannel(
        'plugins.it_nomads.com/flutter_secure_storage',
      );
      final calls = <String>[];
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (
        call,
      ) async {
        calls.add(call.method);
        return call.method == 'ensureNotificationPermission'
            ? true
            : <String, dynamic>{};
      });
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        storage,
        (call) async => call.method == 'read'
            ? 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa'
            : null,
      );
      final auth = FakeAuth();
      final api = LeaseApi(auth);
      final watch = OrderWatch(config(), auth, api: api);
      final prepare = watch.prepare();
      await tester.pump();
      await watch.stop(clear: true);
      final token = 'a' * 64;
      api.pending.complete(
        WatchLease(token, DateTime.now().add(const Duration(hours: 1))),
      );
      await prepare;
      expect(calls, isNot(contains('start')));
      expect(api.revoked, [token]);
      debugDefaultTargetPlatformOverride = null;
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        channel,
        null,
      );
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        storage,
        null,
      );
      api.close();
      await auth.events.close();
    },
  );
}
