import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:cashier/core/realtime_transport.dart';
import 'package:cashier/data/cashier_api.dart';
import 'package:cashier/domain/models.dart';
import 'package:cashier/features/cashier/cashier_controller.dart';

import 'api_models_test.dart' show config, FakeAuth, orderJson, posHandoffJson;
import 'controller_test.dart' show MemoryStore, FakeRealtime, staffResponse;

class RealHttpOverrides extends HttpOverrides {}

class HungAuth extends FakeAuth {
  final gate = Completer<String?>();
  bool hung = true;
  @override
  Future<String?> accessToken() => hung ? gate.future : super.accessToken();
}

void main() {
  test(
    'native WebSocket rejects redirects before contacting destination',
    () => HttpOverrides.runWithHttpOverrides(() async {
      final destination = await HttpServer.bind(
        InternetAddress.loopbackIPv4,
        0,
      );
      final origin = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      var destinationCalls = 0;
      destination.listen((request) async {
        destinationCalls++;
        final socket = await WebSocketTransformer.upgrade(request);
        socket.listen((_) {});
        await socket.close();
      });
      origin.listen((request) async {
        request.response.statusCode = 302;
        request.response.headers.set(
          'location',
          'http://127.0.0.1:${destination.port}/ws',
        );
        await request.response.close();
      });
      try {
        RealtimeSocket? socket;
        Object? failure;
        try {
          socket = await connectNative(
            Uri.parse('ws://127.0.0.1:${origin.port}/ws'),
            {},
          );
        } catch (e) {
          failure = e;
        } finally {
          await socket?.close();
        }
        expect(destinationCalls, 0);
        expect(failure, isA<WebSocketException>());
      } finally {
        await origin.close(force: true);
        await destination.close(force: true);
      }
    }, RealHttpOverrides()),
  );

  test('claim requires saved review and sends one reviewed version', () async {
    final auth = FakeAuth(), store = MemoryStore();
    final posts = <http.Request>[];
    final c = CashierController(
      api: CashierApi(
        config: config(),
        auth: auth,
        client: MockClient((r) async {
          if (r.url.path.endsWith('/admin/sync')) {
            return http.Response('{"revision":"1","new_orders":[]}', 200);
          }
          if (r.url.path.endsWith('/admin/me')) return staffResponse();
          if (r.method == 'POST') {
            posts.add(r);
            return http.Response(
              jsonEncode(
                orderJson(
                  status: 'pos_input',
                  version: 3,
                  posHandoff: posHandoffJson(),
                ),
              ),
              200,
            );
          }
          return http.Response(jsonEncode([orderJson()]), 200);
        }),
      ),
      auth: auth,
      realtime: FakeRealtime(auth),
      store: store,
    );
    await c.initialize();
    await c.claim(OrderRecord.fromJson(orderJson(reviewed: 1)));
    expect(posts, isEmpty);
    expect(c.error, isNotNull);
    await c.claim(c.orders.single);
    expect(posts, hasLength(1));
    expect(jsonDecode(posts.single.body), {'expected_version': 2});
    c.dispose();
    await auth.events.close();
  });

  test(
    'authorization denial invalidates an outstanding successful snapshot',
    () async {
      final auth = FakeAuth(), store = MemoryStore();
      final rt = FakeRealtime(auth);
      final gate = Completer<http.Response>();
      var hold = false;
      final c = CashierController(
        api: CashierApi(
          config: config(),
          auth: auth,
          client: MockClient((r) async {
            if (r.url.path.endsWith('/admin/sync')) {
              return http.Response('{"revision":"1","new_orders":[]}', 200);
            }
            if (r.url.path.endsWith('/admin/me')) return staffResponse();
            if (r.url.path.endsWith('/menu')) {
              return http.Response('{}', 403);
            }
            return hold
                ? gate.future
                : http.Response(jsonEncode([orderJson()]), 200);
          }),
        ),
        auth: auth,
        realtime: rt,
        store: store,
      );
      await c.initialize();
      hold = true;
      final refresh = c.refresh(force: true);
      await Future<void>.delayed(Duration.zero);
      await expectLater(c.menu(), throwsA(isA<ApiException>()));
      gate.complete(http.Response(jsonEncode([orderJson()]), 200));
      await refresh;
      expect(c.signedIn, isFalse);
      expect(c.orders, isEmpty);
      expect(c.staff, isNull);
      expect(rt.starts, 1);
      c.dispose();
      await auth.events.close();
    },
  );

  test('takeover sends a bounded reason and requires admin role', () async {
    final auth = FakeAuth(), store = MemoryStore();
    final posts = <http.Request>[];
    final c = CashierController(
      api: CashierApi(
        config: config(),
        auth: auth,
        client: MockClient((r) async {
          if (r.url.path.endsWith('/admin/sync')) {
            return http.Response('{"revision":"1","new_orders":[]}', 200);
          }
          if (r.url.path.endsWith('/admin/me')) {
            return http.Response(
              jsonEncode({
                'id': 'alice',
                'full_name': 'Alice',
                'role': 'admin',
              }),
              200,
            );
          }
          if (r.method == 'POST') {
            posts.add(r);
            return http.Response(
              jsonEncode(
                orderJson(
                  status: 'pos_input',
                  version: 3,
                  posHandoff: posHandoffJson(),
                ),
              ),
              200,
            );
          }
          return http.Response(
            jsonEncode([
              orderJson(
                status: 'pos_input',
                version: 2,
                posHandoff: posHandoffJson(
                  cashierId: 'bob',
                  cashierName: 'Bob',
                ),
              ),
            ]),
            200,
          );
        }),
      ),
      auth: auth,
      realtime: FakeRealtime(auth),
      store: store,
    );
    await c.initialize();
    final order = c.orders.single;
    await c.claim(order, takeoverReason: 'no');
    expect(posts, isEmpty);
    expect(c.error, isNotNull);
    await c.claim(order, takeoverReason: 'Kasir pagi sakit');
    expect(posts, hasLength(1));
    expect(jsonDecode(posts.single.body), {
      'expected_version': 2,
      'takeover_reason': 'Kasir pagi sakit',
    });
    c.dispose();
    await auth.events.close();
  });

  testWidgets('token acquisition is bounded and late token never sends HTTP', (
    tester,
  ) async {
    final auth = HungAuth();
    var requests = 0;
    final api = CashierApi(
      config: config(),
      auth: auth,
      client: MockClient((r) async {
        requests++;
        return http.Response('[]', 200);
      }),
    );
    var finished = false;
    final result = api.listOrders().then(
      (_) {
        finished = true;
      },
      onError: (Object _) {
        finished = true;
      },
    );
    await tester.pump(const Duration(seconds: 16));
    expect(finished, isTrue);
    auth.gate.complete('late');
    await tester.pump();
    await result;
    expect(requests, 0);
    api.close();
    await auth.events.close();
  });

  testWidgets('new session detaches old hung controller refresh', (
    tester,
  ) async {
    final auth = HungAuth();
    final c = CashierController(
      api: CashierApi(
        config: config(),
        auth: auth,
        client: MockClient((r) async {
          if (r.url.path.endsWith('/staff-login')) {
            return http.Response(
              '{"profile":{"id":"bob","full_name":"Bob","role":"cashier"},"session":{"access_token":"fixture","refresh_token":"fixture:bob"}}',
              200,
            );
          }
          if (r.url.path.endsWith('/admin/sync')) {
            return http.Response('{"revision":"1","new_orders":[]}', 200);
          }
          if (r.url.path.endsWith('/admin/me')) {
            return http.Response(
              jsonEncode({'id': 'bob', 'full_name': 'Bob', 'role': 'cashier'}),
              200,
            );
          }
          return http.Response(jsonEncode([orderJson()]), 200);
        }),
      ),
      auth: auth,
      realtime: FakeRealtime(auth),
      store: MemoryStore(),
    );
    final old = c.initialize();
    await tester.pump();
    await c.logout();
    auth.hung = false;
    var done = false;
    final login = c.login('bob', 'pw').then((_) {
      done = true;
    });
    await tester.pump();
    expect(done, isTrue);
    expect(c.signedIn, isTrue);
    auth.gate.complete('obsolete');
    await tester.pump();
    await Future.wait([old, login]);
    c.dispose();
    await auth.events.close();
  });
}
