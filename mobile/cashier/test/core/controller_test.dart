import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:cashier/core/realtime_client.dart';
import 'package:cashier/data/cashier_api.dart';
import 'package:cashier/data/secure_store.dart';
import 'package:cashier/domain/models.dart';
import 'package:cashier/features/cashier/cashier_controller.dart';

import 'api_models_test.dart' show config, FakeAuth, orderJson, posHandoffJson;

class MemoryStore implements AttemptStore {
  final values = <String, String>{};
  bool failWrite = false;
  Completer<String?>? readGate;
  @override
  Future<String?> read(String key) async =>
      readGate == null ? values[key] : await readGate!.future;
  @override
  Future<void> write(String key, String value) async {
    if (failWrite) throw StateError('secret');
    values[key] = value;
  }

  @override
  Future<void> delete(String key) async {
    values.remove(key);
  }
}

class FakeRealtime extends RealtimeClient {
  FakeRealtime(FakeAuth auth) : super(config(), auth);
  int starts = 0, stops = 0;
  void Function()? invalidate, newOrder;
  @override
  void start({
    required void Function() onInvalidate,
    required void Function(RealtimeStatus) onStatus,
    required void Function() onNewOrder,
  }) {
    starts++;
    invalidate = onInvalidate;
    newOrder = onNewOrder;
  }

  @override
  void reconnect() {
    starts++;
  }

  @override
  void stop() {
    stops++;
  }

  @override
  void dispose() {
    stop();
  }
}

http.Response staffResponse() => http.Response(
  jsonEncode({'id': 'alice', 'full_name': 'Alice', 'role': 'cashier'}),
  200,
);

http.Response okResponse(http.Request r) {
  if (r.url.path.endsWith('/admin/me')) return staffResponse();
  if (r.url.path.endsWith('/admin/orders')) {
    return http.Response(jsonEncode([orderJson()]), 200);
  }
  return http.Response(jsonEncode(orderJson()), 200);
}

void main() {
  late FakeAuth auth;
  late MemoryStore store;
  late FakeRealtime rt;
  late CashierController c;
  late Future<http.Response> Function(http.Request) handler;
  var syncRevision = 0;
  Set<String> arrivals = {};
  setUp(() {
    auth = FakeAuth();
    store = MemoryStore();
    rt = FakeRealtime(auth);
    arrivals = {};
    syncRevision = 0;
    handler = (r) async => okResponse(r);
    c = CashierController(
      api: CashierApi(
        config: config(),
        auth: auth,
        client: MockClient((r) {
          if (r.url.path.endsWith('/staff-login')) {
            final id = (jsonDecode(r.body) as Map)['email'];
            return Future.value(
              http.Response(
                jsonEncode({
                  'profile': {'id': id, 'full_name': id, 'role': 'cashier'},
                  'session': {
                    'access_token': 'fixture',
                    'refresh_token': 'fixture:$id',
                  },
                }),
                200,
              ),
            );
          }
          if (r.url.path.endsWith('/staff-logout')) {
            return Future.value(http.Response('{"ok":true}', 200));
          }
          return r.url.path.endsWith('/admin/sync')
              ? Future.value(
                  http.Response(
                    jsonEncode({
                      'revision': '${syncRevision++}',
                      'new_orders': arrivals.toList(),
                    }),
                    200,
                  ),
                )
              : handler(r);
        }),
      ),
      auth: auth,
      realtime: rt,
      store: store,
    );
  });
  tearDown(() {
    c.dispose();
    auth.events.close();
  });
  test(
    'authorization gates panel; logout clears PII and ignores late snapshots',
    () async {
      final pending = Completer<http.Response>();
      handler = (r) => pending.future;
      final init = c.initialize();
      await Future<void>.delayed(Duration.zero);
      expect(c.signedIn, isFalse);
      await c.logout();
      pending.complete(staffResponse());
      await init;
      expect(c.signedIn, isFalse);
      expect(c.orders, isEmpty);
      expect(c.staff, isNull);
      expect(rt.starts, 0);
    },
  );
  test('invalid staff 401 never authorizes panel', () async {
    handler = (r) async => http.Response('{}', 401);
    await c.initialize();
    expect(c.signedIn, isFalse);
    expect(c.error, isNotNull);
    expect(rt.starts, 0);
  });
  test(
    'refresh is serialized with dirty trailing latest filter snapshot',
    () async {
      await c.initialize();
      final pending = Completer<http.Response>();
      var calls = 0;
      final paths = <Uri>[];
      handler = (r) {
        paths.add(r.url);
        calls++;
        return calls == 1
            ? pending.future
            : Future.value(http.Response('[]', 200));
      };
      final first = c.refresh();
      await Future<void>.delayed(Duration.zero);
      final second = c.changeTab('history');
      final third = c.refresh();
      expect(calls, 1);
      pending.complete(http.Response(jsonEncode([orderJson()]), 200));
      await Future.wait([first, second, third]);
      expect(calls, 2);
      expect(paths.last.queryParameters['tab'], 'history');
      expect(c.orders, isEmpty);
      expect(c.loading, isFalse);
    },
  );
  test(
    'polling detects newly arrived orders and seeds without chiming',
    () async {
      var orders = <Map<String, dynamic>>[];
      handler = (r) async {
        if (r.url.path.endsWith('/admin/me')) return staffResponse();
        if (r.url.queryParameters['tab'] == 'history') {
          return http.Response('[]', 200);
        }
        return http.Response(jsonEncode(orders), 200);
      };
      await c.initialize();
      expect(c.newOrderSerial, 0, reason: 'first snapshot must not chime');

      orders = [orderJson()];
      arrivals = {orderJson()['id'] as String};
      await c.refresh();
      expect(c.newOrderSerial, 1, reason: 'a new order id must chime');

      await c.refresh();
      expect(c.newOrderSerial, 1, reason: 'unchanged poll must not re-chime');

      orders = [
        orderJson(
          id: 'dddddddd-dddd-4ddd-8ddd-dddddddddddd',
          createdAt: '2026-01-02T00:00:00Z',
        ),
        orderJson(),
      ];
      arrivals = orders.map((o) => o['id'] as String).toSet();
      await c.refresh();
      expect(c.newOrderSerial, 2, reason: 'each additional order chimes once');

      await c.changeTab('history');
      await c.changeTab('active');
      expect(
        c.newOrderSerial,
        2,
        reason: 'returning to the active tab re-seeds the baseline',
      );
    },
  );
  test('realtime push and follow-up poll chime the same order once', () async {
    var orders = <Map<String, dynamic>>[];
    handler = (r) async {
      if (r.url.path.endsWith('/admin/me')) return staffResponse();
      return http.Response(jsonEncode(orders), 200);
    };
    await c.initialize();
    expect(c.newOrderSerial, 0);

    orders = [orderJson()];
    arrivals = {orderJson()['id'] as String};
    rt.newOrder?.call();
    await c.refresh();
    expect(
      c.newOrderSerial,
      1,
      reason: 'the follow-up snapshot must not alert the same order again',
    );

    orders = [
      orderJson(
        id: 'dddddddd-dddd-4ddd-8ddd-dddddddddddd',
        createdAt: '2026-01-02T00:00:00Z',
      ),
      orderJson(),
    ];
    arrivals = orders.map((o) => o['id'] as String).toSet();
    await c.refresh();
    expect(c.newOrderSerial, 2, reason: 'polling still alerts later orders');
  });
  test('staff profile and date filter use bounded server queries', () async {
    handler = (r) async {
      if (r.url.path.endsWith('/admin/me')) return staffResponse();
      final tab = r.url.queryParameters['tab'];
      if (tab == 'active') return http.Response('[]', 200);
      return http.Response(
        jsonEncode(
          [
                orderJson(
                  id: 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb',
                  status: 'forwarded',
                  createdAt: '2026-01-02T10:00:00Z',
                ),
                orderJson(
                  id: 'cccccccc-cccc-4ccc-8ccc-cccccccccccc',
                  status: 'completed',
                  createdAt: '2026-01-01T10:00:00Z',
                ),
              ]
              .where(
                (o) =>
                    r.url.queryParameters['date'] == null ||
                    (o['created_at'] as String).startsWith(
                      r.url.queryParameters['date']!,
                    ),
              )
              .toList(),
        ),
        200,
      );
    };
    await c.initialize();
    expect(c.staff!.fullName, 'Alice');
    await c.changeTab('history');
    expect(c.orders, hasLength(2));
    await c.setSelectedDay(DateTime(2026, 1, 1));
    expect(c.orders, hasLength(1));
    expect(c.orders.single.id, 'cccccccc-cccc-4ccc-8ccc-cccccccccccc');
    expect(c.dateScanTruncated, isFalse);
    await c.setSelectedDay(DateTime(2026, 1, 2));
    expect(c.orders, hasLength(1));
    expect(c.orders.single.id, 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb');
  });
  test('pending is saved before POST; uncertainty retries exact payload across '
      'relaunch and user scope', () async {
    await c.initialize();
    final posts = <http.Request>[];
    handler = (r) async {
      if (r.url.path.endsWith('/admin/me')) return staffResponse();
      if (r.method == 'GET') return http.Response('[]', 200);
      expect(store.values, isNotEmpty);
      posts.add(r);
      return http.Response('{}', 503);
    };
    final draft = ReorderDraft(
      customerName: 'A',
      items: [OrderDraftLine(productId: 'p', notes: 'unchanged')],
    );
    expect(await c.submitReorder(draft), isNull);
    expect(c.hasPendingAttempt, isTrue);
    final saved = store.values.values.single;
    expect(await c.submitReorder(draft), isNull);
    expect(posts.length, 1);
    await c.logout();
    expect(store.values.values.single, saved);
    expect(c.hasPendingAttempt, isFalse);
    await c.login('bob', 'pw');
    expect(c.hasPendingAttempt, isFalse);
    await c.logout();
    await c.login('alice', 'pw');
    expect(c.hasPendingAttempt, isTrue);
    await c.retryPending();
    expect(posts.length, 2);
    expect(posts[1].body, posts[0].body);
    expect(
      posts[1].headers['Idempotency-Key'],
      posts[0].headers['Idempotency-Key'],
    );
    expect(
      posts[1].headers['X-Order-Token'],
      posts[0].headers['X-Order-Token'],
    );
    handler = (r) async => http.Response(
      jsonEncode(r.method == 'POST' ? orderJson() : []),
      r.method == 'POST' ? 201 : 200,
    );
    expect(await c.retryPending(), isNotNull);
    expect(c.hasPendingAttempt, isFalse);
    expect(store.values, isEmpty);
  });
  test('only definitive 409 checkout_rejected clears saved attempt', () async {
    await c.initialize();
    var status = 409;
    var code = 'idempotency_conflict';
    handler = (r) async =>
        http.Response(jsonEncode({'error': 'sensitive', 'code': code}), status);
    final draft = ReorderDraft(
      customerName: 'A',
      items: [OrderDraftLine(productId: 'p')],
    );
    await c.submitReorder(draft);
    expect(c.hasPendingAttempt, isTrue);
    status = 400;
    code = 'checkout_rejected';
    await c.retryPending();
    expect(c.hasPendingAttempt, isTrue);
    status = 409;
    await c.retryPending();
    expect(c.hasPendingAttempt, isFalse);
    expect(store.values, isEmpty);
  });
  test('storage write failure prevents network and safe error', () async {
    await c.initialize();
    store.failWrite = true;
    var posts = 0;
    handler = (r) async {
      if (r.method == 'POST') posts++;
      return http.Response('{}', 500);
    };
    await c.submitReorder(
      ReorderDraft(
        customerName: 'A',
        items: [OrderDraftLine(productId: 'p')],
      ),
    );
    expect(posts, 0);
    expect(c.error, isNot(contains('secret')));
  });
  test(
    'claim guards review state and duplicate taps; background suppresses sound',
    () async {
      await c.initialize();
      var calls = 0;
      final pending = Completer<http.Response>();
      handler = (r) {
        calls++;
        return calls == 1
            ? pending.future
            : Future.value(http.Response('[]', 200));
      };
      expect(
        await c.claim(OrderRecord.fromJson(orderJson(reviewed: 1))),
        isNull,
      );
      expect(calls, 0);
      final first = c.claim(c.orders.first);
      await Future<void>.delayed(Duration.zero);
      expect(await c.claim(c.orders.first), isNull);
      expect(calls, 1);
      c.setForeground(false);
      rt.newOrder?.call();
      expect(c.newOrderSerial, 0);
      pending.complete(
        http.Response(
          jsonEncode(
            orderJson(
              status: 'pos_input',
              version: 3,
              posHandoff: posHandoffJson(),
            ),
          ),
          200,
        ),
      );
      await first;
      expect(c.busy, isFalse);
    },
  );
  test('auth switch during pending storage read cannot reveal previous user attempt', () async {
    final gate = Completer<String?>();
    store.readGate = gate;
    final init = c.initialize();
    await Future<void>.delayed(Duration.zero);
    await c.logout();
    gate.complete(null);
    await init;
    expect(c.signedIn, isFalse);
    expect(c.hasPendingAttempt, isFalse);
    expect(c.orders, isEmpty);
  });
}
