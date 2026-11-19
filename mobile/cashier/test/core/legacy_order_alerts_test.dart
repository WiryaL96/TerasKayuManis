import 'dart:async';
import 'dart:convert';

import 'package:cashier/app.dart';
import 'package:cashier/core/order_chime.dart';
import 'package:cashier/data/cashier_api.dart';
import 'package:cashier/domain/models.dart';
import 'package:cashier/domain/order_arrivals.dart';
import 'package:cashier/features/cashier/cashier_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'api_models_test.dart' show FakeAuth, config, orderJson;
import 'controller_test.dart' show FakeRealtime, MemoryStore;

Map<String, dynamic> arrival(int number, {int version = 2}) => orderJson(
  id: '${number.toString().padLeft(8, '0')}-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
  createdAt: DateTime.utc(
    2026,
    1,
    1,
  ).add(Duration(seconds: number)).toIso8601String(),
  version: version,
);

class AlertFixture {
  AlertFixture() {
    realtime = FakeRealtime(auth);
    api = CashierApi(
      config: config(),
      auth: auth,
      client: MockClient((request) async {
        requests.add(request);
        if (request.url.path.endsWith('/staff-logout')) {
          return http.Response('{"ok":true}', 200);
        }
        expect(request.headers['Authorization'], 'Bearer token');
        if (request.url.path.endsWith('/admin/me')) {
          return http.Response(
            '{"id":"alice","full_name":"Alice","role":"cashier"}',
            200,
          );
        }
        if (request.url.path.endsWith('/admin/sync')) {
          return http.Response(jsonEncode({'revision': '$revision'}), 200);
        }
        expect(request.url.path, '/api/core/admin/orders');
        if (isArrivalQuery(request)) {
          return canonicalGate?.future ??
              http.Response(jsonEncode(active), canonicalStatus);
        }
        return http.Response(jsonEncode(visible), 200);
      }),
    );
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
  List<Map<String, dynamic>> active = [], visible = [];
  int revision = 1, canonicalStatus = 200;
  Completer<http.Response>? canonicalGate;

  static bool isArrivalQuery(http.Request request) {
    final query = request.url.queryParameters;
    return request.url.path.endsWith('/admin/orders') &&
        query.length == 4 &&
        query['tab'] == 'active' &&
        query['summary'] == '1' &&
        query['sort'] == 'newest' &&
        query['offset'] == '0';
  }

  int get arrivalReads => requests.where(isArrivalQuery).length;

  Future<void> dispose() async {
    controller.dispose();
    await auth.events.close();
  }
}

class RecordingChime implements OrderChime {
  int plays = 0, stops = 0;
  @override
  Future<void> warmUp() async {}
  @override
  Future<void> play() async {
    plays++;
  }

  @override
  Future<void> stop() async {
    stops++;
  }

  @override
  Future<void> dispose() async {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'empty queue seeds silently; new checkout alerts once across updates',
    () async {
      final fixture = AlertFixture();
      addTearDown(fixture.dispose);
      final c = fixture.controller;
      await c.initialize();
      expect(c.newOrderSerial, 0);
      expect(
        fixture.arrivalReads,
        1,
        reason: 'reuse the visible canonical queue',
      );
      await c.refresh();
      expect(
        fixture.arrivalReads,
        1,
        reason: 'unchanged revision uses the cache',
      );

      fixture.active = [arrival(1)];
      fixture.revision++;
      await c.refresh();
      expect(c.newOrderSerial, 1);
      fixture.active = [arrival(1, version: 3)];
      fixture.revision++;
      await c.refresh();
      expect(c.newOrderSerial, 1);
      fixture.active = [];
      fixture.revision++;
      await c.refresh();
      fixture.active = [arrival(1, version: 4)];
      fixture.revision++;
      await c.refresh();
      expect(c.newOrderSerial, 1);
    },
  );

  test('history, search, status, date, sort and page cannot hide or invent arrivals', () async {
    final fixture = AlertFixture()..active = [arrival(10)];
    addTearDown(fixture.dispose);
    final c = fixture.controller;
    await c.initialize();
    expect(c.newOrderSerial, 0);

    fixture.visible = List.generate(100, (i) => arrival(i + 100));
    await c.changeTab('history');
    await c.setSearch('kopi');
    await c.setStatusFilter('forwarded');
    await c.setSelectedDay(DateTime(2026, 1, 1));
    await c.setSort('oldest');
    await c.nextPage();
    expect(c.offset, 100);
    expect(
      c.newOrderSerial,
      0,
      reason: 'visible history rows are not arrivals',
    );
    final reads = fixture.arrivalReads;
    await c.refresh();
    expect(fixture.arrivalReads, reads);

    fixture.active = [arrival(11), arrival(10)];
    fixture.revision++;
    await c.refresh();
    expect(c.newOrderSerial, 1);
    expect(fixture.arrivalReads, reads + 1);
    expect(c.tab, 'history');
    expect(c.search, 'kopi');
    await c.previousPage();
    await c.clearFilters();
    await c.changeTab('active');
    expect(c.newOrderSerial, 1);
  });

  test('older rows entering a full newest page are not new checkouts', () {
    final arrivals = OrderArrivals();
    List<OrderRecord> rows(Iterable<int> values) =>
        values.map((n) => OrderRecord.fromJson(arrival(n))).toList();
    expect(arrivals.observe(rows(List.generate(100, (i) => 200 - i))), isEmpty);
    expect(arrivals.observe(rows(List.generate(100, (i) => 199 - i))), isEmpty);
    expect(arrivals.observe(rows([201, 199, 198])), hasLength(1));
    expect(arrivals.observe(rows([201, 199, 198])), isEmpty);
  });

  test('same timestamp arrivals are deduplicated by ID and reset for another session', () {
    final arrivals = OrderArrivals();
    final first = OrderRecord.fromJson(arrival(1));
    final second = OrderRecord.fromJson(
      arrival(2)..['created_at'] = arrival(1)['created_at'],
    );
    expect(arrivals.observe([first]), isEmpty);
    expect(arrivals.observe([first, second]), {second.id});
    expect(arrivals.observe([second]), isEmpty);
    expect(arrivals.observe([first, second]), isEmpty);
    arrivals.reset();
    expect(arrivals.observe([first, second]), isEmpty);
  });

  test(
    'failed fallback read retains arrival baseline for a successful retry',
    () async {
      final fixture = AlertFixture()..active = [arrival(1)];
      addTearDown(fixture.dispose);
      final c = fixture.controller;
      await c.initialize();
      await c.changeTab('history');
      fixture.active = [arrival(2), arrival(1)];
      fixture.revision++;
      fixture.canonicalStatus = 503;
      await c.refresh();
      expect(c.newOrderSerial, 0);
      expect(c.error, isNotNull);
      fixture.canonicalStatus = 200;
      await c.refresh(force: true);
      expect(c.newOrderSerial, 1);
      expect(c.error, isNull);
    },
  );

  test(
    'late fallback response after logout cannot alert or restore staff data',
    () async {
      final fixture = AlertFixture()..active = [arrival(1)];
      addTearDown(fixture.dispose);
      final c = fixture.controller;
      await c.initialize();
      await c.changeTab('history');
      fixture.revision++;
      final gate = Completer<http.Response>();
      fixture.canonicalGate = gate;
      final pending = c.refresh();
      await Future<void>.delayed(Duration.zero);
      await c.logout();
      gate.complete(http.Response(jsonEncode([arrival(2), arrival(1)]), 200));
      await pending;
      expect(c.signedIn, isFalse);
      expect(c.orders, isEmpty);
      expect(c.newOrderSerial, 0);
    },
  );

  test('pause invalidates a pending arrival read; resume alerts once after a fresh read', () async {
    final fixture = AlertFixture()..active = [arrival(1)];
    addTearDown(fixture.dispose);
    final c = fixture.controller;
    await c.initialize();
    fixture.active = [arrival(2), arrival(1)];
    fixture.revision++;
    final gate = Completer<http.Response>();
    fixture.canonicalGate = gate;
    final pending = c.refresh();
    await Future<void>.delayed(Duration.zero);
    c.setForeground(false);
    gate.complete(http.Response(jsonEncode(fixture.active), 200));
    await pending;
    expect(c.newOrderSerial, 0);
    fixture.canonicalGate = null;
    c.setForeground(true);
    await c.refresh();
    expect(c.newOrderSerial, 1);
    await c.refresh();
    expect(c.newOrderSerial, 1);
  });

  testWidgets(
    'legacy polling reaches chime, ON previews sound, OFF mutes and saves preference',
    (tester) async {
      final fixture = AlertFixture()..active = [arrival(1)];
      final chime = RecordingChime();
      final saved = <String?>[];
      const storage = MethodChannel(
        'plugins.it_nomads.com/flutter_secure_storage',
      );
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(storage, (
        call,
      ) async {
        if (call.method == 'write') {
          saved.add((call.arguments as Map)['value'] as String?);
        }
        return null;
      });
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          storage,
          null,
        ),
      );
      addTearDown(fixture.auth.events.close);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.binding.setSurfaceSize(const Size(1000, 1000));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        CashierApp(controller: fixture.controller, chime: chime),
      );
      await tester.pumpAndSettle();
      final toggle = find.byKey(const ValueKey('sound-toggle'));
      expect(tester.widget<Switch>(toggle).onChanged, isNotNull);
      expect(chime.plays, 0, reason: 'login snapshot is silent');

      await tester.tap(toggle);
      await tester.pumpAndSettle();
      expect(tester.widget<Switch>(toggle).value, isFalse);
      await tester.tap(toggle);
      await tester.pumpAndSettle();
      expect(tester.widget<Switch>(toggle).value, isTrue);
      expect(chime.plays, 1, reason: 'ON plays a preview');

      fixture.active = [arrival(2), arrival(1)];
      fixture.revision++;
      await fixture.controller.refresh();
      await tester.pump();
      await tester.pump();
      expect(chime.plays, 2, reason: 'new checkout plays the real alert path');
      expect(find.text('Pesanan baru masuk'), findsOneWidget);
      await fixture.controller.refresh();
      await tester.pump();
      expect(chime.plays, 2);

      await tester.tap(toggle);
      await tester.pumpAndSettle();
      fixture.active = [arrival(3), arrival(2), arrival(1)];
      fixture.revision++;
      await fixture.controller.refresh();
      await tester.pump();
      await tester.pump();
      expect(chime.plays, 2, reason: 'OFF suppresses incoming audio');
      expect(saved, ['false', 'true', 'false']);
      expect(chime.stops, greaterThanOrEqualTo(2));
      await tester.pumpWidget(const SizedBox());
    },
  );
}
