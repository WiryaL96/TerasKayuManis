import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../../core/realtime_client.dart';
import '../../data/auth_session.dart';
import '../../data/cashier_api.dart';
import '../../data/checkout_attempt.dart';
import '../../data/secure_store.dart';
import '../../data/order_snapshot_store.dart';
import '../../data/pos_attempt.dart';
import '../../domain/models.dart';
import '../../domain/order_arrivals.dart';
import '../../domain/order_sync.dart';

class CashierController extends ChangeNotifier {
  CashierController({
    required this._api,
    required this._auth,
    required this._realtime,
    required this._store,
  });
  final CashierApi _api;
  final AuthSession _auth;
  final RealtimeClient _realtime;
  final AttemptStore _store;
  static const pageSize = 100;
  final snapshots = OrderSnapshotStore();
  final lastSync = ValueNotifier<DateTime?>(null);
  OrderSync? latestSync;
  Set<String>? _seenNewOrders;
  final _legacyArrivals = OrderArrivals();
  String? _arrivalRevision;
  DateTime? _lastArrivalSync;
  DateTime? _retryAt, _lastFullSync;
  int _failures = 0;
  bool _force = false;
  String? _queryKey;
  String? _syncError;
  bool signedIn = false, busy = false, loading = false;
  String? error;
  List<OrderRecord> orders = const [];
  List<CashierRosterEntry> cashiers = const [];
  StaffProfile? staff;
  String tab = 'active';
  String search = '', statusFilter = '', sort = 'newest';
  DateTime? selectedDay;
  bool dateScanTruncated = false;
  int offset = 0, newOrderSerial = 0;
  RealtimeStatus realtimeStatus = RealtimeStatus.stopped;
  bool get hasPendingAttempt => _pending != null || _pendingBlocked;
  bool get hasMore => orders.length == pageSize;
  bool get isFiltering =>
      search.isNotEmpty || statusFilter.isNotEmpty || selectedDay != null;
  CheckoutAttempt? _pending;
  PosAttempt? _pendingPos;
  bool _posBlocked = false;
  bool get hasPendingPos => _pendingPos != null || _posBlocked;
  bool _pendingBlocked = false,
      _foreground = true,
      _disposed = false,
      _initialized = false;
  bool _dirty = false, _realtimeStarted = false;
  int _generation = 0, _filterRevision = 0, _authOperations = 0;
  int _visibilityVersion = 0;
  String? _user;
  StreamSubscription<void>? _authSubscription;
  Future<void>? _refreshing;
  Future<void> _authQueue = Future.value(), _storageQueue = Future.value();

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  bool _current(int g) =>
      !_disposed && g == _generation && _user != null && _auth.userId == _user;
  String _storeKey(String user) =>
      'tkm.checkout.v1.${_api.storageScope}.${base64Url.encode(utf8.encode(user))}';
  Future<T> _storage<T>(Future<T> Function() work) {
    final result = _storageQueue.then((_) => work());
    _storageQueue = result.then<void>(
      (_) {},
      onError: (Object _, StackTrace _) {},
    );
    return result;
  }

  void _reset() {
    ++_generation;
    _refreshing = null;
    _user = null;
    _dirty = false;
    _realtimeStarted = false;
    _realtime.stop();
    signedIn = false;
    busy = false;
    loading = false;
    orders = const [];
    staff = null;
    _pending = null;
    _pendingPos = null;
    _posBlocked = false;
    _detailFlights.clear();
    _pendingBlocked = false;
    error = null;
    snapshots.clear();
    lastSync.value = null;
    latestSync = null;
    _seenNewOrders = null;
    _legacyArrivals.reset();
    _arrivalRevision = null;
    _lastArrivalSync = null;
    _retryAt = null;
    _lastFullSync = null;
    _queryKey = null;
    _syncError = null;
    _force = false;
    _failures = 0;
    tab = 'active';
    search = '';
    statusFilter = '';
    sort = 'newest';
    selectedDay = null;
    dateScanTruncated = false;
    offset = 0;
    ++_filterRevision;
    newOrderSerial = 0;
    realtimeStatus = RealtimeStatus.stopped;
    _notify();
  }

  Future<void> initialize() async {
    if (_initialized || _disposed) return;
    _initialized = true;
    _authSubscription = _auth.changes.listen(
      (_) {
        if (_authOperations > 0 || _disposed) return;
        if (_auth.userId != _user) {
          _reset();
          unawaited(_adoptSession(_generation));
        } else if (_user != null && _foreground) {
          _realtime.reconnect();
          unawaited(refresh());
        }
      },
      onError: (Object _) {
        if (!_disposed) {
          _reset();
          error = 'Sesi tidak tersedia. Silakan masuk kembali.';
          _notify();
        }
      },
    );
    await _adoptSession(_generation);
  }

  Future<void> _adoptSession(int g) async {
    if (_disposed || g != _generation) return;
    _user = _auth.userId;
    if (_user == null) return;
    loading = true;
    _pendingBlocked = true;
    _posBlocked = true;
    _notify();
    final key = _storeKey(_user!);
    try {
      final raw = await _storage(() => _store.read(key));
      if (!_current(g)) return;
      _pending = raw == null ? null : CheckoutAttempt.decode(raw);
      final pos = await _storage(() => _store.read('$key.pos'));
      if (!_current(g)) return;
      _pendingPos = pos == null ? null : PosAttempt.decode(pos);
      _posBlocked = false;
      _pendingBlocked = false;
    } catch (_) {
      if (!_current(g)) return;
      // Fail closed: inability to read a previous attempt is not proof of absence.
      error = 'Percobaan tersimpan belum dapat dibaca. Masuk kembali sebelum membuat pesanan.';
    }
    if (_current(g)) await refresh();
  }

  Future<List<CashierRosterEntry>> loadCashiers() async {
    if (_disposed) return const [];
    try {
      final result = await _api.listCashiers();
      if (!_disposed) {
        cashiers = List.unmodifiable(result);
        _notify();
      }
      return cashiers;
    } catch (_) {
      return cashiers;
    }
  }

  Future<void> loginPin(String cashierId, String pin) {
    if (_disposed) return Future.value();
    _reset();
    final g = _generation;
    busy = true;
    ++_authOperations;
    _notify();
    final task = _authQueue.then((_) async {
      if (_disposed || g != _generation) return;
      try {
        final result = await _api.loginPin(cashierId, pin);
        if (_disposed || g != _generation) return;
        staff = result.profile;
        await _auth.installSession(result.refreshToken);
        if (g == _generation && !_disposed) await _adoptSession(g);
      } catch (e) {
        if (g == _generation && !_disposed) {
          error = e is ApiException
              ? e.message
              : 'PIN tidak sesuai atau login belum tersedia.';
        }
      }
    });
    _authQueue = task.catchError((Object _) {});
    return task.whenComplete(() {
      --_authOperations;
      if (g == _generation && !_disposed) {
        busy = false;
        loading = false;
        _notify();
      }
    });
  }

  Future<void> login(String email, String password) {
    if (_disposed) return Future.value();
    _reset();
    final g = _generation;
    busy = true;
    ++_authOperations;
    _notify();
    final task = _authQueue.then((_) async {
      if (_disposed || g != _generation) return;
      try {
        final result = await _api.loginStaff(email.trim(), password);
        if (_disposed || g != _generation) return;
        staff = result.profile;
        await _auth.installSession(result.refreshToken);
        if (g == _generation && !_disposed) await _adoptSession(g);
      } catch (_) {
        if (g == _generation && !_disposed) {
          error = 'Login gagal. Periksa akun, kredensial, dan koneksi.';
        }
      }
    });
    _authQueue = task.catchError((Object _) {});
    return task.whenComplete(() {
      --_authOperations;
      if (g == _generation && !_disposed) {
        busy = false;
        loading = false;
        _notify();
      }
    });
  }

  Future<void> logout() {
    if (_disposed) return Future.value();
    // Begin audit while the bearer still exists, but never keep the local UI
    // session alive waiting for an unreliable audit connection.
    unawaited(_api.logoutStaff().catchError((Object _) {}));
    _reset();
    final g = _generation;
    ++_authOperations;
    final task = _authQueue.then((_) async {
      try {
        await _auth.signOut();
      } catch (_) {
        if (g == _generation && !_disposed) {
          error = 'Sesi lokal belum dapat ditutup. Coba keluar kembali.';
          _notify();
        }
      }
    });
    _authQueue = task.catchError((Object _) {});
    return task.whenComplete(() => --_authOperations);
  }

  Future<void> refresh({bool force = false}) {
    if (_disposed || _user == null) return Future.value();
    if (!force && _retryAt != null && DateTime.now().isBefore(_retryAt!)) {
      return Future.value();
    }
    _force |= force;
    final running = _refreshing;
    if (running != null) {
      if (force) _dirty = true;
      return running;
    }
    _dirty = true;
    // Assign before starting work: notifications can request another refresh.
    final done = Completer<void>();
    _refreshing = done.future;
    unawaited(
      _drainRefresh(_generation).whenComplete(() {
        if (identical(_refreshing, done.future)) _refreshing = null;
        done.complete();
      }),
    );
    return done.future;
  }

  Future<void> _drainRefresh(int generation) async {
    while (_dirty && _current(generation)) {
      _dirty = false;
      final g = _generation, revision = _filterRevision;
      final force = _force;
      _force = false;
      final key = jsonEncode([
        tab,
        statusFilter,
        search,
        sort,
        offset,
        selectedDay?.toIso8601String(),
      ]);
      final cached = snapshots.query(key);
      if (_queryKey != key) {
        orders = cached?.orders ?? const [];
        _queryKey = key;
        loading = cached == null;
        _notify();
      }
      try {
        if (staff == null || !staff!.hasName) {
          final profile = await _api.me();
          if (!_current(g) || revision != _filterRevision) continue;
          staff = profile;
        }
        final sync = await _api.sync();
        if (!_current(g) || revision != _filterRevision) continue;
        final previousSync = latestSync;
        final previousRevision = previousSync?.revision;
        var changed = previousSync?.hasNewOrderFeed != sync.hasNewOrderFeed;
        List<OrderRecord>? arrivalSnapshot;
        final reconcile =
            _lastFullSync == null ||
            DateTime.now().difference(_lastFullSync!) >
                const Duration(seconds: 60);
        if (force ||
            cached == null ||
            cached.revision != sync.revision ||
            reconcile) {
          final result = await _api.listOrders(
            tab: tab,
            status: statusFilter,
            search: search,
            sort: sort,
            offset: offset,
            day: selectedDay,
          );
          if (!_current(g) || revision != _filterRevision) continue;
          final next = snapshots.save(key, sync.revision, result);
          changed |= !listEquals(orders, next);
          orders = next;
          _lastFullSync = DateTime.now();
          if (!sync.hasNewOrderFeed &&
              tab == 'active' &&
              statusFilter.isEmpty &&
              search.isEmpty &&
              sort == 'newest' &&
              offset == 0 &&
              selectedDay == null) {
            arrivalSnapshot = result;
          }
        }
        if (!sync.hasNewOrderFeed &&
            arrivalSnapshot == null &&
            (force ||
                _arrivalRevision != sync.revision ||
                _lastArrivalSync == null ||
                DateTime.now().difference(_lastArrivalSync!) >
                    const Duration(seconds: 60))) {
          // Notifications use a fixed query even on history/search/later pages.
          // Reuse the visible response above when it is that same query.
          arrivalSnapshot = await _api.listOrders();
          if (!_current(g) || revision != _filterRevision) continue;
        }
        for (final id in snapshots.details.keys.toList()) {
          if (force ||
              previousRevision != sync.revision ||
              reconcile ||
              _syncError != null ||
              snapshots.details[id]?.value.usable == false) {
            await refreshDetail(id);
          }
        }
        if (!_current(g)) return;
        if (revision != _filterRevision) continue;
        final Set<String> fresh;
        if (sync.hasNewOrderFeed) {
          fresh =
              previousSync?.hasNewOrderFeed != true || _seenNewOrders == null
              ? <String>{}
              : sync.newOrders.difference(_seenNewOrders!);
          _seenNewOrders = sync.newOrders;
          _legacyArrivals.reset();
          _arrivalRevision = null;
          _lastArrivalSync = null;
        } else {
          fresh = arrivalSnapshot == null
              ? <String>{}
              : _legacyArrivals.observe(arrivalSnapshot);
          _seenNewOrders = null;
          if (arrivalSnapshot != null) {
            _arrivalRevision = sync.revision;
            _lastArrivalSync = DateTime.now();
          }
        }
        latestSync = sync;
        if (_foreground && signedIn && fresh.isNotEmpty) {
          newOrderSerial += fresh.length;
          changed = true;
        }
        if (error == _syncError) {
          changed |= error != null;
          error = null;
        }
        _syncError = null;
        _retryAt = null;
        _failures = 0;
        lastSync.value = DateTime.now();
        changed |= !signedIn || loading;
        loading = false;
        signedIn = true;
        dateScanTruncated = false;
        if (sync.overflow) {
          error = 'Banyak pesanan baru. Muat ulang antrean untuk memeriksa semuanya.';
          changed = true;
        }
        _startRealtime();
        if (changed) _notify();
      } catch (e) {
        if (_current(g) && revision == _filterRevision) {
          _failure(e);
          _syncError = error;
          for (final detail in snapshots.details.values) {
            detail.value = DetailSnapshot(
              order: detail.value.order,
              error: 'Koneksi terganggu. Muat ulang status sebelum bertindak.',
            );
          }
          _failures = (_failures + 1).clamp(1, 5);
          _retryAt = DateTime.now().add(
            e is ApiException && e.retryAfter != null
                ? e.retryAfter!
                : Duration(seconds: 2 << _failures),
          );
          loading = false;
          _notify();
        }
      }
    }
  }

  void adoptSeenOrders(Set<String> ids) =>
      _seenNewOrders = Set.unmodifiable(ids);

  ValueNotifier<DetailSnapshot> watchDetail(OrderRecord initial) {
    final state = snapshots.details.putIfAbsent(
      initial.id,
      () => ValueNotifier(DetailSnapshot(order: initial, loading: true)),
    );
    unawaited(refreshDetail(initial.id));
    return state;
  }

  void releaseDetail(String id) {
    snapshots.details.remove(id)?.dispose();
    _detailFlights.remove(id);
  }

  final _detailFlights = <String, Future<void>>{};
  Future<void> refreshDetail(String id) {
    final running = _detailFlights[id];
    if (running != null) return running;
    late final Future<void> future;
    future = _fetchDetail(id).whenComplete(() {
      if (identical(_detailFlights[id], future)) _detailFlights.remove(id);
    });
    return _detailFlights[id] = future;
  }

  Future<void> _fetchDetail(String id) async {
    final g = _generation;
    final visibility = _visibilityVersion;
    final notifier = snapshots.details[id];
    try {
      final row = await _api.detail(
        id,
        orderNumber: notifier?.value.order?.orderNumber,
      );
      if (!_current(g) ||
          !_foreground ||
          visibility != _visibilityVersion ||
          notifier == null ||
          snapshots.details[id] != notifier) {
        return;
      }
      final old = notifier.value;
      if ((old.order?.version ?? 0) > row.version) {
        throw const ApiException(
          'Versi pesanan dari server belum terbaru. Muat ulang sebelum bertindak.',
        );
      }
      notifier.value = DetailSnapshot(order: row, checkedAt: DateTime.now());
    } catch (e) {
      if (!_current(g) || !_foreground || visibility != _visibilityVersion) {
        return;
      }
      if (notifier != null && snapshots.details[id] == notifier) {
        notifier.value = DetailSnapshot(
          order: notifier.value.order,
          error: e is ApiException
              ? e.message
              : 'Status belum dapat dipastikan. Muat ulang sebelum bertindak.',
        );
      }
      if (e is ApiException && (e.status == 401 || e.status == 403)) {
        _failure(e);
        _notify();
      }
    }
  }

  void _startRealtime() {
    if (!_foreground || !signedIn || _realtimeStarted || _disposed) return;
    _realtimeStarted = true;
    final g = _generation;
    _realtime.start(
      onInvalidate: () {
        if (_current(g) && _foreground) unawaited(refresh());
      },
      onStatus: (value) {
        if (_current(g)) {
          if (realtimeStatus != value) {
            realtimeStatus = value;
            _notify();
          }
        }
      },
      onNewOrder: () {
        if (_current(g) && _foreground && signedIn) {
          unawaited(refresh());
        }
      },
    );
  }

  void _failure(Object e) {
    error = e is ApiException
        ? e.message
        : 'Tindakan gagal. Periksa status sebelum mencoba kembali.';
    if (e is ApiException && (e.status == 401 || e.status == 403)) {
      // Detach all reads/mutations from the denied authorization epoch.
      ++_generation;
      _dirty = false;
      _refreshing = null;
      busy = false;
      loading = false;
      signedIn = false;
      staff = null;
      orders = const [];
      snapshots.clear();
      _realtimeStarted = false;
      _realtime.stop();
      realtimeStatus = RealtimeStatus.stopped;
    }
  }

  static const _statuses = {
    'active': {'', 'pending', 'ready', 'pos_input', 'confirmed'},
    'history': {'', 'forwarded', 'completed', 'expired', 'cancelled'},
  };

  Future<void> changeTab(String value) async {
    if (!['active', 'history'].contains(value) || _disposed) return;
    tab = value;
    if (value == 'active') selectedDay = null;
    statusFilter = '';
    offset = 0;
    ++_filterRevision;
    await refresh(force: true);
  }

  Future<void> setStatusFilter(String value) async {
    if (_disposed || !_statuses[tab]!.contains(value)) return;
    if (statusFilter == value) return;
    statusFilter = value;
    offset = 0;
    ++_filterRevision;
    await refresh(force: true);
  }

  Future<void> setSearch(String value) async {
    if (_disposed) return;
    final query = String.fromCharCodes(value.trim().runes.take(80));
    if (query == search) return;
    search = query;
    offset = 0;
    ++_filterRevision;
    await refresh(force: true);
  }

  Future<void> setSort(String value) async {
    if (_disposed || !['newest', 'oldest'].contains(value)) return;
    if (sort == value) return;
    sort = value;
    offset = 0;
    ++_filterRevision;
    await refresh(force: true);
  }

  Future<void> setSelectedDay(DateTime? value) async {
    if (_disposed || tab != 'history') return;
    final day = value == null
        ? null
        : DateTime(value.year, value.month, value.day);
    if (day == selectedDay) return;
    selectedDay = day;
    offset = 0;
    ++_filterRevision;
    await refresh(force: true);
  }

  Future<void> clearFilters() async {
    if (_disposed) return;
    if (search.isEmpty &&
        statusFilter.isEmpty &&
        selectedDay == null &&
        sort == 'newest') {
      return;
    }
    search = '';
    statusFilter = '';
    sort = 'newest';
    selectedDay = null;
    offset = 0;
    ++_filterRevision;
    await refresh(force: true);
  }

  Future<void> nextPage() async {
    if (_disposed || !hasMore || offset + pageSize > 100000) {
      return;
    }
    offset += pageSize;
    ++_filterRevision;
    await refresh(force: true);
  }

  Future<void> previousPage() async {
    if (_disposed || offset == 0) return;
    offset = (offset - pageSize).clamp(0, 100000);
    ++_filterRevision;
    await refresh(force: true);
  }

  void setForeground(bool value) {
    if (_disposed || _foreground == value) return;
    _foreground = value;
    _visibilityVersion++;
    _detailFlights.clear();
    if (!value) {
      _filterRevision++;
      _dirty = false;
      for (final detail in snapshots.details.values) {
        detail.value = DetailSnapshot(
          order: detail.value.order,
          error: 'Status akan diperiksa kembali saat aplikasi dibuka.',
        );
      }
      _realtimeStarted = false;
      _realtime.stop();
      realtimeStatus = RealtimeStatus.stopped;
      _notify();
    } else if (_user != null) {
      _startRealtime();
      unawaited(refresh(force: true));
    }
  }

  Future<T> _read<T>(Future<T> Function() action) async {
    final g = _generation;
    if (!signedIn || !_current(g)) {
      throw const ApiException('Staff login required', status: 401);
    }
    try {
      final value = await action();
      if (!_current(g)) throw const ApiException('Session changed');
      return value;
    } catch (e) {
      if (_current(g)) {
        _failure(e);
        _notify();
      }
      throw e is ApiException ? e : const ApiException('Request failed');
    }
  }

  Future<Catalog> menu() => _read(_api.menu);
  Future<ReorderDraft> prepareReorder(OrderRecord order) => _read(() {
    if (!order.isExpired) {
      throw const ApiException('Only expired orders can be reordered');
    }
    return _api.reorder(order.id);
  });
  Future<OrderRecord?> _mutate(
    bool allowed,
    Future<OrderRecord> Function(int g) action, {
    String? denial,
    void Function(OrderRecord result)? onSuccess,
  }) async {
    if (_disposed || busy) return null;
    final g = _generation;
    if (!signedIn || !_current(g) || !allowed) {
      error =
          denial ??
          'Tindakan tidak tersedia. Muat ulang dan periksa status pesanan.';
      _notify();
      return null;
    }
    busy = true;
    error = null;
    _notify();
    try {
      final result = await action(g);
      if (!_current(g)) return null;
      onSuccess?.call(result);
      snapshots.invalidate();
      await refresh(force: true);
      return _current(g) ? result : null;
    } catch (e) {
      if (_current(g)) {
        _failure(e);
        final message = error;
        if (_current(g) && signedIn) {
          await refresh(force: true);
          if (_current(g)) {
            error = '$message Periksa POS sebelum input atau pembayaran ulang.';
          }
        }
        _notify();
      }
      return null;
    } finally {
      if (_current(g)) {
        busy = false;
        _notify();
      }
    }
  }

  Future<OrderRecord?> review(OrderRecord order, List<OrderDraftLine> items) =>
      _mutate(
        order.canReview(DateTime.now()) && items.isNotEmpty,
        (_) => _api.review(order.id, order.version, items),
      );

  Future<OrderRecord?> claim(OrderRecord order, {String takeoverReason = ''}) {
    final profile = staff;
    final takeover = order.isPosInput;
    final reason = takeoverReason.trim();
    String? denial;
    var allowed = false;
    if (profile == null || !profile.hasName) {
      denial = 'Nama staf belum diisi pada profil. Hubungi admin sebelum menangani pesanan.';
    } else if (takeover) {
      allowed =
          order.canTakeOverFor(staffId: profile.id, isAdmin: profile.isAdmin) &&
          reason.runes.length >= 5 &&
          reason.runes.length <= 200;
      if (!allowed) {
        denial = 'Pesanan sedang ditangani kasir lain. Hanya admin dapat mengambil alih dengan alasan 5–200 karakter.';
      }
    } else {
      allowed =
          order.canClaim(DateTime.now()) &&
          order.reviewedVersion == order.version;
      if (!allowed) {
        denial = 'Tinjau pesanan terlebih dahulu, lalu tangani sebelum batas waktu habis.';
      }
    }
    return _mutate(
      allowed,
      (g) => _api.claimPos(
        order.id,
        order.version,
        takeoverReason: takeover ? reason : '',
      ),
      denial: denial,
      onSuccess: (result) {
        if (result.isPosInput && statusFilter.isNotEmpty) {
          statusFilter = '';
          offset = 0;
          ++_filterRevision;
        }
      },
    );
  }

  Future<OrderRecord?> forward(
    OrderRecord order, {
    required bool enteredInPos,
    required bool paidInPos,
    String reference = '',
  }) {
    final value = reference.trim();
    final allowed =
        !hasPendingPos &&
        order.canForwardFor(staff?.id) &&
        enteredInPos &&
        paidInPos &&
        value.runes.length <= 80 &&
        !value.contains(RegExp(r'[\x00-\x1f\x7f]'));
    return _mutate(
      allowed,
      (g) async {
        final attempt = PosAttempt(
          order.id,
          order.version,
          value,
          orderNumber: order.orderNumber,
        );
        final key = '${_storeKey(_user!)}.pos';
        await _storage(() => _store.write(key, attempt.encode()));
        if (!_current(g)) throw const ApiException('Sesi berubah');
        _pendingPos = attempt;
        return _sendPos(attempt, key, g);
      },
      denial: 'Hanya kasir yang menangani pesanan ini yang dapat menandainya masuk aplikasi kasir.',
      onSuccess: (result) {
        if (result.status == 'forwarded') {
          tab = 'history';
          statusFilter = '';
          selectedDay = null;
          offset = 0;
          ++_filterRevision;
        }
      },
    );
  }

  Future<OrderRecord?> retryPos() => _mutate(
    _pendingPos != null,
    (g) => _sendPos(_pendingPos!, '${_storeKey(_user!)}.pos', g),
  );

  Future<OrderRecord> _sendPos(PosAttempt attempt, String key, int g) async {
    Future<void> clear() async {
      await _storage(() => _store.delete(key));
      if (_current(g)) {
        _pendingPos = null;
        _posBlocked = false;
      }
    }

    try {
      final result = await _api.forwardPos(
        attempt.orderId,
        attempt.version,
        reference: attempt.reference,
      );
      if (_current(g)) await clear();
      return result;
    } on ApiException catch (error) {
      if (!_current(g)) rethrow;
      try {
        final current = await _api.detail(
          attempt.orderId,
          orderNumber: attempt.orderNumber,
        );
        if (!_current(g)) rethrow;
        if (current.isForwarded &&
            current.posHandoff?.cashierId == _user &&
            current.posHandoff?.posReference == attempt.reference) {
          await clear();
          return current;
        }
        if (current.version > attempt.version &&
            (current.posHandoff?.cashierId != _user || current.isForwarded)) {
          await clear();
        }
      } catch (_) {
        /* Keep frozen intent until an authoritative result is available. */
      }
      if (error.status == 401 || error.status == 403) {
        _failure(error);
      }
      rethrow;
    }
  }

  Future<OrderRecord?> submitReorder(
    ReorderDraft draft,
  ) => _mutate(!hasPendingAttempt && draft.items.isNotEmpty, (g) async {
    final attempt = CheckoutAttempt.create(draft), key = _storeKey(_user!);
    // Freeze all three values before durable storage and any network activity.
    await _storage(() => _store.write(key, attempt.encode()));
    if (!_current(g)) throw const ApiException('Session changed');
    _pending = attempt;
    _notify();
    return _sendAttempt(attempt, key, g);
  });
  Future<OrderRecord?> retryPending() => _mutate(
    _pending != null,
    (g) => _sendAttempt(_pending!, _storeKey(_user!), g),
  );
  Future<OrderRecord> _sendAttempt(
    CheckoutAttempt attempt,
    String key,
    int g,
  ) async {
    try {
      final result = await _api.createOrder(
        attempt.draft,
        attempt.key,
        attempt.token,
      );
      if (_current(g)) await _clearAttempt(key, g);
      return result;
    } on ApiException catch (e) {
      if (e.checkoutRejected && _current(g)) await _clearAttempt(key, g);
      rethrow;
    }
  }

  Future<void> _clearAttempt(String key, int g) async {
    await _storage(() => _store.delete(key));
    if (_current(g)) {
      _pending = null;
      _pendingBlocked = false;
      _notify();
    }
  }

  void clearError() {
    error = null;
    _notify();
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    ++_generation;
    unawaited(_authSubscription?.cancel());
    _realtime.dispose();
    _api.close();
    orders = const [];
    snapshots.dispose();
    lastSync.dispose();
    _pending = null;
    super.dispose();
  }
}
