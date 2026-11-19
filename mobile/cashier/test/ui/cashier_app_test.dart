import 'package:cashier/app.dart';
import 'package:cashier/core/realtime_client.dart';
import 'package:cashier/domain/models.dart';
import 'package:cashier/domain/order_sync.dart';
import 'package:cashier/data/order_snapshot_store.dart';
import 'package:cashier/features/cashier/cashier_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

OrderRecord order({
  bool reviewed = false,
  bool expired = false,
  bool paid = false,
  bool posInput = false,
  bool forwarded = false,
  String handler = 'Alice',
  String handlerId = 'alice',
  Duration? expiresIn,
}) {
  final status = expired
      ? 'expired'
      : forwarded
      ? 'forwarded'
      : posInput
      ? 'pos_input'
      : paid
      ? 'confirmed'
      : 'pending';
  return OrderRecord.fromJson({
    'id': 'order-1',
    'order_number': 'TKM-123',
    'customer_name': 'Sari',
    'status': status,
    'payment_status': paid ? 'paid' : 'unpaid',
    'version': forwarded
        ? 4
        : posInput
        ? 3
        : 2,
    'reviewed_version': status == 'pending' ? (reviewed ? 2 : null) : 2,
    'total': 25000,
    'created_at': DateTime.now()
        .subtract(const Duration(minutes: 5))
        .toUtc()
        .toIso8601String(),
    'expires_at': DateTime.now()
        .add(
          expired
              ? const Duration(hours: -1)
              : (expiresIn ?? const Duration(hours: 1)),
        )
        .toUtc()
        .toIso8601String(),
    'pos_handoff': posInput || forwarded
        ? {
            'cashier_id': handlerId,
            'cashier_name': handler,
            'claimed_at': DateTime.now()
                .subtract(const Duration(minutes: 4))
                .toUtc()
                .toIso8601String(),
            'forwarded_at': forwarded
                ? DateTime.now()
                      .subtract(const Duration(minutes: 2))
                      .toUtc()
                      .toIso8601String()
                : null,
            'pos_reference': forwarded ? 'POS-1' : null,
          }
        : null,
    'order_items': [
      {
        'product_id': 'coffee',
        'product_name': 'Kopi',
        'quantity': 1,
        'unit_price': 25000,
        'subtotal': 25000,
        'variant_ids': <String>[],
        'addon_ids': <String>[],
        'notes': '',
      },
    ],
  });
}

Catalog catalog() => Catalog.fromJson({
  'settings': {'require_customer_name': true},
  'products': [
    {
      'id': 'coffee',
      'name': 'Kopi',
      'price': 25000,
      'is_available': true,
      'variants': [
        {
          'id': 'hot',
          'name': 'Panas',
          'group_name': 'Suhu',
          'price_modifier': 0,
          'is_available': true,
        },
      ],
      'addons': [
        {'id': 'milk', 'name': 'Susu', 'price': 3000, 'is_available': true},
      ],
    },
    {
      'id': 'tea',
      'name': 'Teh',
      'price': 10000,
      'is_available': true,
      'variants': [],
      'addons': [],
    },
  ],
});

class FakeController extends ChangeNotifier implements CashierController {
  @override
  bool hasPendingPos = false;
  @override
  Future<OrderRecord?> retryPos() async => null;
  @override
  final snapshots = OrderSnapshotStore();
  @override
  final lastSync = ValueNotifier<DateTime?>(DateTime.now());
  @override
  OrderSync? latestSync;
  @override
  void adoptSeenOrders(Set<String> ids) {}
  @override
  ValueNotifier<DetailSnapshot> watchDetail(OrderRecord initial) =>
      snapshots.details.putIfAbsent(
        initial.id,
        () => ValueNotifier(
          DetailSnapshot(order: initial, checkedAt: DateTime.now()),
        ),
      );
  @override
  Future<void> refreshDetail(String id) async {
    emit();
  }

  @override
  void releaseDetail(String id) {
    snapshots.details.remove(id)?.dispose();
  }

  @override
  bool signedIn = true;
  @override
  bool busy = false;
  @override
  bool loading = false;
  @override
  String? error;
  @override
  List<OrderRecord> orders = [order()];
  @override
  List<CashierRosterEntry> cashiers = const [
    CashierRosterEntry(
      id: '11111111-1111-4111-8111-111111111111',
      name: 'Kasir Raka',
    ),
  ];
  @override
  StaffProfile? staff = const StaffProfile(
    id: 'alice',
    fullName: 'Alice',
    role: 'cashier',
  );
  @override
  String tab = 'active';
  @override
  String search = '', statusFilter = '', sort = 'newest';
  @override
  DateTime? selectedDay;
  @override
  bool dateScanTruncated = false;
  @override
  int offset = 0;
  @override
  RealtimeStatus realtimeStatus = RealtimeStatus.connected;
  @override
  int newOrderSerial = 0;
  @override
  bool hasPendingAttempt = false;
  bool more = false;
  @override
  bool get hasMore => more;
  @override
  bool get isFiltering =>
      search.isNotEmpty || statusFilter.isNotEmpty || selectedDay != null;
  int initializes = 0,
      menus = 0,
      claims = 0,
      forwards = 0,
      submits = 0,
      retries = 0,
      refreshes = 0;
  String? email, password, pinCashierId, pinCode, takeoverReason, reference;
  bool? enteredInPos, paidInPos;
  List<OrderDraftLine>? reviewedItems;
  final foreground = <bool>[];
  void emit() {
    for (final entry in snapshots.details.entries) {
      final current = orders.where((o) => o.id == entry.key).firstOrNull;
      entry.value.value = current == null
          ? const DetailSnapshot(error: 'Snapshot tidak tersedia')
          : DetailSnapshot(order: current, checkedAt: DateTime.now());
    }
    notifyListeners();
  }

  @override
  Future<void> initialize() async {
    initializes++;
  }

  @override
  Future<List<CashierRosterEntry>> loadCashiers() async => cashiers;

  @override
  Future<void> loginPin(String cashierId, String pin) async {
    pinCashierId = cashierId;
    pinCode = pin;
    signedIn = true;
    emit();
  }

  @override
  Future<void> login(String email, String password) async {
    this.email = email;
    this.password = password;
    signedIn = true;
    emit();
  }

  @override
  Future<void> logout() async {
    signedIn = false;
    emit();
  }

  @override
  Future<void> refresh({bool force = false}) async {
    refreshes++;
    emit();
  }

  @override
  Future<void> changeTab(String value) async {
    tab = value;
    statusFilter = '';
    offset = 0;
    emit();
  }

  @override
  Future<void> setStatusFilter(String value) async {
    statusFilter = value;
    offset = 0;
    emit();
  }

  @override
  Future<void> setSearch(String value) async {
    search = value;
    offset = 0;
    emit();
  }

  @override
  Future<void> setSort(String value) async {
    sort = value;
    offset = 0;
    emit();
  }

  @override
  Future<void> setSelectedDay(DateTime? value) async {
    selectedDay = value;
    offset = 0;
    emit();
  }

  @override
  Future<void> clearFilters() async {
    search = '';
    statusFilter = '';
    sort = 'newest';
    selectedDay = null;
    offset = 0;
    emit();
  }

  @override
  Future<void> nextPage() async {
    offset += 100;
    emit();
  }

  @override
  Future<void> previousPage() async {
    offset -= 100;
    emit();
  }

  @override
  void setForeground(bool value) {
    foreground.add(value);
  }

  @override
  Future<Catalog> menu() async {
    menus++;
    return catalog();
  }

  @override
  Future<OrderRecord?> review(
    OrderRecord record,
    List<OrderDraftLine> items,
  ) async {
    reviewedItems = items;
    orders = [order(reviewed: true)];
    emit();
    return orders.first;
  }

  @override
  Future<OrderRecord?> claim(
    OrderRecord record, {
    String takeoverReason = '',
  }) async {
    claims++;
    this.takeoverReason = takeoverReason;
    orders = [order(posInput: true)];
    emit();
    return orders.first;
  }

  @override
  Future<OrderRecord?> forward(
    OrderRecord record, {
    required bool enteredInPos,
    required bool paidInPos,
    String reference = '',
  }) async {
    forwards++;
    this.enteredInPos = enteredInPos;
    this.paidInPos = paidInPos;
    this.reference = reference;
    orders = [order(forwarded: true)];
    emit();
    return orders.first;
  }

  @override
  Future<ReorderDraft> prepareReorder(OrderRecord record) async => ReorderDraft(
    customerName: 'Sari',
    items: [
      OrderDraftLine(productId: 'coffee', variantIds: ['hot']),
    ],
  );
  @override
  Future<OrderRecord?> submitReorder(ReorderDraft draft) async {
    submits++;
    hasPendingAttempt = true;
    error = 'Hasil belum pasti';
    emit();
    return null;
  }

  @override
  Future<OrderRecord?> retryPending() async {
    retries++;
    hasPendingAttempt = false;
    emit();
    return order();
  }

  @override
  void clearError() {
    error = null;
    emit();
  }
}

Future<void> mount(WidgetTester tester, FakeController controller) async {
  tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
  await tester.binding.setSurfaceSize(const Size(1000, 1000));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(CashierApp(controller: controller));
  await tester.pumpAndSettle();
}

Future<void> tap(WidgetTester tester, String key) async {
  if (find.byKey(ValueKey(key)).evaluate().isEmpty) {
    await tester.scrollUntilVisible(
      find.byKey(ValueKey(key)),
      250,
      scrollable: find.byType(Scrollable).last,
    );
  }
  await tester.ensureVisible(find.byKey(ValueKey(key)));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(ValueKey(key)));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets(
    'initialize once; login validates and submits credentials, no catalog on launch',
    (tester) async {
      final c = FakeController()..signedIn = false;
      await mount(tester, c);
      expect(c.initializes, 1);
      expect(c.menus, 0);
      await tap(tester, 'login-submit');
      expect(c.email, isNull);
      await tester.enterText(
        find.byKey(const ValueKey('login-email')),
        ' staff@example.com ',
      );
      await tester.enterText(
        find.byKey(const ValueKey('login-password')),
        'secret123',
      );
      await tap(tester, 'login-submit');
      expect(c.email, 'staff@example.com');
      expect(c.password, 'secret123');
      c.emit();
      await tester.pump();
      expect(c.initializes, 1);
      expect(find.text('TKM-123'), findsOneWidget);
    },
  );

  testWidgets('PIN login mode selects cashier and submits 6-digit PIN', (
    tester,
  ) async {
    final c = FakeController()..signedIn = false;
    await mount(tester, c);
    await tap(tester, 'login-mode-toggle');
    await tap(tester, 'login-cashier-select');
    await tester.tap(find.text('Kasir Raka').last);
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('login-pin')), '123456');
    await tap(tester, 'login-submit');
    expect(c.pinCashierId, '11111111-1111-4111-8111-111111111111');
    expect(c.pinCode, '123456');
    expect(find.text('TKM-123'), findsOneWidget);
  });

  testWidgets('history filters, sort and pagination call controller', (
    tester,
  ) async {
    final c = FakeController()..more = true;
    await mount(tester, c);
    await tap(tester, 'tab-history');
    expect(c.tab, 'history');
    await tap(tester, 'status-filter-forwarded');
    expect(c.statusFilter, 'forwarded');
    await tap(tester, 'next-page');
    expect(c.offset, 100);
    await tap(tester, 'previous-page');
    expect(c.offset, 0);
    await tap(tester, 'sort-order');
    await tester.tap(find.text('Terlama').last);
    await tester.pumpAndSettle();
    expect(c.sort, 'oldest');
    await tap(tester, 'refresh');
    expect(c.refreshes, 1);
  });

  testWidgets('unreviewed order cannot claim and offers review', (
    tester,
  ) async {
    final c = FakeController();
    await mount(tester, c);
    await tap(tester, 'order-order-1');
    expect(find.byKey(const ValueKey('claim-order')), findsNothing);
    expect(find.byKey(const ValueKey('open-review')), findsOneWidget);
    expect(find.text('Proses Pemesanan'), findsOneWidget);
    expect(c.claims, 0);
  });

  testWidgets('reviewed order claims only after confirmation', (tester) async {
    final c = FakeController()..orders = [order(reviewed: true)];
    await mount(tester, c);
    await tap(tester, 'order-order-1');
    await tap(tester, 'claim-order');
    expect(c.claims, 0);
    await tap(tester, 'confirm-no');
    await tap(tester, 'claim-order');
    await tap(tester, 'confirm-yes');
    expect(c.claims, 1);
    expect(find.byKey(const ValueKey('forward-order')), findsOneWidget);
  });

  testWidgets('forward requires both POS confirmations and reference', (
    tester,
  ) async {
    final c = FakeController()..orders = [order(posInput: true)];
    await mount(tester, c);
    await tap(tester, 'order-order-1');
    expect(
      tester
          .widget<FilledButton>(find.byKey(const ValueKey('forward-order')))
          .onPressed,
      isNull,
    );
    await tester.enterText(
      find.byKey(const ValueKey('pos-reference')),
      'POS-77',
    );
    await tap(tester, 'entered-in-pos');
    await tap(tester, 'paid-in-pos');
    await tap(tester, 'forward-order');
    await tap(tester, 'confirm-no');
    expect(c.forwards, 0);
    await tap(tester, 'forward-order');
    await tap(tester, 'confirm-yes');
    expect(c.forwards, 1);
    expect(c.enteredInPos, isTrue);
    expect(c.paidInPos, isTrue);
    expect(c.reference, 'POS-77');
  });

  testWidgets('admin can take over another cashier with a reason', (
    tester,
  ) async {
    final c = FakeController()
      ..staff = const StaffProfile(
        id: 'alice',
        fullName: 'Alice',
        role: 'admin',
      )
      ..orders = [order(posInput: true, handler: 'Bob', handlerId: 'bob')];
    await mount(tester, c);
    await tap(tester, 'order-order-1');
    expect(find.byKey(const ValueKey('takeover-order')), findsOneWidget);
    await tap(tester, 'takeover-order');
    expect(c.claims, 0);
    await tester.enterText(
      find.byKey(const ValueKey('takeover-reason')),
      'Kasir pagi sakit',
    );
    await tap(tester, 'takeover-order');
    await tap(tester, 'confirm-yes');
    expect(c.claims, 1);
    expect(c.takeoverReason, 'Kasir pagi sakit');
  });

  testWidgets(
    'fresh catalog editor changes qty variants addons notes and product list',
    (tester) async {
      final c = FakeController();
      await mount(tester, c);
      await tap(tester, 'order-order-1');
      await tap(tester, 'open-review');
      expect(c.menus, 1);
      await tap(tester, 'qty-plus-0');
      await tap(tester, 'variant-0-hot');
      await tap(tester, 'addon-0-milk');
      await tester.enterText(
        find.byKey(const ValueKey('notes-0')),
        'Tanpa gula',
      );
      c.emit();
      await tester.pumpAndSettle();
      await tap(tester, 'add-product');
      await tap(tester, 'product-tea');
      await tap(tester, 'remove-line-1');
      await tap(tester, 'editor-save');
      expect(c.reviewedItems, hasLength(1));
      expect(c.reviewedItems!.single.quantity, 2);
      expect(c.reviewedItems!.single.variantIds, ['hot']);
      expect(c.reviewedItems!.single.addonIds, ['milk']);
      expect(c.reviewedItems!.single.notes, 'Tanpa gula');
      expect(c.forwards, 0);
    },
  );

  testWidgets('expired reorder confirmation and persistent recovery action', (
    tester,
  ) async {
    final c = FakeController()..orders = [order(expired: true)];
    await mount(tester, c);
    await tap(tester, 'order-order-1');
    await tap(tester, 'reorder-order');
    expect(c.submits, 0);
    expect(c.menus, 1);
    await tap(tester, 'editor-save');
    expect(c.submits, 0);
    await tap(tester, 'confirm-yes');
    expect(c.submits, 1);
    await tester.pageBack();
    await tester.pumpAndSettle();
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('retry-pending')), findsOneWidget);
    await tap(tester, 'retry-pending');
    expect(c.retries, 1);
  });

  testWidgets('pending recovery prominent on relaunch; busy blocks retry', (
    tester,
  ) async {
    final c = FakeController()
      ..hasPendingAttempt = true
      ..busy = true;
    await mount(tester, c);
    expect(
      tester
          .widget<FilledButton>(find.byKey(const ValueKey('retry-pending')))
          .onPressed,
      isNull,
    );
    c.busy = false;
    c.emit();
    await tester.pumpAndSettle();
    await tap(tester, 'retry-pending');
    expect(c.retries, 1);
  });

  testWidgets('foreground-only serial snackbar and sound; lifecycle forwarded', (
    tester,
  ) async {
    final c = FakeController();
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('xyz.luan/audioplayers'),
      (call) async => null,
    );
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('xyz.luan/audioplayers.global'),
      (call) async => null,
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        const MethodChannel('xyz.luan/audioplayers'),
        null,
      ),
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        const MethodChannel('xyz.luan/audioplayers.global'),
        null,
      ),
    );
    await mount(tester, c);
    c.newOrderSerial++;
    c.emit();
    // The listener queues presentation after this frame; render it next frame.
    await tester.pump();
    await tester.pump();
    expect(find.text('Pesanan baru masuk'), findsOneWidget);
    expect(tester.takeException(), isNull);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    c.newOrderSerial++;
    c.emit();
    await tester.pump();
    expect(c.foreground.last, isFalse);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    expect(c.foreground.last, isTrue);
    await tester.pumpWidget(const SizedBox());
    expect(c.foreground.last, isFalse);
  });
}
