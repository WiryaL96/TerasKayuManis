import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:uuid/uuid.dart';

import '../data/auth_session.dart';
import '../data/cashier_api.dart';
import '../domain/order_sync.dart';
import 'app_config.dart';

/// Serialized native commands, with cancellation across permission/network awaits.
/// Supabase refresh tokens stay exclusively in the Flutter Auth SDK.
class OrderWatch {
  OrderWatch(this.config, this.auth, {this.api});
  static const _channel = MethodChannel(
    'id.alrizky.teraskayumanis.cashier/watch',
  );
  final AppConfig config;
  final AuthSession auth;
  final CashierApi? api;
  final status = ValueNotifier<String>('Pemantauan latar belum diaktifkan');
  final _storage = const FlutterSecureStorage();
  Future<void> _commands = Future.value();
  int _generation = 0;
  bool _desired = false, _permission = false, sound = true;
  OrderSync? _sync;
  WatchLease? _lease;
  String? _leaseUser;
  Future<void>? _preparing;
  void Function(Set<String>)? onSeen;
  bool get isSupported =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;
  static const _feedUnavailable =
      'Pemantauan latar belum didukung server. Suara pesanan tetap tersedia saat aplikasi terbuka.';
  bool get _feedSupported => _sync?.hasNewOrderFeed != false;
  void remember(OrderSync sync) {
    _sync = sync;
    if (!_feedSupported) status.value = _feedUnavailable;
  }

  Future<T> _command<T>(Future<T> Function() action) {
    final future = _commands.then((_) => action());
    _commands = future.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    return future;
  }

  Future<bool> ensureNotificationPermission() async {
    if (!isSupported) return false;
    if (!_feedSupported) {
      status.value = _feedUnavailable;
      return false;
    }
    try {
      _permission =
          await _channel
              .invokeMethod<bool>('ensureNotificationPermission')
              .timeout(const Duration(seconds: 30)) ??
          false;
    } catch (_) {
      _permission = false;
    }
    status.value = _permission
        ? 'Notifikasi diizinkan'
        : 'Izin notifikasi belum diberikan';
    return _permission;
  }

  Future<void> prepare() {
    if (!_feedSupported) {
      status.value = _feedUnavailable;
      return Future.value();
    }
    if (!isSupported || api == null || auth.userId == null) {
      return Future.value();
    }
    if (_permission &&
        _leaseUser == auth.userId &&
        _lease != null &&
        _lease!.expiresAt.difference(DateTime.now()) >
            const Duration(minutes: 30)) {
      return Future.value();
    }
    final running = _preparing;
    if (running != null) return running;
    late final Future<void> future;
    future = _prepare().whenComplete(() {
      if (identical(_preparing, future)) _preparing = null;
    });
    return _preparing = future;
  }

  Future<void> _prepare() async {
    final generation = _generation, user = auth.userId;
    WatchLease? acquired;
    bool current() =>
        generation == _generation && auth.userId == user && _feedSupported;
    try {
      if (!_permission && !await ensureNotificationPermission()) return;
      if (!current()) return;
      final key = 'tkm.watch.device.${config.storageScope}';
      var device = await _storage.read(key: key);
      if (!current()) return;
      if (device == null) {
        device = const Uuid().v4();
        await _storage.write(key: key, value: device);
      }
      if (!current()) return;
      acquired = await api!.issueWatch(device);
      if (!current()) {
        await api!.revokeWatch(acquired.token);
        return;
      }
      _lease = acquired;
      _leaseUser = user;
      status.value = 'Pemantauan siap saat aplikasi di latar';
    } catch (_) {
      if (acquired != null) {
        unawaited(api!.revokeWatch(acquired.token).catchError((Object _) {}));
      }
      if (current()) {
        status.value =
            'Pemantauan latar belum siap. Periksa koneksi dan versi server.';
      }
    }
  }

  Future<void> start() async {
    if (!isSupported) return;
    if (!_feedSupported) {
      status.value = _feedUnavailable;
      return;
    }
    final generation = ++_generation, user = auth.userId;
    _desired = true;
    final lease = _lease;
    if (!_permission ||
        lease == null ||
        user != _leaseUser ||
        lease.expiresAt.isBefore(DateTime.now())) {
      status.value = 'Buka aplikasi untuk memperbarui izin pemantauan';
      return;
    }
    bool current() =>
        generation == _generation &&
        _desired &&
        auth.userId == user &&
        _feedSupported;
    try {
      await _command(() async {
        if (!current()) return;
        final ok = await _channel
            .invokeMethod<bool>('start', {
              'apiBase': config.apiBase.toString(),
              'scope': '${config.storageScope}:$user',
              'token': lease.token,
              'expiresAt': lease.expiresAt.millisecondsSinceEpoch,
              'revision': _sync?.revision ?? '',
              'seen': _sync?.newOrders.toList(),
              'sound': sound,
            })
            .timeout(const Duration(seconds: 10));
        if (ok != true) throw StateError('Watch unavailable');
        if (current()) {
          status.value =
              'Pemantau latar aktif sampai ${lease.expiresAt.toLocal().hour.toString().padLeft(2, '0')}:${lease.expiresAt.toLocal().minute.toString().padLeft(2, '0')}';
        }
      });
    } catch (_) {
      if (current()) {
        status.value =
            'Pemantau latar gagal. Buka aplikasi untuk sinkronisasi.';
      }
    }
  }

  Future<void> stop({bool clear = false}) async {
    _desired = false;
    ++_generation;
    _preparing = null;
    if (!isSupported) return;
    final lease = _lease;
    _lease = null;
    _leaseUser = null;
    await _command(() async {
      final result = await _channel
          .invokeMapMethod<String, dynamic>('stop', {'clear': clear})
          .timeout(const Duration(seconds: 10));
      if (!clear &&
          result?['scope'] == '${config.storageScope}:${auth.userId}' &&
          result?['seen'] is List) {
        onSeen?.call(Set<String>.from(result!['seen'] as List));
      }
    }).catchError((Object _) {
      status.value = 'Pemantau perlu diperiksa kembali';
    });
    if (lease != null && api != null) {
      unawaited(api!.revokeWatch(lease.token).catchError((Object _) {}));
    }
    if (clear) _sync = null;
  }
}
