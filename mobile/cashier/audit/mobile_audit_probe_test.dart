// Regression probes from the audit. Included by test/audit_regressions_test.dart.
// Fixtures only: no restaurant network, credentials, or database access.
import 'dart:async';
import 'dart:convert';

import 'package:cashier/app.dart';
import 'package:cashier/core/order_watch.dart';
import 'package:cashier/data/cashier_api.dart';
import 'package:cashier/domain/models.dart';
import 'package:cashier/features/cashier/cashier_controller.dart';
import 'package:cashier/features/cashier/order_detail_screen.dart';
import 'package:cashier/features/cashier/order_editor_screen.dart';
import 'package:cashier/features/cashier/order_line_editor.dart';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import '../test/core/api_models_test.dart'
    show FakeAuth, config, orderJson, posHandoffJson;
import '../test/core/controller_test.dart' show FakeRealtime, MemoryStore;
import '../test/ui/cashier_app_test.dart'
    show FakeController, catalog, order, tap;

void main() {
  group('Controller audit', () {
    late FakeAuth auth;
    late CashierController controller;
    late Future<http.Response> Function(http.Request) handler;
    late List<http.Request> requests;

    setUp(() {
      auth = FakeAuth();
      requests = [];
      handler = (r) async {
        if (r.url.path.endsWith('/admin/me')) {
          return http.Response(
            jsonEncode({
              'id': 'alice',
              'full_name': 'Alice',
              'role': 'cashier',
            }),
            200,
          );
        }
        if (r.url.path.endsWith('/admin/sync')) {
          return http.Response('{"revision":"1"}', 200);
        }
        return http.Response(jsonEncode([orderJson()]), 200);
      };
      controller = CashierController(
        api: CashierApi(
          config: config(),
          auth: auth,
          client: MockClient((request) {
            requests.add(request);
            if (request.url.path.endsWith('/admin/sync')) {
              return Future.value(
                http.Response('{"revision":"1","new_orders":[]}', 200),
              );
            }
            return handler(request);
          }),
        ),
        auth: auth,
        realtime: FakeRealtime(auth),
        store: MemoryStore(),
      );
    });

    tearDown(() async {
      controller.dispose();
      await auth.events.close();
    });

    test(
      'P01 unchanged periodic refresh should reuse revision snapshot',
      () async {
        await controller.initialize();
        await controller.refresh();
        expect(
          requests.where((r) => r.url.path.endsWith('/admin/orders')).length,
          1,
          reason:
              'An unchanged revision must not download all order items again.',
        );
      },
    );

    test(
      'N01 changing a filter must not chime for an existing order',
      () async {
        await controller.initialize();
        handler = (r) async => http.Response(
          jsonEncode([orderJson(id: 'dddddddd-dddd-4ddd-8ddd-dddddddddddd')]),
          200,
        );
        await controller.setSearch('existing order on another result page');
        expect(controller.newOrderSerial, 0);
      },
    );

    test(
      'F01 conflict must reconcile authoritative state before retry',
      () async {
        await controller.initialize();
        requests.clear();
        handler = (r) async => r.method == 'POST'
            ? http.Response('{}', 409)
            : http.Response(jsonEncode([orderJson(status: 'pos_input')]), 200);
        await controller.claim(controller.orders.single);
        expect(
          requests.any((r) => r.method == 'GET'),
          isTrue,
          reason: 'The server may already have accepted this or another claim.',
        );
      },
    );

    test('P02 history polling should not repeatedly scan ten full pages', () async {
      await controller.initialize();
      handler = (r) async => http.Response(
        jsonEncode(
          List.generate(
            100,
            (i) => orderJson(
              id: 'aaaaaaaa-aaaa-4aaa-8aaa-${(int.parse(r.url.queryParameters['offset'] ?? '0') + i).toString().padLeft(12, '0')}',
              status: 'forwarded',
              createdAt: '2026-11-15T10:00:00Z',
            ),
          ),
        ),
        200,
      );
      await controller.changeTab('history');
      await controller.setSelectedDay(DateTime(2026, 1, 1));
      requests.clear();
      await controller.refresh();
      expect(
        requests.where((r) => r.url.path.endsWith('/admin/orders')).length,
        lessThanOrEqualTo(1),
        reason:
            'Unchanged history needs a revision check, not a ten-page scan.',
      );
    });
  });

  testWidgets('U01 background refresh must keep search usable', (tester) async {
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.binding.setSurfaceSize(const Size(1000, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final c = FakeController();
    await tester.pumpWidget(CashierApp(controller: c));
    await tester.pumpAndSettle();
    c.loading = true;
    c.emit();
    await tester.pump();
    final enabled = tester
        .widget<TextField>(find.byKey(const ValueKey('order-search')))
        .enabled;
    await tester.pumpWidget(const SizedBox());
    expect(enabled, isTrue);
  });

  testWidgets('F02 disappearing selected order must disable stale claim', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1000, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final c = FakeController()..orders = [order(reviewed: true)];
    await tester.pumpWidget(
      MaterialApp(
        home: OrderDetailScreen(controller: c, order: c.orders.single),
      ),
    );
    await tester.pumpAndSettle();
    c.orders = [];
    c.emit();
    await tester.pump();
    final claim = find.byKey(const ValueKey('claim-order'));
    final enabled =
        claim.evaluate().isNotEmpty &&
        tester.widget<FilledButton>(claim).onPressed != null;
    await tester.pumpWidget(const SizedBox());
    c.dispose();
    expect(
      enabled,
      isFalse,
      reason: 'An absent snapshot cannot prove ownership/state.',
    );
  });

  testWidgets('U02 quantity cannot exceed the backend limit of 50', (
    tester,
  ) async {
    OrderDraftLine? changed;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ListView(
            children: [
              OrderLineEditor(
                index: 0,
                line: OrderDraftLine(productId: 'coffee', quantity: 50),
                product: catalog().products.first,
                disabled: false,
                onChanged: (value) => changed = value,
                onRemove: () {},
              ),
            ],
          ),
        ),
      ),
    );
    await tester.tap(find.byKey(const ValueKey('qty-plus-0')));
    await tester.pumpWidget(const SizedBox());
    expect(changed, isNull, reason: 'The UI currently emits quantity 51.');
  });

  testWidgets('U03 review must require one choice in every available group', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1000, 1400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final c = FakeController();
    await tester.pumpWidget(
      MaterialApp(
        home: OrderEditorScreen(
          controller: c,
          catalog: catalog(),
          order: order(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tap(tester, 'editor-save');
    final sent = c.reviewedItems;
    await tester.pumpWidget(const SizedBox());
    c.dispose();
    expect(sent, isNull, reason: 'The mandatory Suhu group is empty.');
  });

  testWidgets('F03 POS checkboxes must reset after ownership/version changes', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1000, 1600));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final c = FakeController()..orders = [order(posInput: true)];
    await tester.pumpWidget(
      MaterialApp(
        home: OrderDetailScreen(controller: c, order: c.orders.single),
      ),
    );
    await tester.pumpAndSettle();
    await tap(tester, 'entered-in-pos');
    await tap(tester, 'paid-in-pos');
    c.orders = [
      OrderRecord.fromJson(
        orderJson(
          id: 'order-1',
          status: 'pos_input',
          version: 4,
          posHandoff: posHandoffJson(cashierId: 'bob', cashierName: 'Bob'),
        ),
      ),
    ];
    c.emit();
    await tester.pumpAndSettle();
    c.orders = [
      OrderRecord.fromJson(
        orderJson(
          id: 'order-1',
          status: 'pos_input',
          version: 5,
          posHandoff: posHandoffJson(),
        ),
      ),
    ];
    c.emit();
    await tester.pumpAndSettle();
    final checked = tester
        .widget<CheckboxListTile>(find.byKey(const ValueKey('paid-in-pos')))
        .value;
    await tester.pumpWidget(const SizedBox());
    c.dispose();
    expect(checked, isFalse);
  });

  testWidgets('U04 compact landscape with keyboard should not overflow', (
    tester,
  ) async {
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.binding.setSurfaceSize(const Size(640, 360));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    tester.view.viewInsets = const FakeViewPadding(bottom: 180);
    addTearDown(tester.view.resetViewInsets);
    final c = FakeController();
    await tester.pumpWidget(CashierApp(controller: c));
    await tester.pump();
    final exception = tester.takeException();
    await tester.pumpWidget(const SizedBox());
    expect(exception, isNull);
  });

  testWidgets('S03 delayed watcher start must not outlive stop/logout', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    const channel = MethodChannel('id.alrizky.teraskayumanis.cashier/watch');
    final permission = Completer<bool>();
    final calls = <String>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (
      call,
    ) async {
      calls.add(call.method);
      if (call.method == 'ensureNotificationPermission') {
        return permission.future;
      }
      return true;
    });
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        channel,
        null,
      ),
    );
    final auth = FakeAuth();
    final api = CashierApi(
      config: config(),
      auth: auth,
      client: MockClient((request) async {
        fail('Permission result after stop must not issue a lease');
      }),
    );
    final watch = OrderWatch(config(), auth, api: api);
    final pending = watch.prepare();
    await tester.pump();
    await watch.stop(clear: true);
    permission.complete(true);
    await pending;
    final nativeStartedAfterStop =
        calls.indexOf('start') > calls.indexOf('stop');
    await watch.stop(clear: true);
    await auth.events.close();
    api.close();
    debugDefaultTargetPlatformOverride = null;
    expect(
      nativeStartedAfterStop,
      isFalse,
      reason: 'A late permission response restarts the service after stop.',
    );
  });

  testWidgets('P04 countdown tick must not rebuild all 50 detail item rows', (
    tester,
  ) async {
    final json = orderJson();
    json['order_items'] = List.generate(
      50,
      (_) => (orderJson()['order_items'] as List).first,
    );
    final record = OrderRecord.fromJson(json);
    final c = FakeController()..orders = [record];
    await tester.pumpWidget(
      MaterialApp(
        home: OrderDetailScreen(controller: c, order: record),
      ),
    );
    await tester.pumpAndSettle();
    var itemBuilds = 0;
    debugOnRebuildDirtyWidget = (element, builtOnce) {
      if (element.widget.runtimeType.toString() == '_ItemRow') itemBuilds++;
    };
    addTearDown(() => debugOnRebuildDirtyWidget = null);
    // Production reads DateTime.now(), which WidgetTester.pump's fake clock
    // does not advance. Cross a real second before firing its periodic timer.
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 1100)),
    );
    await tester.pump(const Duration(seconds: 1));
    debugOnRebuildDirtyWidget = null;
    await tester.pumpWidget(const SizedBox());
    c.dispose();
    expect(
      itemBuilds,
      0,
      reason:
          'Only countdown/actions should react to the clock. Observed item rebuilds: $itemBuilds',
    );
  });

  testWidgets('P05 editing notes must not rebuild a sibling line editor', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1000, 2200));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final json = orderJson();
    json['order_items'] = List.generate(
      2,
      (_) => {
        ...Map<String, dynamic>.from(
          (orderJson()['order_items'] as List).first as Map,
        ),
        'product_id': 'coffee',
        'variant_ids': <String>[],
        'addon_ids': <String>[],
      },
    );
    final c = FakeController();
    await tester.pumpWidget(
      MaterialApp(
        home: OrderEditorScreen(
          controller: c,
          catalog: catalog(),
          order: OrderRecord.fromJson(json),
        ),
      ),
    );
    await tester.pumpAndSettle();
    var siblingBuilds = 0;
    debugOnRebuildDirtyWidget = (element, builtOnce) {
      final widget = element.widget;
      if (widget is OrderLineEditor && widget.index == 1) siblingBuilds++;
    };
    addTearDown(() => debugOnRebuildDirtyWidget = null);
    await tester.enterText(find.byKey(const ValueKey('notes-0')), 'tanpa gula');
    await tester.pump();
    debugOnRebuildDirtyWidget = null;
    await tester.pumpWidget(const SizedBox());
    c.dispose();
    expect(
      siblingBuilds,
      0,
      reason: 'Typing in one line must not rebuild the other line.',
    );
  });
}
