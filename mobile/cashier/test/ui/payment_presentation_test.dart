import 'package:cashier/app.dart';
import 'package:cashier/features/cashier/order_detail_screen.dart';
import 'package:cashier/features/cashier/ui_common.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'cashier_app_test.dart' show FakeController, mount, tap, order;

void main() {
  test('rupiah groups integer digits without rounding', () {
    expect(rupiah(5000), 'Rp 5.000');
    expect(rupiah(1234567890), 'Rp 1.234.567.890');
    expect(rupiah(-5000), 'Rp -5.000');
  });

  testWidgets('countdown hides once the cashier handles the order', (
    tester,
  ) async {
    final c = FakeController()..orders = [order(reviewed: true)];
    await mount(tester, c);
    await tap(tester, 'order-order-1');
    expect(find.text('Sisa waktu sebelum kedaluwarsa'), findsOneWidget);
    expect(find.textContaining('Hitung mundur berhenti'), findsNothing);
    c.orders = [order(posInput: true)];
    c.emit();
    await tester.pumpAndSettle();
    expect(find.text('Sisa waktu sebelum kedaluwarsa'), findsNothing);
    expect(find.textContaining('Waktu pembayaran dijeda'), findsOneWidget);
    expect(find.textContaining('Hitung mundur berhenti'), findsWidgets);
    expect(find.byKey(const ValueKey('forward-order')), findsOneWidget);
  });

  testWidgets('local clock expires claim actions without a REST refresh', (
    tester,
  ) async {
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    final c = FakeController()
      ..orders = [order(reviewed: true, expiresIn: const Duration(seconds: 1))];
    final record = c.orders.single;
    await tester.pumpWidget(
      MaterialApp(
        home: OrderDetailScreen(controller: c, order: record),
      ),
    );
    expect(find.byKey(const ValueKey('claim-order')), findsOneWidget);
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 1100)),
    );
    await tester.pump(const Duration(seconds: 1));
    expect(find.byKey(const ValueKey('claim-order')), findsNothing);
    expect(
      find.textContaining('Batas waktu pesanan sudah lewat'),
      findsOneWidget,
    );
    expect(c.claims, 0);
    await tester.pumpWidget(const SizedBox());
    c.dispose();
  });

  testWidgets(
    'phone and tablet layouts remain usable and date empty state shows',
    (tester) async {
      for (final size in const [
        Size(320, 640),
        Size(360, 740),
        Size(393, 851),
        Size(600, 960),
        Size(768, 1024),
        Size(840, 800),
        Size(1024, 768),
        Size(1280, 800),
        Size(1600, 900),
      ]) {
        await tester.binding.setSurfaceSize(size);
        final c = FakeController();
        await tester.pumpWidget(CashierApp(controller: c));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        c
          ..tab = 'history'
          ..selectedDay = DateTime(2026, 10, 12)
          ..orders = const [];
        c.emit();
        await tester.pumpAndSettle();
        expect(
          find.textContaining('Tidak ada pesanan pada tanggal ini'),
          findsOneWidget,
        );
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
      }
      await tester.binding.setSurfaceSize(const Size(393, 851));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      tester.platformDispatcher.textScaleFactorTestValue = 1.5;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      await tester.pumpWidget(CashierApp(controller: FakeController()));
      await tester.pumpAndSettle();
      await tap(tester, 'order-order-1');
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );
}
