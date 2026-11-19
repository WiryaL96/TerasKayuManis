import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'core/app_theme.dart';
import 'core/order_chime.dart';
import 'core/order_watch.dart';
import 'core/visible_clock.dart';
import 'features/auth/login_screen.dart';
import 'features/cashier/cashier_controller.dart';
import 'features/cashier/cashier_screen.dart';

class CashierApp extends StatefulWidget {
  const CashierApp({
    super.key,
    required this.controller,
    this.watch,
    this.chime,
    this.demo = false,
  });
  final CashierController controller;
  final OrderWatch? watch;
  final OrderChime? chime;
  final bool demo;

  @override
  State<CashierApp> createState() => _CashierAppState();
}

class _CashierAppState extends State<CashierApp> with WidgetsBindingObserver {
  final _messenger = GlobalKey<ScaffoldMessengerState>();
  final _navigator = GlobalKey<NavigatorState>();
  late final _chime = widget.chime ?? OrderChime();
  bool _foreground = true;
  bool _sound = true;
  bool _wasSignedIn = false;
  int _serial = 0;
  String? _startupError;
  final _signedIn = ValueNotifier(false);
  int _lifecycleGeneration = 0;
  Timer? _watchRenewal;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _foreground =
        WidgetsBinding.instance.lifecycleState == null ||
        WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed;
    _serial = widget.controller.newOrderSerial;
    _wasSignedIn = widget.controller.signedIn;
    _signedIn.value = _wasSignedIn;
    widget.watch?.onSeen = widget.controller.adoptSeenOrders;
    widget.controller.addListener(_changed);
    widget.controller.setForeground(_foreground);
    unawaited(_chime.warmUp());
    unawaited(_initialize());
    _watchRenewal = Timer.periodic(const Duration(minutes: 10), (_) {
      if (_foreground && widget.controller.signedIn) {
        unawaited(widget.watch?.prepare());
      }
    });
  }

  Future<void> _initialize() async {
    try {
      if (widget.watch != null) {
        try {
          final saved = await const FlutterSecureStorage()
              .read(key: 'tkm.sound.v1')
              .timeout(const Duration(seconds: 2));
          if (mounted && saved != null) {
            setState(() => _sound = saved == 'true');
          }
        } catch (_) {}
        widget.watch!.sound = _sound;
        await widget.watch!.stop();
      }
      await widget.controller.initialize();
      if (mounted && _foreground && widget.controller.signedIn) {
        unawaited(widget.watch?.prepare());
      }
    } catch (_) {
      if (mounted) {
        setState(
          () => _startupError = 'Sesi gagal dimuat. Silakan masuk kembali.',
        );
      }
    }
  }

  void _changed() {
    final c = widget.controller;
    final delta = c.newOrderSerial - _serial;
    final alert = delta > 0 && c.signedIn && _foreground;
    _serial = c.newOrderSerial;
    if (_signedIn.value != c.signedIn) _signedIn.value = c.signedIn;
    if (c.latestSync != null) widget.watch?.remember(c.latestSync!);
    if (!_wasSignedIn && c.signedIn && _foreground) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && c.signedIn && _foreground) {
          unawaited(widget.watch?.prepare());
        }
      });
    }
    if (_wasSignedIn && !c.signedIn) {
      unawaited(_chime.stop());
      unawaited(widget.watch?.stop(clear: true) ?? Future.value());
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _navigator.currentState?.popUntil((route) => route.isFirst);
          _messenger.currentState?.clearSnackBars();
        }
      });
    }
    _wasSignedIn = c.signedIn;
    if (alert) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || !_foreground || !c.signedIn) return;
        _messenger.currentState?.clearSnackBars();
        _messenger.currentState?.showSnackBar(
          SnackBar(
            content: Text(
              delta > 1 ? '$delta pesanan baru masuk' : 'Pesanan baru masuk',
            ),
          ),
        );
        if (_sound) {
          unawaited(_chime.play());
        }
      });
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // `inactive` and `hidden` fire for a pulldown, a permission dialog or an
    // app-switch preview. Treating those as "backgrounded" started and stopped
    // the native watcher several times a second, and every stop interrupted
    // polling, which delayed the alert by up to a minute. Only a real pause
    // hands over, and only a real resume takes over.
    if (state == AppLifecycleState.paused) {
      ++_lifecycleGeneration;
      _foreground = false;
      widget.controller.setForeground(false);
      _messenger.currentState?.clearSnackBars();
      unawaited(_chime.stop());
      // Hand over to the native watcher so orders still alert while hidden.
      if (widget.controller.signedIn) {
        unawaited(widget.watch?.start() ?? Future.value());
      }
      return;
    }
    if (state == AppLifecycleState.resumed) {
      if (widget.watch == null) {
        _foreground = true;
        widget.controller.setForeground(true);
        return;
      }
      final generation = ++_lifecycleGeneration;
      unawaited(() async {
        await widget.watch?.stop();
        if (!mounted || generation != _lifecycleGeneration) return;
        _foreground = true;
        widget.controller.setForeground(true);
        if (widget.controller.signedIn) unawaited(widget.watch?.prepare());
      }());
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _watchRenewal?.cancel();
    widget.controller.removeListener(_changed);
    widget.controller.setForeground(false);
    widget.controller.dispose();
    unawaited(widget.watch?.stop() ?? Future.value());
    unawaited(_chime.dispose());
    _signedIn.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'Kasir TerasKayuManis',
    debugShowCheckedModeBanner: false,
    navigatorKey: _navigator,
    navigatorObservers: [cashierRouteObserver],
    scaffoldMessengerKey: _messenger,
    theme: buildAppTheme(),
    home: ValueListenableBuilder<bool>(
      valueListenable: _signedIn,
      builder: (context, signedIn, _) => signedIn
          ? CashierScreen(
              controller: widget.controller,
              sound: _sound,
              onSoundChanged: (value) {
                setState(() => _sound = value);
                widget.watch?.sound = value;
                if (!value) {
                  unawaited(_chime.stop());
                } else if (_foreground && widget.controller.signedIn) {
                  // Give immediate feedback that sound is enabled on this device.
                  unawaited(_chime.play());
                }
                unawaited(
                  const FlutterSecureStorage()
                      .write(key: 'tkm.sound.v1', value: '$value')
                      .catchError((Object _) {}),
                );
              },
              watchStatus: widget.watch?.status,
              onEnableNotifications: widget.watch == null
                  ? null
                  : () => unawaited(() async {
                      final watch = widget.watch!;
                      if (await watch.ensureNotificationPermission() &&
                          mounted &&
                          _foreground &&
                          widget.controller.signedIn) {
                        await watch.prepare();
                      }
                    }()),
              demo: widget.demo,
            )
          : ListenableBuilder(
              listenable: widget.controller,
              builder: (context, _) => LoginScreen(
                controller: widget.controller,
                startupError: _startupError,
              ),
            ),
    ),
  );
}
