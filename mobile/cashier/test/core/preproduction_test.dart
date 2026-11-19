import 'dart:async';
import 'dart:convert';

import 'package:cashier/data/cashier_api.dart';
import 'package:cashier/domain/models.dart';
import 'package:cashier/features/cashier/cashier_controller.dart';
import 'package:cashier/features/cashier/ui_common.dart' show formatDateTime;
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'api_models_test.dart' show config, FakeAuth, orderJson, posHandoffJson;
import 'controller_test.dart' show MemoryStore, FakeRealtime;

void main() {
  test(
    'timestamps use the same WIB day as history queries regardless of offset',
    () {
      expect(
        formatDateTime(DateTime.parse('2026-11-15T17:30:00Z')),
        '16 Nov 2026, 00:30 WIB',
      );
      expect(
        formatDateTime(DateTime.parse('2026-11-16T01:30:00+08:00')),
        '16 Nov 2026, 00:30 WIB',
      );
    },
  );
  late FakeAuth auth;
  late MemoryStore store;
  late CashierController controller;
  late Future<http.Response> Function(http.Request) detailHandler;
  late List<http.Request> requests;
  setUp(() {
    auth = FakeAuth();
    store = MemoryStore();
    requests = [];
    detailHandler = (_) async => http.Response(jsonEncode(orderJson()), 200);
    controller = CashierController(
      api: CashierApi(
        config: config(),
        auth: auth,
        client: MockClient((r) async {
          requests.add(r);
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
          return detailHandler(r);
        }),
      ),
      auth: auth,
      realtime: FakeRealtime(auth),
      store: store,
    );
  });
  tearDown(() async {
    controller.dispose();
    await auth.events.close();
  });

  test(
    'failed detail recovers on unchanged revision without a full list refetch',
    () async {
      await controller.initialize();
      detailHandler = (_) async => http.Response('{}', 503);
      final order = OrderRecord.fromJson(orderJson());
      final state = controller.watchDetail(order);
      await controller.refreshDetail(order.id);
      expect(state.value.usable, isFalse);
      detailHandler = (_) async => http.Response(jsonEncode(orderJson()), 200);
      await controller.refresh();
      expect(state.value.usable, isTrue);
      expect(
        requests.where((r) => r.url.path.endsWith('/admin/orders')),
        hasLength(1),
      );
      controller.releaseDetail(order.id);
    },
  );

  test(
    'reopening a detail detaches the request belonging to the disposed view',
    () async {
      await controller.initialize();
      final first = Completer<http.Response>();
      var calls = 0;
      detailHandler = (_) => ++calls == 1
          ? first.future
          : Future.value(http.Response(jsonEncode(orderJson()), 200));
      final order = OrderRecord.fromJson(orderJson());
      controller.watchDetail(order);
      await Future<void>.delayed(Duration.zero);
      controller.releaseDetail(order.id);
      final reopened = controller.watchDetail(order);
      final refreshed = controller.refreshDetail(order.id);
      first.complete(http.Response(jsonEncode(orderJson(version: 1)), 200));
      await refreshed;
      expect(calls, 2);
      expect(reopened.value.usable, isTrue);
      expect(reopened.value.order!.version, 2);
      controller.releaseDetail(order.id);
    },
  );

  test(
    'response from before pause cannot reauthorize detail actions',
    () async {
      await controller.initialize();
      final response = Completer<http.Response>();
      detailHandler = (_) => response.future;
      final order = OrderRecord.fromJson(orderJson());
      final state = controller.watchDetail(order);
      final pending = controller.refreshDetail(order.id);
      await Future<void>.delayed(Duration.zero);
      controller.setForeground(false);
      response.complete(http.Response(jsonEncode(orderJson()), 200));
      await pending;
      expect(state.value.usable, isFalse);
      controller.releaseDetail(order.id);
    },
  );

  test(
    'invalid POS reference never becomes a durable unrecoverable intent',
    () async {
      await controller.initialize();
      final order = OrderRecord.fromJson(
        orderJson(
          status: 'pos_input',
          version: 3,
          posHandoff: posHandoffJson(),
        ),
      );
      expect(
        await controller.forward(
          order,
          enteredInPos: true,
          paidInPos: true,
          reference: 'POS\u0000test',
        ),
        isNull,
      );
      expect(store.values, isEmpty);
      expect(controller.hasPendingPos, isFalse);
      expect(requests.where((r) => r.method == 'POST'), isEmpty);
    },
  );
}
