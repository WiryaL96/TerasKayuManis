import 'dart:ui';

import 'package:cashier/app.dart';
import 'package:cashier/demo/demo_cashier.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:cashier_perf_harness/main.dart' show withCashierAssets;

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('100 orders, 50 items: scroll, countdown and editor typing', (
    tester,
  ) async {
    if (kDebugMode) {
      fail(
        'Frame benchmark requires --profile or --release on a physical device.',
      );
    }
    final controller = createDemoController(stress: true);
    await tester.pumpWidget(
      withCashierAssets(CashierApp(controller: controller, demo: true)),
    );
    await tester.pumpAndSettle();
    final frames = <FrameTiming>[];
    void collect(List<FrameTiming> batch) {
      frames.addAll(batch);
    }

    binding.addTimingsCallback(collect);
    try {
      for (var i = 0; i < 20; i++) {
        await tester.fling(
          find.byKey(const ValueKey('order-list')),
          Offset(0, i.isEven ? -900 : 900),
          1800,
        );
        await tester.pumpAndSettle();
        await controller.refresh();
      }
      final orderFinder = find.byKey(
        ValueKey('order-${controller.orders.first.id}'),
      );
      await tester.scrollUntilVisible(
        orderFinder,
        -350,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(orderFinder);
      await tester.pumpAndSettle();
      final review = find.byKey(const ValueKey('open-review'));
      await tester.scrollUntilVisible(
        review,
        400,
        scrollable: find.byType(Scrollable).last,
      );
      await tester.tap(review);
      await tester.pumpAndSettle();
      final notes = find.byKey(const ValueKey('notes-0'));
      await tester.ensureVisible(notes);
      for (var i = 1; i <= 30; i++) {
        await tester.enterText(notes, 'catatan ${'a' * i}');
        await tester.pump(const Duration(milliseconds: 50));
      }
      await tester.pumpAndSettle();
    } finally {
      binding.removeTimingsCallback(collect);
    }
    expect(frames.length, greaterThan(100));
    final refreshRate =
        binding.platformDispatcher.views.first.display.refreshRate;
    final budget = 1000000 / (refreshRate > 0 ? refreshRate : 60);
    final ui = frames.map((f) => f.buildDuration.inMicroseconds).toList()
      ..sort();
    final raster = frames.map((f) => f.rasterDuration.inMicroseconds).toList()
      ..sort();
    int percentile(List<int> values, double p) =>
        values[((values.length - 1) * p).round()];
    final slow = frames
        .where(
          (f) =>
              f.buildDuration.inMicroseconds > budget ||
              f.rasterDuration.inMicroseconds > budget,
        )
        .length;
    binding.reportData = {
      'fixture_orders': 100,
      'items_per_order': 50,
      'frames': frames.length,
      'frame_budget_us': budget,
      'ui_p95_us': percentile(ui, .95),
      'ui_p99_us': percentile(ui, .99),
      'raster_p95_us': percentile(raster, .95),
      'raster_p99_us': percentile(raster, .99),
      'jank_fraction': slow / frames.length,
    };
    expect(
      slow / frames.length,
      lessThan(.01),
      reason:
          'Target jank <1%; inspect exported trace before relaxing the budget.',
    );
    await tester.pumpWidget(const SizedBox());
  });
}
