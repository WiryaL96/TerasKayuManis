import 'dart:convert';

import 'package:cashier/core/app_config.dart';
import 'package:cashier/core/realtime_client.dart';
import 'package:cashier/data/cashier_api.dart';
import 'package:cashier/data/order_snapshot_store.dart';
import 'package:cashier/domain/models.dart';
import 'package:cashier/features/cashier/cashier_controller.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'api_models_test.dart' show config, FakeAuth, orderJson, posHandoffJson;
import 'controller_test.dart' show MemoryStore, FakeRealtime;

void main() {
  test(
    'summary order count survives loading full detail at same version',
    () async {
      final auth = FakeAuth();
      final summary = OrderRecord.fromJson({
        ...orderJson(),
        'item_count': 25,
        'order_items': <Object>[],
      });
      expect(summary.itemCount, 25);
      final c = CashierController(
        api: CashierApi(
          config: config(),
          auth: auth,
          client: MockClient((r) async {
            if (r.url.path.endsWith('/admin/me')) {
              return http.Response(
                '{"id":"alice","full_name":"Alice","role":"cashier"}',
                200,
              );
            }
            if (r.url.path.endsWith('/admin/sync')) {
              return http.Response('{"revision":"1","new_orders":[]}', 200);
            }
            if (r.url.path.endsWith('/admin/orders')) {
              return http.Response('[]', 200);
            }
            return http.Response(jsonEncode(orderJson()), 200);
          }),
        ),
        auth: auth,
        realtime: FakeRealtime(auth),
        store: MemoryStore(),
      );
      await c.initialize();
      final detail = c.watchDetail(summary);
      await c.refreshDetail(summary.id);
      expect(detail.value.usable, isTrue);
      expect(detail.value.order!.items, isNotEmpty);
      c.releaseDetail(summary.id);
      c.dispose();
      await auth.events.close();
    },
  );
  test('uncertain POS confirmation survives restart and retries exact version/reference', () async {
    final auth = FakeAuth(), store = MemoryStore();
    final posts = <String>[];
    var committed = false;
    Map<String, dynamic> row() => orderJson(
      status: committed ? 'forwarded' : 'pos_input',
      version: committed ? 4 : 3,
      posHandoff: posHandoffJson(
        posReference: 'POS-test',
        forwardedAt: committed ? '2026-11-15T10:00:00Z' : null,
      ),
    );
    CashierController make() => CashierController(
      api: CashierApi(
        config: config(),
        auth: auth,
        client: MockClient((r) async {
          if (r.url.path.endsWith('/admin/me')) {
            return http.Response(
              '{"id":"alice","full_name":"Alice","role":"cashier"}',
              200,
            );
          }
          if (r.url.path.endsWith('/admin/sync')) {
            return http.Response('{"revision":"1","new_orders":[]}', 200);
          }
          if (r.url.path.endsWith('/forward-pos')) {
            expect(
              store.values.keys.any((key) => key.endsWith('.pos')),
              isTrue,
            );
            posts.add(r.body);
            return committed
                ? http.Response(jsonEncode(row()), 200)
                : http.Response('{}', 503);
          }
          if (r.url.path.endsWith('/admin/orders')) {
            return http.Response(jsonEncode([row()]), 200);
          }
          return http.Response('{}', 503);
        }),
      ),
      auth: auth,
      realtime: FakeRealtime(auth),
      store: store,
    );
    var c = make();
    await c.initialize();
    final order = c.orders.single;
    expect(
      await c.forward(
        order,
        enteredInPos: true,
        paidInPos: true,
        reference: 'POS-test',
      ),
      isNull,
    );
    expect(c.hasPendingPos, isTrue);
    await c.forward(
      order,
      enteredInPos: true,
      paidInPos: true,
      reference: 'changed',
    );
    expect(posts, hasLength(1));
    c.dispose();
    c = make();
    await c.initialize();
    expect(c.hasPendingPos, isTrue);
    committed = true;
    expect((await c.retryPos())?.status, 'forwarded');
    expect(posts, hasLength(2));
    expect(posts.last, posts.first);
    expect(c.hasPendingPos, isFalse);
    expect(store.values, isEmpty);
    c.dispose();
    await auth.events.close();
  });

  test(
    'history tab receives arrivals independently from its visible rows',
    () async {
      final auth = FakeAuth();
      var revision = 1;
      var arrivals = <String>[];
      var lists = 0;
      final c = CashierController(
        api: CashierApi(
          config: config(),
          auth: auth,
          client: MockClient((r) async {
            if (r.url.path.endsWith('/admin/me')) {
              return http.Response(
                '{"id":"alice","full_name":"Alice","role":"cashier"}',
                200,
              );
            }
            if (r.url.path.endsWith('/admin/sync')) {
              return http.Response(
                jsonEncode({'revision': '$revision', 'new_orders': arrivals}),
                200,
              );
            }
            lists++;
            return http.Response('[]', 200);
          }),
        ),
        auth: auth,
        realtime: FakeRealtime(auth),
        store: MemoryStore(),
      );
      await c.initialize();
      await c.changeTab('history');
      final before = lists;
      await c.refresh();
      expect(lists, before);
      arrivals = ['aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa'];
      revision++;
      await c.refresh();
      expect(c.tab, 'history');
      expect(c.newOrderSerial, 1);
      expect(c.orders, isEmpty);
      await c.setSearch('old item');
      expect(c.newOrderSerial, 1);
      c.dispose();
      await auth.events.close();
    },
  );

  test('cached versions cannot move backwards', () {
    final store = OrderSnapshotStore();
    final newer = OrderRecord.fromJson(orderJson(version: 5));
    store.save('queue', '2', [newer]);
    expect(
      store.save('queue', '1', [
        OrderRecord.fromJson(orderJson(version: 3)),
      ]).single,
      same(newer),
    );
    store.dispose();
  });

  test(
    'polling mode never attempts websocket connection on start or reconnect',
    () async {
      final auth = FakeAuth(), original = config();
      final polling = AppConfig(
        apiBase: original.apiBase,
        wsUrl: original.wsUrl,
        wsOrigin: original.wsOrigin,
        supabaseUrl: original.supabaseUrl,
        supabaseKey: original.supabaseKey,
        pollingOnly: true,
      );
      var connections = 0, invalidations = 0;
      RealtimeStatus? status;
      final rt = RealtimeClient(
        polling,
        auth,
        connector: (_, _) async {
          connections++;
          throw StateError('unexpected socket');
        },
      );
      rt.start(
        onInvalidate: () => invalidations++,
        onStatus: (value) => status = value,
        onNewOrder: () {},
      );
      rt.reconnect();
      expect(connections, 0);
      expect(status, RealtimeStatus.polling);
      expect(invalidations, 1);
      rt.dispose();
      await auth.events.close();
    },
  );
}
