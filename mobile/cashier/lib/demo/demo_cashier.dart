import 'dart:async';
import 'dart:convert';

import '../core/app_config.dart';
import '../core/realtime_client.dart';
import '../data/auth_session.dart';
import '../data/cashier_api.dart';
import '../data/secure_store.dart';
import '../domain/models.dart';
import '../domain/order_sync.dart';
import '../features/cashier/cashier_controller.dart';

// ponytail: volatile, single-device UI simulator; use Go + Auth for integration QA.
CashierController createDemoController({bool stress = false}) {
  final auth = DemoAuth();
  final api = DemoApi(auth);
  if (stress) api.seedStress();
  return CashierController(
    api: api,
    auth: auth,
    realtime: _DemoRealtime(api.config, auth),
    store: _MemoryStore(),
  );
}

class DemoAuth implements AuthSession {
  String? _user = 'demo';
  @override
  String? get userId => _user;
  @override
  String? get refreshToken => _user == null ? null : 'preview-only';
  @override
  Stream<void> get changes => const Stream.empty();
  @override
  Future<String?> accessToken() async => null;
  @override
  Future<void> signIn(String email, String password) async {
    _user = 'demo';
  }

  @override
  Future<void> installSession(String refreshToken) async {
    _user = 'demo';
  }

  @override
  Future<void> signOut() async {
    _user = null;
  }
}

class _MemoryStore implements AttemptStore {
  final _values = <String, String>{};
  @override
  Future<String?> read(String key) async => _values[key];
  @override
  Future<void> write(String key, String value) async {
    _values[key] = value;
  }

  @override
  Future<void> delete(String key) async {
    _values.remove(key);
  }
}

class _DemoRealtime extends RealtimeClient {
  _DemoRealtime(super.config, super.auth);
  @override
  void start({
    required void Function() onInvalidate,
    required void Function(RealtimeStatus) onStatus,
    required void Function() onNewOrder,
  }) => onStatus(RealtimeStatus.stopped);
  @override
  void reconnect() {}
}

class DemoApi extends CashierApi {
  void seedStress() {
    _orders.clear();
    for (var i = 0; i < 100; i++) {
      _add(
        'Fixture $i',
        List.generate(
          50,
          (line) => OrderDraftLine(
            productId: 'tea',
            notes: 'Catatan sintetis baris $line',
          ),
        ),
      );
    }
  }

  DemoApi(AuthSession auth)
    : super(
        auth: auth,
        config: AppConfig(
          apiBase: Uri.parse('https://demo.invalid/api/core/'),
          wsUrl: Uri.parse('wss://demo.invalid/ws'),
          wsOrigin: 'https://demo.invalid',
          supabaseUrl: 'https://demo.invalid',
          supabaseKey: 'sb_publishable_demo',
        ),
      ) {
    final dina = _add('Dina', [
      OrderDraftLine(productId: 'coffee', variantIds: ['iced']),
    ]);
    final ayu = _add('Ayu', [OrderDraftLine(productId: 'tea')]);
    ayu.addAll({
      'status': 'pos_input',
      'version': 3,
      'reviewed_version': 3,
      'created_at': DateTime.now()
          .subtract(const Duration(minutes: 6))
          .toIso8601String(),
      'pos_handoff': {
        'cashier_id': 'demo',
        'cashier_name': 'Kasir Demo',
        'claimed_at': DateTime.now()
            .subtract(const Duration(minutes: 5))
            .toIso8601String(),
        'forwarded_at': null,
        'pos_reference': null,
      },
    });
    final rian = _add('Rian', [
      OrderDraftLine(productId: 'toast', quantity: 2),
    ]);
    rian.addAll({
      'status': 'forwarded',
      'version': 4,
      'reviewed_version': 3,
      'created_at': DateTime.now()
          .subtract(const Duration(minutes: 30))
          .toIso8601String(),
      'pos_handoff': {
        'cashier_id': 'demo',
        'cashier_name': 'Kasir Demo',
        'claimed_at': DateTime.now()
            .subtract(const Duration(minutes: 20))
            .toIso8601String(),
        'forwarded_at': DateTime.now()
            .subtract(const Duration(minutes: 15))
            .toIso8601String(),
        'pos_reference': 'POS-100',
      },
    });
    final budi = _add('Budi', [OrderDraftLine(productId: 'tea')]);
    budi.addAll({
      'status': 'completed',
      'version': 5,
      'reviewed_version': 4,
      'created_at': DateTime.now()
          .subtract(const Duration(hours: 2))
          .toIso8601String(),
    });
    final sari = _add('Sari', [OrderDraftLine(productId: 'tea')]);
    sari.addAll({
      'status': 'expired',
      'version': 2,
      'created_at': DateTime.now()
          .subtract(const Duration(hours: 1))
          .toIso8601String(),
      'expires_at': DateTime.now()
          .subtract(const Duration(minutes: 45))
          .toIso8601String(),
    });
    // Keep the newest active order first, like the REST list.
    dina['created_at'] = DateTime.now().toIso8601String();
  }
  final _orders = <Map<String, dynamic>>[];
  final _attempts = <String, ({String payload, String token, String id})>{};
  final _catalog = Catalog.fromJson({
    'settings': {'require_customer_name': true},
    'products': [
      {
        'id': 'coffee',
        'name': 'Kopi Susu',
        'price': 18000,
        'is_available': true,
        'variants': [
          {
            'id': 'hot',
            'name': 'Panas',
            'group_name': 'Suhu',
            'price_modifier': 0,
            'is_available': true,
          },
          {
            'id': 'iced',
            'name': 'Dingin',
            'group_name': 'Suhu',
            'price_modifier': 2000,
            'is_available': true,
          },
        ],
        'addons': [
          {
            'id': 'shot',
            'name': 'Extra shot',
            'price': 5000,
            'is_available': true,
          },
        ],
      },
      {
        'id': 'tea',
        'name': 'Es Teh Manis',
        'price': 5000,
        'is_available': true,
      },
      {
        'id': 'toast',
        'name': 'Roti Bakar Cokelat',
        'price': 15000,
        'is_available': true,
      },
      {
        'id': 'sold-out',
        'name': 'Kentang Goreng (Habis)',
        'price': 12000,
        'is_available': false,
      },
    ],
  });

  Never _conflict() => throw const ApiException(
    'Data demo berubah atau input tidak valid.',
    status: 409,
  );
  Map<String, dynamic> _find(String id) =>
      _orders.firstWhere((o) => o['id'] == id);
  OrderRecord _snapshot(Map<String, dynamic> order) =>
      OrderRecord.fromJson(order);

  List<Map<String, dynamic>> _price(List<OrderDraftLine> items) {
    if (items.isEmpty || items.length > 50) _conflict();
    return items.map((line) {
      final p = _catalog.products
          .where((p) => p.id == line.productId)
          .firstOrNull;
      if (p == null ||
          !p.available ||
          line.quantity < 1 ||
          line.quantity > 50 ||
          line.variantIds.length > 20 ||
          line.addonIds.length > 20) {
        _conflict();
      }
      final variants = p.variants
          .where((v) => line.variantIds.contains(v.id))
          .toList();
      final addons = p.addons
          .where((a) => line.addonIds.contains(a.id))
          .toList();
      final groups = variants.map((v) => v.groupName).toSet();
      if (variants.length != line.variantIds.length ||
          addons.length != line.addonIds.length ||
          groups.length != variants.length ||
          variants.any((v) => !v.available) ||
          addons.any((a) => !a.available) ||
          p.variants.any((v) => v.available && !groups.contains(v.groupName))) {
        _conflict();
      }
      final unit =
          p.price + variants.fold(0, (sum, v) => sum + v.priceModifier);
      final extra = addons.fold(0, (sum, a) => sum + a.price);
      return <String, dynamic>{
        ...line.toJson(),
        'product_name': p.name,
        'variant_name': variants.map((v) => v.name).join(' · '),
        'unit_price': unit,
        'subtotal': (unit + extra) * line.quantity,
        'order_item_addons': addons.map((a) => {'addon_name': a.name}).toList(),
        'notes': String.fromCharCodes(line.notes.runes.take(200)),
      };
    }).toList();
  }

  Map<String, dynamic> _add(String name, List<OrderDraftLine> items) {
    if (name.trim().isEmpty) _conflict();
    final priced = _price(items), number = _orders.length + 1;
    final order = <String, dynamic>{
      'id': '00000000-0000-4000-8000-${number.toString().padLeft(12, '0')}',
      'order_number': 'DEMO-A$number',
      'customer_name': name,
      'status': 'pending',
      'payment_status': 'unpaid',
      'version': 1,
      'reviewed_version': null,
      'created_at': DateTime.now().toIso8601String(),
      'expires_at': DateTime.now()
          .add(const Duration(minutes: 15))
          .toIso8601String(),
      'total': priced.fold<int>(0, (sum, i) => sum + (i['subtotal'] as int)),
      'order_items': priced,
    };
    _orders.insert(0, order);
    return order;
  }

  void _expirePending() {
    for (final o in _orders) {
      if (o['status'] == 'pending' && _snapshot(o).isExpired) {
        o['status'] = 'expired';
        o['version'] = (o['version'] as int) + 1;
      }
    }
  }

  @override
  Future<StaffProfile> me() async =>
      const StaffProfile(id: 'demo', fullName: 'Kasir Demo', role: 'admin');

  @override
  Future<String> syncRevision() async => '${_orders.length}';
  @override
  Future<OrderSync> sync() async {
    _expirePending();
    return OrderSync(
      _orders.map((o) => '${o['id']}:${o['version']}').join('|'),
      _orders.map((o) => o['id'] as String).toSet(),
    );
  }

  @override
  Future<OrderRecord> detail(String id, {String? orderNumber}) async =>
      _snapshot(_find(id));

  @override
  Future<List<CashierRosterEntry>> listCashiers() async => const [
    CashierRosterEntry(
      id: '00000000-0000-4000-8000-000000020002',
      name: 'Kasir Demo',
    ),
  ];

  @override
  Future<({StaffProfile profile, String accessToken, String refreshToken})>
  loginPin(String cashierId, String pin) async {
    if (pin != '123456') _conflict();
    return (
      profile: const StaffProfile(
        id: 'demo',
        fullName: 'Kasir Demo',
        role: 'cashier',
      ),
      accessToken: 'preview:demo',
      refreshToken: 'preview-only',
    );
  }

  @override
  Future<({StaffProfile profile, String accessToken, String refreshToken})>
  loginStaff(String identifier, String password) async => (
    profile: const StaffProfile(
      id: 'demo',
      fullName: 'Kasir Demo',
      role: 'admin',
    ),
    accessToken: 'preview:demo',
    refreshToken: 'preview-only',
  );

  @override
  Future<void> logoutStaff() async {}

  @override
  Future<Catalog> menu() async => _catalog;

  static const _activeStatuses = {'pending', 'pos_input', 'confirmed'};
  static const _historyStatuses = {
    'forwarded',
    'completed',
    'expired',
    'cancelled',
  };

  @override
  Future<List<OrderRecord>> listOrders({
    String tab = 'active',
    String status = '',
    String search = '',
    String sort = 'newest',
    int offset = 0,
    DateTime? day,
  }) async {
    _expirePending();
    final query = search.trim().toLowerCase();
    final matches = _orders.where((o) {
      final snapshot = _snapshot(o);
      final inTab = (tab == 'active' ? _activeStatuses : _historyStatuses)
          .contains(o['status']);
      if (!inTab) return false;
      if (day != null) {
        final at = DateTime.parse(o['created_at'] as String)
            .toUtc()
            .add(const Duration(hours: 7));
        if (at.year != day.year || at.month != day.month || at.day != day.day) {
          return false;
        }
      }
      if (status == 'ready') {
        if (!snapshot.canClaim(DateTime.now())) return false;
      } else if (status.isNotEmpty && o['status'] != status) {
        return false;
      }
      if (query.isEmpty) return true;
      return (o['order_number'] as String).toLowerCase().contains(query) ||
          (o['customer_name'] as String).toLowerCase().contains(query) ||
          (o['order_items'] as List).any(
            (item) => ((item as Map)['product_name'] as String)
                .toLowerCase()
                .contains(query),
          );
    }).toList();
    matches.sort((a, b) {
      final left = DateTime.parse(a['created_at'] as String);
      final right = DateTime.parse(b['created_at'] as String);
      final byTime = left.compareTo(right);
      final byId = (a['id'] as String).compareTo(b['id'] as String);
      return sort == 'oldest'
          ? (byTime != 0 ? byTime : byId)
          : (byTime != 0 ? -byTime : -byId);
    });
    return matches.skip(offset).take(100).map(_snapshot).toList();
  }

  @override
  Future<OrderRecord> review(
    String id,
    int version,
    List<OrderDraftLine> items,
  ) async {
    final o = _find(id);
    if (!_snapshot(o).canReview(DateTime.now()) || o['version'] != version) {
      _conflict();
    }
    final priced = _price(items);
    o.addAll({
      'order_items': priced,
      'version': version + 1,
      'reviewed_version': version + 1,
      'total': priced.fold<int>(0, (sum, i) => sum + (i['subtotal'] as int)),
    });
    return _snapshot(o);
  }

  @override
  Future<OrderRecord> claimPos(
    String id,
    int version, {
    String takeoverReason = '',
  }) async {
    final o = _find(id);
    final handoff = o['pos_handoff'];
    if (o['status'] == 'pos_input' &&
        handoff is Map &&
        handoff['cashier_id'] == 'demo' &&
        (version == o['version'] || version == (o['version'] as int) - 1)) {
      return _snapshot(o);
    }
    if (o['payment_status'] != 'unpaid' || version != o['version']) {
      _conflict();
    }
    if (o['status'] == 'pos_input') {
      final reason = takeoverReason.trim();
      if (reason.runes.length < 5 ||
          reason.runes.length > 200 ||
          reason.contains(RegExp(r'[\x00-\x1f\x7f]'))) {
        _conflict();
      }
    } else if (o['status'] != 'pending' ||
        o['reviewed_version'] != o['version'] ||
        !_snapshot(o).canReview(DateTime.now())) {
      _conflict();
    }
    o['pos_handoff'] = {
      'cashier_id': 'demo',
      'cashier_name': 'Kasir Demo',
      'claimed_at': DateTime.now().toIso8601String(),
      'forwarded_at': null,
      'pos_reference': null,
    };
    o['status'] = 'pos_input';
    o['version'] = version + 1;
    return _snapshot(o);
  }

  @override
  Future<OrderRecord> forwardPos(
    String id,
    int version, {
    String reference = '',
  }) async {
    final o = _find(id);
    final handoff = o['pos_handoff'];
    final value = reference.trim();
    if (handoff is! Map || handoff['cashier_id'] != 'demo') {
      throw const ApiException('Akses ditolak', status: 403);
    }
    if (o['status'] == 'forwarded' &&
        version == (o['version'] as int) - 1 &&
        (handoff['pos_reference'] as String? ?? '') == value) {
      return _snapshot(o);
    }
    if (o['status'] != 'pos_input' ||
        version != o['version'] ||
        o['payment_status'] != 'unpaid' ||
        value.runes.length > 80 ||
        value.contains(RegExp(r'[\x00-\x1f\x7f]'))) {
      _conflict();
    }
    handoff['forwarded_at'] = DateTime.now().toIso8601String();
    handoff['pos_reference'] = value.isEmpty ? null : value;
    o['status'] = 'forwarded';
    o['version'] = version + 1;
    return _snapshot(o);
  }

  @override
  Future<ReorderDraft> reorder(String id) async {
    final o = _snapshot(_find(id));
    if (!o.isExpired) _conflict();
    return ReorderDraft(
      customerName: o.customerName,
      items: o.items.map((i) => i.toDraft()).toList(),
    );
  }

  @override
  Future<OrderRecord> createOrder(
    ReorderDraft draft,
    String key,
    String orderToken,
  ) async {
    final payload = jsonEncode(draft.toJson()), previous = _attempts[key];
    if (previous != null) {
      if (previous.payload != payload || previous.token != orderToken) {
        _conflict();
      }
      return _snapshot(_find(previous.id));
    }
    final o = _add(draft.customerName, draft.items);
    _attempts[key] = (
      payload: payload,
      token: orderToken,
      id: o['id'] as String,
    );
    return _snapshot(o);
  }
}
