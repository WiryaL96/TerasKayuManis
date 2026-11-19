import 'package:flutter_test/flutter_test.dart';
import 'package:cashier/demo/demo_cashier.dart';
import 'package:cashier/data/cashier_api.dart';
import 'package:cashier/app.dart';
import 'package:flutter/material.dart';

void main() {
  testWidgets('demo opens cashier without credentials on phone-sized screen', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(393, 851));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      CashierApp(controller: createDemoController(), demo: true),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('DEMO • Data lokal'), findsOneWidget);
    expect(find.text('DEMO-A1'), findsOneWidget);
    expect(find.textContaining('Email'), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
  test('demo review, claim, forward and exact reorder retry', () async {
    final api = DemoApi(DemoAuth());
    addTearDown(api.close);
    final order = (await api.listOrders()).firstWhere(
      (o) => o.status == 'pending',
    );
    await expectLater(
      api.claimPos(order.id, order.version),
      throwsA(isA<ApiException>()),
    );
    final reviewed = await api.review(
      order.id,
      order.version,
      order.items.map((i) => i.toDraft()).toList(),
    );
    expect(reviewed.items.single.variantName, 'Dingin');
    expect(reviewed.canClaim(DateTime.now()), isTrue);
    final claimed = await api.claimPos(reviewed.id, reviewed.version);
    expect(claimed.status, 'pos_input');
    expect(claimed.posHandoff!.cashierName, 'Kasir Demo');
    expect(claimed.canForwardFor('demo'), isTrue);
    final forwarded = await api.forwardPos(
      claimed.id,
      claimed.version,
      reference: 'POS-9',
    );
    expect(forwarded.status, 'forwarded');
    expect(forwarded.posHandoff!.forwardedAt, isNotNull);
    expect(forwarded.posHandoff!.posReference, 'POS-9');
    expect(
      (await api.forwardPos(
        claimed.id,
        claimed.version,
        reference: 'POS-9',
      )).version,
      forwarded.version,
    );
    final history = await api.listOrders(tab: 'history');
    expect(history.any((o) => o.id == order.id), isTrue);
    final expired = (await api.listOrders(
      tab: 'history',
      status: 'expired',
    )).single;
    final draft = await api.reorder(expired.id);
    final created = await api.createOrder(
      draft,
      'demo-key-1234567890',
      'demo-token-123456789012345',
    );
    expect(
      (await api.createOrder(
        draft,
        'demo-key-1234567890',
        'demo-token-123456789012345',
      )).id,
      created.id,
    );
    expect(created.id, isNot(expired.id));
    await expectLater(
      api.claimPos(created.id, created.version),
      throwsA(isA<ApiException>()),
    );
    expect(
      (await api.listOrders(tab: 'history', status: 'expired')).single.id,
      expired.id,
    );
  });
}
