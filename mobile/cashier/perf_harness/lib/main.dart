import 'package:cashier/app.dart';
import 'package:cashier/demo/demo_cashier.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

void main() => runApp(
  withCashierAssets(
    CashierApp(controller: createDemoController(stress: true), demo: true),
  ),
);

// The cashier is a dependency here: its bundle keys have a package prefix.
// Keep the same actual images as the production UI instead of benchmarking
// missing-image fallback widgets. The harness performs no network requests.
Widget withCashierAssets(Widget child) =>
    DefaultAssetBundle(bundle: _CashierAssets(), child: child);

class _CashierAssets extends CachingAssetBundle {
  @override
  Future<ByteData> load(String key) => rootBundle.load(
    key.startsWith('assets/') ? 'packages/cashier/$key' : key,
  );
}
