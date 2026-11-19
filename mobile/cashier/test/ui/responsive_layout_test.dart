import 'package:cashier/app.dart';
import 'package:cashier/core/app_theme.dart';
import 'package:cashier/features/cashier/order_detail_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'cashier_app_test.dart' show FakeController, order;

void main() {
  group('AppBreakpoints derive purely from available width', () {
    test('tiers follow the container width, not the device', () {
      expect(AppBreakpoints.isCompact(320), isTrue);
      expect(AppBreakpoints.isCompact(599), isTrue);
      expect(AppBreakpoints.isMedium(600), isTrue);
      expect(AppBreakpoints.isMedium(839), isTrue);
      expect(AppBreakpoints.isExpanded(840), isTrue);
      expect(AppBreakpoints.isExpanded(1199), isTrue);
      expect(AppBreakpoints.isWide(1200), isTrue);
      expect(AppBreakpoints.isWide(2560), isTrue);
    });

    test('grid grows with width and never reads device category', () {
      expect(AppBreakpoints.gridColumns(360), 1);
      expect(AppBreakpoints.gridColumns(599), 1);
      expect(AppBreakpoints.gridColumns(600), 1);
      expect(AppBreakpoints.gridColumns(839), 1);
      expect(AppBreakpoints.gridColumns(840), 2);
      expect(AppBreakpoints.gridColumns(1199), 2);
      expect(AppBreakpoints.gridColumns(1200), 3);
      expect(AppBreakpoints.gridColumns(1920), 3);
    });

    test('content width caps only on very large windows', () {
      expect(AppBreakpoints.contentMaxWidth(800), 800);
      expect(AppBreakpoints.contentMaxWidth(1199), 1199);
      expect(AppBreakpoints.contentMaxWidth(1200), 1280);
      expect(AppBreakpoints.contentMaxWidth(2560), 1280);
    });
  });

  testWidgets('resizing the window reflows the queue without overflow', (
    tester,
  ) async {
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.binding.setSurfaceSize(const Size(320, 640));
    final c = FakeController()
      ..orders = [order(reviewed: true), order(posInput: true, handler: 'Bob')];
    await tester.pumpWidget(CashierApp(controller: c));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);

    // Same widget tree; only the available width changes between frames.
    for (final size in const [
      Size(600, 960),
      Size(840, 800),
      Size(1200, 800),
      Size(1600, 900),
      Size(360, 740),
    ]) {
      await tester.binding.setSurfaceSize(size);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull, reason: 'overflow at $size');
    }

    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('order detail splits into two panes only when wide enough', (
    tester,
  ) async {
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    final c = FakeController()..orders = [order(reviewed: true)];
    addTearDown(() => tester.binding.setSurfaceSize(null));

    Future<void> showAt(Size size) async {
      await tester.binding.setSurfaceSize(size);
      await tester.pumpWidget(
        MaterialApp(
          home: OrderDetailScreen(controller: c, order: c.orders.single),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull, reason: 'overflow at $size');
    }

    await showAt(const Size(900, 800));
    expect(find.byType(ListView), findsOneWidget, reason: 'single pane');

    await showAt(const Size(1280, 800));
    expect(
      find.byType(ListView),
      findsNWidgets(2),
      reason: 'queue and actions side by side',
    );

    await tester.pumpWidget(const SizedBox());
    c.dispose();
  });
}
