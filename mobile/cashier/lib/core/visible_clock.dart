import 'dart:async';

import 'package:flutter/material.dart';

final cashierRouteObserver = RouteObserver<ModalRoute<void>>();

/// Stops the periodic clock when a route is covered or the app is hidden.
class VisibleClock extends ValueNotifier<DateTime>
    with WidgetsBindingObserver, RouteAware {
  VisibleClock() : super(DateTime.now()) {
    WidgetsBinding.instance.addObserver(this);
  }
  Timer? _timer;
  bool _visible = true;
  void attach(BuildContext context) {
    final route = ModalRoute.of(context);
    if (route != null) cashierRouteObserver.subscribe(this, route);
    _visible = route?.isCurrent ?? true;
    _schedule();
  }

  void _schedule() {
    _timer?.cancel();
    final life = WidgetsBinding.instance.lifecycleState;
    if (!_visible || (life != null && life != AppLifecycleState.resumed)) {
      return;
    }
    value = DateTime.now();
    _timer = Timer.periodic(
      const Duration(seconds: 1),
      (_) => value = DateTime.now(),
    );
  }

  @override
  void didPushNext() {
    _visible = false;
    _schedule();
  }

  @override
  void didPopNext() {
    _visible = true;
    _schedule();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) => _schedule();
  @override
  void dispose() {
    _timer?.cancel();
    cashierRouteObserver.unsubscribe(this);
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }
}
