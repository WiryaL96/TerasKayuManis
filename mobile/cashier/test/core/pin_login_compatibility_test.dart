import 'dart:convert';

import 'package:cashier/core/order_watch.dart';
import 'package:cashier/data/cashier_api.dart';
import 'package:cashier/domain/order_sync.dart';
import 'package:cashier/features/cashier/cashier_controller.dart';
import 'package:cashier/features/cashier/cashier_screen.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'api_models_test.dart' show FakeAuth, config, orderJson;
import 'controller_test.dart' show FakeRealtime, MemoryStore;

const _cashierId = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa';
const _fixturePin = '123456';

class LoginFixture {
  LoginFixture() {
    auth.id = null;
    api = CashierApi(
      config: config(),
      auth: auth,
      client: MockClient((request) async {
        requests.add(request);
        if (request.url.path == '/api/auth/cashier-pin') {
          expect(request.headers.containsKey('Authorization'), isFalse);
          expect(jsonDecode(request.body), {
            'cashier_id': _cashierId,
            'pin': _fixturePin,
          });
          return http.Response(
            jsonEncode({
              'profile': {
                'id': _cashierId,
                'full_name': 'Kasir Fixture',
                'role': 'cashier',
              },
              'session': {
                'access_token': 'fixture-access',
                'refresh_token': 'fixture:$_cashierId',
              },
            }),
            loginStatus,
          );
        }
        expect(request.method, 'GET');
        expect(request.headers['Authorization'], 'Bearer fixture:$_cashierId');
        if (request.url.path.endsWith('/admin/sync')) {
          return http.Response(jsonEncode(sync), 200);
        }
        expect(request.url.path, '/api/core/admin/orders');
        return http.Response(jsonEncode(orders), ordersStatus);
      }),
    );
    realtime = FakeRealtime(auth);
    controller = CashierController(
      api: api,
      auth: auth,
      realtime: realtime,
      store: MemoryStore(),
    );
  }

  final auth = FakeAuth();
  final requests = <http.Request>[];
  late final CashierApi api;
  late final FakeRealtime realtime;
  late final CashierController controller;
  int loginStatus = 200, ordersStatus = 200;
  Object sync = {'revision': '1'};
  List<Map<String, dynamic>> orders = [orderJson()];

  Future<void> dispose() async {
    controller.dispose();
    await auth.events.close();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'valid PIN and revision-only sync open the authenticated queue',
    () async {
      final fixture = LoginFixture();
      addTearDown(fixture.dispose);
      final controller = fixture.controller;

      await controller.loginPin(_cashierId, _fixturePin);

      expect(controller.signedIn, isTrue);
      expect(controller.staff?.id, _cashierId);
      expect(controller.orders.single.id, orderJson()['id']);
      expect(controller.error, isNull);
      expect(controller.latestSync?.hasNewOrderFeed, isFalse);
      expect(controller.newOrderSerial, 0);
      expect(fixture.realtime.starts, 1);

      fixture.sync = {'revision': '2'};
      fixture.orders = [];
      await controller.refresh();
      expect(controller.orders, isEmpty);
      expect(controller.lastSync.value, isNotNull);
      expect(controller.newOrderSerial, 0);
      expect(
        fixture.requests.where((request) => request.method == 'POST'),
        hasLength(1),
      );
    },
  );

  test(
    'notification feed availability reseeds without replaying old arrivals',
    () async {
      final fixture = LoginFixture();
      addTearDown(fixture.dispose);
      final controller = fixture.controller;
      await controller.loginPin(_cashierId, _fixturePin);
      var changes = 0;
      controller.addListener(() => changes++);

      fixture.sync = {
        'revision': '1',
        'new_orders': ['existing-order'],
      };
      await controller.refresh();
      expect(controller.latestSync?.hasNewOrderFeed, isTrue);
      expect(controller.newOrderSerial, 0);
      expect(changes, greaterThan(0));

      fixture.sync = {
        'revision': '2',
        'new_orders': ['existing-order', 'new-order'],
      };
      await controller.refresh();
      expect(controller.newOrderSerial, 1);

      fixture.sync = {'revision': '2'};
      await controller.refresh();
      fixture.sync = {
        'revision': '2',
        'new_orders': ['existing-order', 'new-order', 'during-gap'],
      };
      await controller.refresh();
      expect(controller.newOrderSerial, 1);
    },
  );

  test(
    'wrong PIN does not report an expired session or read staff data',
    () async {
      final fixture = LoginFixture()..loginStatus = 401;
      addTearDown(fixture.dispose);

      await fixture.controller.loginPin(_cashierId, _fixturePin);

      expect(fixture.controller.signedIn, isFalse);
      expect(fixture.controller.error, contains('PIN tidak sesuai'));
      expect(fixture.controller.error, isNot(contains('Sesi kasir berakhir')));
      expect(fixture.auth.userId, isNull);
      expect(fixture.requests, hasLength(1));
    },
  );

  test(
    'legacy sync never bypasses rejected staff queue authorization',
    () async {
      final fixture = LoginFixture()..ordersStatus = 401;
      addTearDown(fixture.dispose);

      await fixture.controller.loginPin(_cashierId, _fixturePin);

      expect(fixture.controller.signedIn, isFalse);
      expect(fixture.controller.orders, isEmpty);
      expect(fixture.controller.error, contains('Sesi kasir berakhir'));
      expect(fixture.realtime.starts, 0);
    },
  );

  test(
    'malformed sync remains an explicit error and never opens the queue',
    () async {
      for (final sync in <Object>[
        [],
        {'revision': ''},
        {'revision': '1', 'new_orders': null},
        {'revision': '1', 'new_orders': 'secret-invalid-value'},
        {
          'revision': '1',
          'new_orders': [123],
        },
        {'revision': '1', 'new_orders': List.filled(1001, 'order')},
      ]) {
        final fixture = LoginFixture()..sync = sync;
        try {
          await fixture.controller.loginPin(_cashierId, _fixturePin);
          expect(fixture.controller.signedIn, isFalse);
          expect(
            fixture.controller.error,
            contains('Data sinkronisasi tidak valid'),
          );
          expect(fixture.controller.error, isNot(contains('secret')));
          expect(fixture.controller.error, isNot(contains('Tindakan gagal')));
          expect(
            fixture.requests.where((r) => r.url.path.endsWith('/admin/orders')),
            isEmpty,
          );
        } finally {
          await fixture.dispose();
        }
      }
    },
  );

  testWidgets(
    'legacy sync enables foreground sound and explains background limits',
    (tester) async {
      final fixture = LoginFixture();
      addTearDown(fixture.dispose);
      await fixture.controller.loginPin(_cashierId, _fixturePin);
      final watchStatus = ValueNotifier('Notifikasi diizinkan');
      addTearDown(watchStatus.dispose);
      bool? soundChanged;

      await tester.pumpWidget(
        MaterialApp(
          home: CashierScreen(
            controller: fixture.controller,
            sound: true,
            onSoundChanged: (value) => soundChanged = value,
            watchStatus: watchStatus,
            onEnableNotifications: () => fail('legacy watch must be disabled'),
          ),
        ),
      );
      await tester.pump();
      expect(
        find.textContaining(
          'Suara pesanan baru tersedia saat aplikasi terbuka',
        ),
        findsOneWidget,
      );
      final sound = tester.widget<Switch>(
        find.byKey(const ValueKey('sound-toggle')),
      );
      expect(sound.value, isTrue);
      expect(sound.onChanged, isNotNull);
      await tester.tap(find.byKey(const ValueKey('sound-toggle')));
      expect(soundChanged, isFalse);
      expect(find.text('Periksa izin notifikasi'), findsNothing);
      expect(find.text('Notifikasi diizinkan'), findsNothing);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'legacy sync does not request permission, lease, or native start',
    (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);
      const channel = MethodChannel('id.alrizky.teraskayumanis.cashier/watch');
      final nativeCalls = <String>[];
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (
        call,
      ) async {
        nativeCalls.add(call.method);
        return true;
      });
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          channel,
          null,
        ),
      );
      final auth = FakeAuth();
      addTearDown(auth.events.close);
      var leaseRequests = 0;
      final api = CashierApi(
        config: config(),
        auth: auth,
        client: MockClient((_) async {
          leaseRequests++;
          return http.Response('{}', 404);
        }),
      );
      addTearDown(api.close);
      final watch = OrderWatch(config(), auth, api: api);
      watch.remember(OrderSync.fromJson({'revision': '1'}));

      try {
        expect(await watch.ensureNotificationPermission(), isFalse);
        await watch.prepare();
        await watch.start();

        expect(nativeCalls, isEmpty);
        expect(leaseRequests, 0);
        expect(
          watch.status.value,
          contains('Pemantauan latar belum didukung server'),
        );
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    },
  );
}
