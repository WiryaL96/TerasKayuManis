import 'dart:async';
import 'dart:convert';

import 'package:cashier/data/cashier_api.dart';
import 'package:cashier/data/pos_attempt.dart';
import 'package:cashier/features/cashier/cashier_controller.dart';
import 'package:cashier/features/cashier/order_detail_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'api_models_test.dart' show FakeAuth, config, orderJson, posHandoffJson;
import 'controller_test.dart' show FakeRealtime, MemoryStore;
import '../ui/cashier_app_test.dart' show tap;

const _id = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa';
const _otherId = 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb';
http.Response missingRoute() => http.Response(
  '404 page not found\n',
  404,
  headers: {'content-type': 'text/plain; charset=utf-8'},
);
http.Response jsonResponse(Object data, {int status = 200}) =>
    http.Response(jsonEncode(data), status);

class DetailFixture {
  DetailFixture() {
    api = CashierApi(
      config: config(),
      auth: auth,
      client: MockClient((request) async {
        requests.add(request);
        if (!request.url.path.endsWith('/menu')) {
          expect(request.headers['Authorization'], 'Bearer token');
        }
        if (request.url.path.endsWith('/admin/me')) {
          return jsonResponse({
            'id': 'alice',
            'full_name': 'Alice',
            'role': 'cashier',
          });
        }
        if (request.url.path.endsWith('/admin/sync')) {
          return jsonResponse({'revision': '${row['version']}'});
        }
        if (request.url.path.endsWith('/admin/orders/$_id')) {
          return primary;
        }
        if (request.url.path.endsWith('/admin/orders')) {
          if (!request.url.queryParameters.containsKey('summary')) {
            final handler = fullHandler;
            if (handler != null) return handler(request);
          }
          final history = [
            'forwarded',
            'expired',
            'completed',
            'cancelled',
          ].contains(row['status']);
          return jsonResponse(
            (request.url.queryParameters['tab'] == 'history') == history
                ? [row]
                : [],
          );
        }
        if (request.url.path.endsWith('/menu')) {
          return jsonResponse({
            'settings': {},
            'products': [
              {
                'id': 'p',
                'name': 'Coffee',
                'price': 6000,
                'is_available': true,
                'variants': [
                  {
                    'id': 'v',
                    'name': 'Hot',
                    'group_name': 'Temperature',
                    'price_modifier': 0,
                    'is_available': true,
                  },
                ],
                'addons': [
                  {'id': 'a', 'name': 'Milk', 'price': 0, 'is_available': true},
                ],
              },
            ],
          });
        }
        final body = jsonDecode(request.body) as Map;
        expect(body['expected_version'], row['version']);
        if (request.url.path.endsWith('/review')) {
          expect(body['items'], isNotEmpty);
          row = orderJson(version: 3, reviewed: 3);
        } else if (request.url.path.endsWith('/claim-pos')) {
          expect(row['reviewed_version'], row['version']);
          row = orderJson(
            version: 4,
            reviewed: 3,
            status: 'pos_input',
            posHandoff: posHandoffJson(),
          );
        } else if (request.url.path.endsWith('/forward-pos')) {
          expect(body['entered_in_pos'], isTrue);
          expect(body['paid_in_pos'], isTrue);
          expect(store.values, isNotEmpty);
          row = orderJson(
            version: 5,
            reviewed: 3,
            status: 'forwarded',
            posHandoff: posHandoffJson(forwardedAt: '2026-01-01T00:15:00Z'),
          );
        } else {
          fail('Unexpected request ${request.method} ${request.url.path}');
        }
        return jsonResponse(
          row,
          status:
              loseForwardResponse && request.url.path.endsWith('/forward-pos')
              ? 503
              : 200,
        );
      }),
    );
    controller = CashierController(
      api: api,
      auth: auth,
      realtime: FakeRealtime(auth),
      store: store,
    );
  }

  final auth = FakeAuth();
  final store = MemoryStore();
  final requests = <http.Request>[];
  late final CashierApi api;
  late final CashierController controller;
  Map<String, dynamic> row = orderJson(reviewed: null);
  http.Response primary = missingRoute();
  bool loseForwardResponse = false;
  Future<http.Response> Function(http.Request)? fullHandler;

  Future<void> dispose() async {
    controller.dispose();
    await auth.events.close();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('missing detail route uses fresh full staff list and exact ID, not first search match', () async {
    final fixture = DetailFixture();
    addTearDown(fixture.dispose);
    fixture.fullHandler = (request) async {
      expect(request.url.queryParameters, {
        'tab': 'active',
        'q': 'TKM-1',
        'sort': 'newest',
        'offset': '0',
      });
      return jsonResponse([orderJson(id: _otherId), orderJson(version: 4)]);
    };
    final row = await fixture.api.detail(_id, orderNumber: 'TKM-1');
    expect(row.id, _id);
    expect(row.version, 4);
    expect(row.items, isNotEmpty);
    expect(fixture.requests, hasLength(2));
    expect(fixture.requests.every((r) => r.method == 'GET'), isTrue);
  });

  test(
    'modern detail stays a single read and rejects a mismatched ID',
    () async {
      final fixture = DetailFixture()..primary = jsonResponse(orderJson());
      addTearDown(fixture.dispose);
      expect((await fixture.api.detail(_id)).id, _id);
      expect(fixture.requests, hasLength(1));
      fixture.primary = jsonResponse(orderJson(id: _otherId));
      await expectLater(fixture.api.detail(_id), throwsA(isA<ApiException>()));
      expect(fixture.requests, hasLength(2));
    },
  );

  test(
    'order moving from active to history is verified as expired, not pending',
    () async {
      final fixture = DetailFixture()
        ..row = orderJson(status: 'expired', version: 4);
      addTearDown(fixture.dispose);
      final row = await fixture.api.detail(_id, orderNumber: 'TKM-1');
      expect(row.status, 'expired');
      expect(row.canReview(DateTime.now()), isFalse);
      expect(fixture.requests.map((r) => r.url.queryParameters['tab']), [
        null,
        'active',
        'history',
      ]);
    },
  );

  test(
    'real not-found, authorization and server errors never use fallback',
    () async {
      for (final status in [401, 403, 404, 429, 503]) {
        final fixture = DetailFixture()
          ..primary = jsonResponse({
            'error': 'private backend error',
          }, status: status);
        try {
          await expectLater(
            fixture.api.detail(_id, orderNumber: 'TKM-1'),
            throwsA(
              isA<ApiException>().having((e) => e.status, 'status', status),
            ),
          );
          expect(fixture.requests, hasLength(1));
        } finally {
          await fixture.dispose();
        }
      }
    },
  );

  test('missing, duplicate, malformed or summary-only fallback data never verify detail', () async {
    for (final data in <Object>[
      {},
      [],
      [orderJson(id: _otherId)],
      [orderJson(), orderJson()],
      [orderJson()..remove('order_items')],
      [orderJson()..['order_items'] = []],
      [orderJson()..['version'] = 0],
      [orderJson()..['expires_at'] = 'invalid'],
    ]) {
      final fixture = DetailFixture()
        ..fullHandler = (_) async => jsonResponse(data);
      try {
        await expectLater(
          fixture.api.detail(_id, orderNumber: 'TKM-1'),
          throwsA(isA<ApiException>()),
        );
      } finally {
        await fixture.dispose();
      }
    }
  });

  test(
    'search collisions page within a bound without using visible filters',
    () async {
      final fixture = DetailFixture();
      addTearDown(fixture.dispose);
      fixture.fullHandler = (request) async {
        return jsonResponse(
          request.url.queryParameters['offset'] == '0'
              ? List.generate(100, (_) => orderJson(id: _otherId))
              : [orderJson()],
        );
      };
      expect((await fixture.api.detail(_id, orderNumber: 'TKM-1')).id, _id);
      expect(fixture.requests.last.url.queryParameters['offset'], '100');
      fixture.requests.clear();
      fixture.fullHandler = (_) async =>
          jsonResponse(List.generate(100, (_) => orderJson(id: _otherId)));
      await expectLater(
        fixture.api.detail(_id, orderNumber: 'TKM-1'),
        throwsA(
          isA<ApiException>().having(
            (e) => e.message,
            'message',
            contains('belum lengkap'),
          ),
        ),
      );
      expect(fixture.requests, hasLength(7));
    },
  );

  test('fallback cannot continue under another staff session', () async {
    final fixture = DetailFixture();
    addTearDown(fixture.dispose);
    fixture.fullHandler = (_) async {
      fixture.auth.id = 'bob';
      fixture.auth.events.add(null);
      return jsonResponse([orderJson()]);
    };
    await expectLater(
      fixture.api.detail(_id, orderNumber: 'TKM-1'),
      throwsA(isA<ApiException>()),
    );
    expect(fixture.requests, hasLength(2));
  });

  test('detail remains locked until a fresh full response and after a version rollback', () async {
    final fixture = DetailFixture();
    addTearDown(fixture.dispose);
    final c = fixture.controller;
    await c.initialize();
    final gate = Completer<http.Response>();
    fixture.fullHandler = (_) => gate.future;
    final state = c.watchDetail(c.orders.single);
    final pending = c.refreshDetail(_id);
    expect(state.value.usable, isFalse);
    gate.complete(jsonResponse([orderJson(version: 5)]));
    await pending;
    expect(state.value.usable, isTrue);
    fixture.fullHandler = (_) async => jsonResponse([orderJson(version: 4)]);
    await c.refreshDetail(_id);
    expect(state.value.usable, isFalse);
    expect(state.value.order?.version, 5);
    expect(state.value.error, contains('belum terbaru'));
    c.releaseDetail(_id);
  });

  test(
    'fallback authorization denial clears session and stale detail',
    () async {
      final fixture = DetailFixture();
      addTearDown(fixture.dispose);
      await fixture.controller.initialize();
      fixture.fullHandler = (_) async => jsonResponse({}, status: 403);
      final state = fixture.controller.watchDetail(
        fixture.controller.orders.single,
      );
      await fixture.controller.refreshDetail(_id);
      expect(fixture.controller.signedIn, isFalse);
      expect(state.value.usable, isFalse);
      expect(fixture.controller.orders, isEmpty);
      fixture.controller.releaseDetail(_id);
    },
  );

  test('stored POS lookup hint survives restart and legacy intents remain readable', () {
    final saved = PosAttempt(_id, 4, 'POS-test', orderNumber: 'TKM-1');
    expect(PosAttempt.decode(saved.encode()).orderNumber, 'TKM-1');
    expect(
      PosAttempt.decode(PosAttempt(_id, 4, 'POS-test').encode()).orderNumber,
      isNull,
    );
    for (final number in ['', 'a' * 81, 'A\u0000']) {
      expect(
        () => PosAttempt.decode(
          PosAttempt(_id, 4, '', orderNumber: number).encode(),
        ),
        throwsFormatException,
      );
    }
  });

  test(
    'uncertain POS response reconciles from fresh history without resubmitting',
    () async {
      final fixture = DetailFixture()
        ..row = orderJson(
          version: 4,
          status: 'pos_input',
          posHandoff: posHandoffJson(),
        )
        ..loseForwardResponse = true;
      addTearDown(fixture.dispose);
      await fixture.controller.initialize();
      final result = await fixture.controller.forward(
        fixture.controller.orders.single,
        enteredInPos: true,
        paidInPos: true,
      );
      expect(result?.status, 'forwarded');
      expect(fixture.controller.hasPendingPos, isFalse);
      expect(fixture.store.values, isEmpty);
      expect(fixture.requests.where((r) => r.method == 'POST'), hasLength(1));
      expect(
        fixture.requests.any(
          (r) =>
              r.url.queryParameters['tab'] == 'history' &&
              r.url.queryParameters['q'] == 'TKM-1' &&
              !r.url.queryParameters.containsKey('summary'),
        ),
        isTrue,
      );
    },
  );

  testWidgets(
    'legacy full detail unlocks review, saves current version, and completes confirmed POS flow',
    (tester) async {
      final fixture = DetailFixture();
      addTearDown(fixture.dispose);
      await fixture.controller.initialize();
      await tester.binding.setSurfaceSize(const Size(1000, 1400));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        MaterialApp(
          home: OrderDetailScreen(
            controller: fixture.controller,
            order: fixture.controller.orders.single,
          ),
        ),
      );
      await tester.pumpAndSettle();
      final review = find.byKey(const ValueKey('open-review'));
      await tester.ensureVisible(review);
      expect(tester.widget<FilledButton>(review).onPressed, isNotNull);
      expect(
        find.textContaining('Status belum dapat dipastikan'),
        findsNothing,
      );

      await tap(tester, 'open-review');
      await tap(tester, 'editor-save');
      expect(fixture.row['reviewed_version'], 3);
      expect(find.byKey(const ValueKey('claim-order')), findsOneWidget);
      await tap(tester, 'claim-order');
      await tap(tester, 'confirm-yes');
      expect(fixture.row['status'], 'pos_input');
      await tap(tester, 'entered-in-pos');
      await tap(tester, 'paid-in-pos');
      await tap(tester, 'forward-order');
      await tap(tester, 'confirm-yes');
      expect(fixture.row['status'], 'forwarded');
      expect(fixture.controller.hasPendingPos, isFalse);
      expect(fixture.store.values, isEmpty);
      expect(
        fixture.requests
            .where((r) => r.method == 'POST')
            .map((r) => r.url.path.split('/').last),
        ['review', 'claim-pos', 'forward-pos'],
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );
}
