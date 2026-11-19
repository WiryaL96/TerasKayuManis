import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:cashier/core/app_config.dart';
import 'package:cashier/data/auth_session.dart';
import 'package:cashier/data/cashier_api.dart';
import 'package:cashier/domain/models.dart';

AppConfig config({
  String key = 'sb_publishable_test',
  String base = 'https://example.test/api/core/',
}) => AppConfig(
  apiBase: Uri.parse(base),
  wsUrl: Uri.parse('wss://example.test/ws'),
  wsOrigin: 'https://example.test',
  supabaseUrl: 'https://auth.test',
  supabaseKey: key,
);

class FakeAuth implements AuthSession {
  String? id = 'alice';
  String? token = 'token';
  final events = StreamController<void>.broadcast(sync: true);
  @override
  String? get userId => id;
  @override
  String? get refreshToken => id == null ? null : 'test-refresh';
  @override
  Future<String?> accessToken() async => token;
  @override
  Stream<void> get changes => events.stream;
  @override
  Future<void> signIn(String email, String password) async {
    id = email;
    events.add(null);
  }

  @override
  Future<void> installSession(String refreshToken) async {
    token = refreshToken;
    id = refreshToken.startsWith('fixture:')
        ? refreshToken.substring(8)
        : id ?? 'alice';
    events.add(null);
  }

  @override
  Future<void> signOut() async {
    id = null;
    events.add(null);
  }
}

Map<String, dynamic> posHandoffJson({
  String cashierId = 'alice',
  String cashierName = 'Alice',
  String? forwardedAt,
  String posReference = '',
}) => {
  'cashier_id': cashierId,
  'cashier_name': cashierName,
  'claimed_at': '2026-01-01T00:05:00Z',
  'forwarded_at': forwardedAt,
  'pos_reference': posReference,
};

Map<String, dynamic> orderJson({
  String id = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
  String status = 'pending',
  String payment = 'unpaid',
  int version = 2,
  int? reviewed = 2,
  Map<String, dynamic>? posHandoff,
  String createdAt = '2026-01-01T00:00:00Z',
}) => {
  'id': id,
  'order_number': 'TKM-1',
  'customer_name': 'A',
  'status': status,
  'payment_status': payment,
  'version': version,
  'reviewed_version': reviewed,
  'total': 12500,
  'created_at': createdAt,
  'expires_at': '2099-01-01T00:00:00Z',
  // tkm.order_json (0005_shared_qr_checkout.sql), not checkout's items.
  'tables': null,
  'pos_handoff': posHandoff,
  'order_items': [
    {
      'id': 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb',
      'order_item_addons': [
        {'addon_id': 'a', 'addon_name': 'Milk', 'price': 0},
      ],
      'product_id': 'p',
      'product_name': 'Coffee',
      'quantity': 2,
      'unit_price': 6000,
      'subtotal': 12000,
      'variant_ids': ['v'],
      'addon_ids': ['a'],
      'notes': 'hot',
    },
  ],
};
void main() {
  test(
    'config rejects unsafe endpoints and privileged keys without leaking',
    () {
      for (final base in [
        'http://example.test/',
        'https://u:secret@example.test/',
        'https://example.test/?secret=x',
        'https://example.test/#x',
      ]) {
        expect(() => config(base: base), throwsFormatException);
      }
      final roleClaims = base64Url
          .encode(utf8.encode('{"role":"service_role"}'))
          .replaceAll('=', '');
      for (final key in ['sb_secret_secret', 'e30.$roleClaims.sig', '']) {
        expect(() => config(key: key), throwsFormatException);
      }
      expect(config().apiBase.path, '/api/core/');
    },
  );
  test('models retain choices, backend totals, strict review and POS handoff guards', () {
    final o = OrderRecord.fromJson(orderJson());
    expect(o.total, 12500);
    expect(o.itemCount, 2);
    expect(o.canReview(DateTime.utc(2026)), isTrue);
    expect(o.canClaim(DateTime.utc(2026)), isTrue);
    expect(o.canReview(DateTime.utc(2099)), isFalse);
    expect(
      OrderRecord.fromJson(orderJson(reviewed: 1)).canClaim(DateTime.utc(2026)),
      isFalse,
    );
    final pos = OrderRecord.fromJson(
      orderJson(status: 'pos_input', reviewed: 2, posHandoff: posHandoffJson()),
    );
    expect(pos.isPosInput, isTrue);
    expect(pos.pausedRemaining, isNotNull);
    expect(pos.isStalePosClaim(DateTime.utc(2026, 1, 1, 0, 10)), isFalse);
    expect(pos.isStalePosClaim(DateTime.utc(2026, 1, 1, 0, 16)), isTrue);
    expect(pos.canForwardFor('alice'), isTrue);
    expect(pos.canForwardFor('bob'), isFalse);
    expect(pos.canTakeOverFor(staffId: 'bob', isAdmin: true), isTrue);
    expect(pos.canTakeOverFor(staffId: 'bob', isAdmin: false), isFalse);
    expect(pos.posHandoff!.cashierName, 'Alice');
    final forwarded = OrderRecord.fromJson(
      orderJson(
        status: 'forwarded',
        version: 3,
        posHandoff: posHandoffJson(
          forwardedAt: '2026-01-01T00:10:00Z',
          posReference: 'POS-1',
        ),
      ),
    );
    expect(forwarded.isForwarded, isTrue);
    expect(forwarded.posHandoff!.forwardedAt, isNotNull);
    expect(forwarded.posHandoff!.posReference, 'POS-1');
    expect(o.items.single.toDraft().toJson(), {
      'product_id': 'p',
      'quantity': 2,
      'variant_ids': ['v'],
      'addon_ids': ['a'],
      'notes': 'hot',
    });
    final draft = ReorderDraft.fromJson({
      'customer_name': 'A',
      'payment_method': 'cash',
      'items': [o.items.single.toDraft().toJson()],
    });
    expect(draft.toJson().containsKey('table_token'), isFalse);
    expect(draft.toJson()['payment_method'], 'cash');
    expect(() => o.items.add(o.items.first), throwsUnsupportedError);
  });
  test('menu uses actual backend settings and availability fields', () {
    final menu = Catalog.fromJson({
      'settings': {'require_customer_name': true},
      'products': [
        {
          'id': 'p',
          'name': 'Coffee',
          'price': 100,
          'is_available': false,
          'variants': [
            {
              'id': 'v',
              'name': 'L',
              'group_name': 'Size',
              'price_modifier': 20,
              'is_available': true,
            },
          ],
          'addons': [
            {'id': 'a', 'name': 'Milk', 'price': 30, 'is_available': false},
          ],
        },
      ],
    });
    expect(menu.requireCustomerName, isTrue);
    expect(menu.products.single.available, isFalse);
    expect(menu.products.single.variants.single.groupName, 'Size');
    expect(menu.products.single.addons.single.price, 30);
  });
  test(
    'API routing, staff profile, filters and POS handoff payloads',
    () async {
      final requests = <http.Request>[];
      final api = CashierApi(
        config: config(),
        auth: FakeAuth(),
        client: MockClient((r) async {
          requests.add(r);
          if (r.url.path.endsWith('admin/me')) {
            return http.Response(
              jsonEncode({
                'id': 'alice',
                'full_name': 'Alice',
                'role': 'admin',
              }),
              200,
            );
          }
          return http.Response(
            jsonEncode(
              r.url.path.endsWith('admin/orders') ? [orderJson()] : orderJson(),
            ),
            200,
          );
        }),
      );
      await api.listOrders(
        tab: 'history',
        status: 'forwarded',
        search: 'Kopi',
        sort: 'oldest',
        offset: 100,
      );
      expect(requests.last.url.queryParameters, {
        'tab': 'history',
        'summary': '1',
        'status': 'forwarded',
        'q': 'Kopi',
        'sort': 'oldest',
        'offset': '100',
      });
      expect(requests.last.headers['Authorization'], 'Bearer token');
      final me = await api.me();
      expect(me.fullName, 'Alice');
      expect(me.isAdmin, isTrue);
      await api.claimPos(orderJson()['id'] as String, 2);
      expect(jsonDecode(requests.last.body), {'expected_version': 2});
      await api.claimPos(
        orderJson()['id'] as String,
        2,
        takeoverReason: 'Kasir pagi sakit',
      );
      expect(jsonDecode(requests.last.body), {
        'expected_version': 2,
        'takeover_reason': 'Kasir pagi sakit',
      });
      await api.forwardPos(orderJson()['id'] as String, 2, reference: 'POS-1');
      expect(jsonDecode(requests.last.body), {
        'expected_version': 2,
        'pos_reference': 'POS-1',
        'entered_in_pos': true,
        'paid_in_pos': true,
      });
      expect(() => api.claimPos('../escape', 2), throwsA(isA<ApiException>()));
      expect(
        () =>
            api.claimPos(orderJson()['id'] as String, 2, takeoverReason: 'no'),
        throwsA(isA<ApiException>()),
      );
      expect(
        () =>
            api.forwardPos(orderJson()['id'] as String, 2, reference: 'x' * 81),
        throwsA(isA<ApiException>()),
      );
      expect(requests.length, 5);
      api.close();
    },
  );
  test(
    'API preserves uncertain conflicts and respects Retry-After without replay',
    () async {
      var calls = 0;
      final api = CashierApi(
        config: config(),
        auth: FakeAuth(),
        client: MockClient((r) async {
          calls++;
          return http.Response(
            '{"error":"secret backend text","code":"checkout_rejected"}',
            429,
            headers: {'retry-after': '60'},
          );
        }),
      );
      final draft = ReorderDraft(
        customerName: 'A',
        items: [OrderDraftLine(productId: 'p')],
      );
      try {
        await api.createOrder(
          draft,
          '1234567890123456',
          '123456789012345678901234',
        );
        fail('must fail');
      } on ApiException catch (e) {
        expect(e.status, 429);
        expect(e.checkoutRejected, isFalse);
        expect(e.toString(), isNot(contains('secret backend text')));
      }
      await expectLater(api.listOrders(), throwsA(isA<ApiException>()));
      expect(calls, 1);
      api.close();
    },
  );
}
