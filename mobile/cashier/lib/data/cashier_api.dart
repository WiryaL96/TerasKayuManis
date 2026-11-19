import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import 'package:http/http.dart' as http;

import '../core/app_config.dart';
import '../core/diagnostics.dart';
import '../domain/models.dart';
import '../domain/order_sync.dart';
import 'auth_session.dart';

class ApiException implements Exception {
  const ApiException(this.message, {this.status, this.code, this.retryAfter});
  final String message;
  final int? status;
  final String? code;
  final Duration? retryAfter;
  bool get checkoutRejected => status == 409 && code == 'checkout_rejected';
  @override
  String toString() => message;
}

class CashierApi {
  CashierApi({required this.config, required this.auth, http.Client? client})
    : _client = client ?? http.Client() {
    _observedUser = auth.userId;
    _authSubscription = auth.changes.listen(
      (_) => _syncIdentity(),
      onError: (Object _) => ++_authGeneration,
    );
  }
  final AppConfig config;
  final AuthSession auth;
  final http.Client _client;
  late final StreamSubscription<void> _authSubscription;
  int _authGeneration = 0;
  String? _observedUser;
  final _requests = <Completer<void>>{};
  void _abortRequests() {
    for (final request in _requests) {
      if (!request.isCompleted) request.complete();
    }
    _requests.clear();
  }

  void _syncIdentity() {
    if (_observedUser != auth.userId) {
      _observedUser = auth.userId;
      ++_authGeneration;
      _abortRequests();
    }
  }

  DateTime? _retryAt;
  bool _closed = false;
  String get storageScope => config.storageScope;
  static final _uuid = RegExp(
    r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
  );
  String _orderPath(String id, String action) {
    if (!_uuid.hasMatch(id)) {
      throw const ApiException('Invalid order identifier');
    }
    return 'orders/$id/$action';
  }

  Future<dynamic> _request(
    String method,
    String path, {
    Map<String, String>? query,
    Object? body,
    Map<String, String> headers = const {},
    bool staff = true,
  }) async {
    if (_closed) throw const ApiException('Connection closed');
    final retryAt = _retryAt;
    if (retryAt != null && DateTime.now().isBefore(retryAt)) {
      throw ApiException(
        'Please wait before retrying',
        status: 429,
        retryAfter: retryAt.difference(DateTime.now()),
      );
    }
    _syncIdentity();
    final user = auth.userId;
    final generation = _authGeneration;
    final clock = Stopwatch()..start();
    final abort = Completer<void>();
    _requests.add(abort);
    final deadline = Timer(const Duration(seconds: 15), () {
      if (!abort.isCompleted) abort.complete();
    });
    var succeeded = false;
    int? responseStatus;
    Duration remaining() {
      final left = const Duration(seconds: 15) - clock.elapsed;
      if (left <= Duration.zero) throw TimeoutException('Request timed out');
      return left;
    }

    try {
      final token = staff
          ? await auth.accessToken().timeout(remaining())
          : null;
      if (_closed || generation != _authGeneration) {
        throw const ApiException('Session changed');
      }
      if (staff &&
          (user == null ||
              auth.userId != user ||
              token == null ||
              token.isEmpty)) {
        throw const ApiException('Staff login required', status: 401);
      }
      final base = config.apiBase.toString();
      final uri =
          (path.startsWith('/')
                  ? config.siteOrigin.resolve(path)
                  : Uri.parse(base.endsWith('/') ? base : '$base/')
                        .resolve(path))
              .replace(queryParameters: query);
      final request = http.AbortableRequest(
        method,
        uri,
        abortTrigger: abort.future,
      )..followRedirects = false;
      request.headers.addAll({
        'Accept': 'application/json',
        if (path.startsWith('/api/auth/')) 'Origin': config.wsOrigin,
        if (staff) 'Authorization': 'Bearer $token',
        ...headers,
      });
      if (body != null) {
        request.headers['Content-Type'] = 'application/json';
        request.body = jsonEncode(body);
      }
      final streamed = await _client.send(request).timeout(remaining());
      responseStatus = streamed.statusCode;
      final bytes = await _boundedBytes(streamed.stream).timeout(remaining());
      final response = http.Response.bytes(
        bytes,
        streamed.statusCode,
        headers: streamed.headers,
      );
      if (_closed || generation != _authGeneration) {
        throw const ApiException('Session changed');
      }
      if (response.statusCode < 200 || response.statusCode >= 300) {
        String? code;
        try {
          final data = jsonDecode(response.body);
          if (data is Map &&
              [
                'checkout_rejected',
                'idempotency_conflict',
              ].contains(data['code'])) {
            code = data['code'] as String;
          }
        } catch (_) {}
        if (response.statusCode == 404 &&
            method == 'GET' &&
            path.startsWith('admin/orders/') &&
            _uuid.hasMatch(path.substring('admin/orders/'.length)) &&
            response.headers['content-type']?.split(';').first.trim() ==
                'text/plain' &&
            response.body.trim() == '404 page not found') {
          // Go's router response means the older server has no detail route.
          // A JSON 404 for an actual missing order must not trigger fallback.
          code = 'staff_detail_unavailable';
        }
        Duration? retry;
        if (response.statusCode == 429) {
          final value = response.headers['retry-after'];
          final seconds = int.tryParse(value ?? '');
          DateTime? date;
          try {
            if (value != null && seconds == null) date = HttpDate.parse(value);
          } catch (_) {}
          retry = seconds != null
              ? Duration(seconds: seconds < 0 ? 0 : seconds)
              : date?.difference(DateTime.now()) ?? const Duration(seconds: 60);
          if (retry.isNegative) retry = Duration.zero;
          _retryAt = DateTime.now().add(retry);
        }
        throw ApiException(
          switch (response.statusCode) {
            401 when path == '/api/auth/cashier-pin' => 'PIN tidak sesuai atau akun kasir tidak tersedia. Periksa pilihan kasir dan PIN.',
            401 when path == '/api/auth/staff-login' =>
              'Akun atau kata sandi tidak sesuai. Periksa lalu coba lagi.',
            401 => 'Sesi kasir berakhir. Silakan masuk kembali.',
            403 => 'Akses ditolak untuk tindakan ini.',
            404 => 'Pesanan tidak ditemukan.',
            409 => 'Pesanan berubah atau sudah ditangani kasir lain. Muat ulang lalu periksa statusnya.',
            410 => 'Pembayaran tunai di aplikasi ini sudah tidak berlaku. Gunakan alur input ke aplikasi kasir.',
            429 => 'Tunggu sebentar sebelum mencoba lagi.',
            _ => 'Permintaan gagal. Periksa koneksi lalu coba lagi.',
          },
          status: response.statusCode,
          code: code,
          retryAfter: retry,
        );
      }
      if (response.statusCode == 204) {
        succeeded = true;
        return null;
      }
      final decoded = response.bodyBytes.length > 64 * 1024
          ? await compute(_decodeJson, response.body)
          : jsonDecode(response.body);
      if (_closed || generation != _authGeneration) {
        throw const ApiException('Sesi berubah');
      }
      succeeded = true;
      return decoded;
    } on ApiException {
      rethrow;
    } catch (_) {
      throw const ApiException(
        'Koneksi atau respons gagal. Periksa status pesanan sebelum mencoba lagi.',
      );
    } finally {
      deadline.cancel();
      if (!abort.isCompleted) abort.complete();
      _requests.remove(abort);
      Diagnostics.instance.request(
        clock.elapsed,
        succeeded,
        status: responseStatus,
      );
    }
  }

  static const _statuses = {
    'active': {'', 'pending', 'ready', 'pos_input', 'confirmed'},
    'history': {'', 'forwarded', 'completed', 'expired', 'cancelled'},
  };

  Future<List<OrderRecord>> listOrders({
    String tab = 'active',
    String status = '',
    String search = '',
    String sort = 'newest',
    int offset = 0,
    DateTime? day,
  }) async {
    final query = search.trim();
    if (!_statuses.containsKey(tab) ||
        !_statuses[tab]!.contains(status) ||
        (sort != 'newest' && sort != 'oldest') ||
        query.runes.length > 80 ||
        query.contains('\u0000') ||
        offset < 0 ||
        offset > 100000) {
      throw const ApiException('Filter pesanan tidak valid');
    }
    final data = await _request(
      'GET',
      'admin/orders',
      query: {
        'tab': tab,
        'summary': '1',
        if (status.isNotEmpty) 'status': status,
        if (query.isNotEmpty) 'q': query,
        'sort': sort,
        'offset': '$offset',
        if (day != null)
          'date':
              '${day.year.toString().padLeft(4, '0')}-${day.month.toString().padLeft(2, '0')}-${day.day.toString().padLeft(2, '0')}',
      },
    );
    return List.unmodifiable(
      (data as List).map(
        (v) => OrderRecord.fromJson(Map<String, dynamic>.from(v as Map)),
      ),
    );
  }

  Future<StaffProfile> me() async => StaffProfile.fromJson(
    Map<String, dynamic>.from(await _request('GET', 'admin/me') as Map),
  );

  Future<String> syncRevision() async {
    final data = await _request('GET', 'admin/sync');
    final revision = (data as Map?)?['revision'];
    if (revision is! String || revision.isEmpty) {
      throw const ApiException('Respons sinkronisasi tidak valid');
    }
    return revision;
  }

  Future<OrderSync> sync() async {
    final data = await _request('GET', 'admin/sync');
    try {
      return OrderSync.fromJson(Map<String, dynamic>.from(data as Map));
    } on FormatException {
      throw const ApiException(
        'Data sinkronisasi tidak valid. Hubungi admin untuk memeriksa layanan kasir.',
        code: 'invalid_sync_response',
      );
    } on TypeError {
      throw const ApiException(
        'Data sinkronisasi tidak valid. Hubungi admin untuk memeriksa layanan kasir.',
        code: 'invalid_sync_response',
      );
    }
  }

  Future<OrderRecord> detail(String id, {String? orderNumber}) async {
    if (!_uuid.hasMatch(id)) {
      throw const ApiException('Nomor pesanan tidak valid');
    }
    _syncIdentity();
    final generation = _authGeneration, user = auth.userId;
    void checkSession() {
      _syncIdentity();
      if (_closed || generation != _authGeneration || user != auth.userId) {
        throw const ApiException('Sesi berubah. Silakan masuk kembali.');
      }
    }

    try {
      final data = await _request('GET', 'admin/orders/$id');
      checkSession();
      return _detailRecord(data, id);
    } on ApiException catch (error) {
      if (error.code != 'staff_detail_unavailable') rethrow;
    }
    checkSession();
    final number = orderNumber?.trim() ?? '';
    if (number.isEmpty ||
        number.runes.length > 80 ||
        number.contains(RegExp(r'[\x00-\x1f\x7f]'))) {
      throw const ApiException(
        'Detail belum tersedia. Buka kembali pesanan dari antrean.',
        code: 'staff_detail_unavailable',
      );
    }

    // Fetch a fresh, full staff snapshot. Never authorize actions using the
    // clicked/cached summary, a public customer endpoint, or the first match.
    var truncated = false;
    for (final tab in ['active', 'history']) {
      for (var page = 0; page < 3; page++) {
        checkSession();
        final data = await _request(
          'GET',
          'admin/orders',
          query: {
            'tab': tab,
            'q': number,
            'sort': 'newest',
            'offset': '${page * 100}',
          },
        );
        checkSession();
        if (data is! List) throw _invalidDetail;
        final matches = data.where((row) => row is Map && row['id'] == id);
        if (matches.length > 1) throw _invalidDetail;
        if (matches.isNotEmpty) return _detailRecord(matches.single, id);
        if (data.length < 100) break;
        if (page == 2) truncated = true;
      }
    }
    throw ApiException(
      truncated
          ? 'Pencarian detail belum lengkap. Muat ulang antrean atau hubungi admin.'
          : 'Pesanan tidak ditemukan pada data terbaru. Muat ulang antrean.',
      status: truncated ? null : 404,
    );
  }

  static const _invalidDetail = ApiException(
    'Detail pesanan dari server tidak lengkap. Muat ulang atau hubungi admin.',
    code: 'invalid_order_detail',
  );

  static OrderRecord _detailRecord(dynamic data, String id) {
    try {
      if (data is! Map ||
          data['id'] != id ||
          data['order_items'] is! List ||
          (data['order_items'] as List).isEmpty) {
        throw _invalidDetail;
      }
      final order = OrderRecord.fromJson(Map<String, dynamic>.from(data));
      if (order.version < 1) throw _invalidDetail;
      return order;
    } on FormatException {
      throw _invalidDetail;
    } on TypeError {
      throw _invalidDetail;
    }
  }

  Future<WatchLease> issueWatch(String deviceId) async => WatchLease.fromJson(
    Map<String, dynamic>.from(
      await _request('POST', 'admin/watch', body: {'device_id': deviceId})
          as Map,
    ),
  );

  Future<void> revokeWatch(String token) async {
    await _request(
      'DELETE',
      'admin/watch',
      staff: false,
      headers: {'X-Watch-Token': token},
    );
  }

  Future<List<CashierRosterEntry>> listCashiers() async {
    final data = await _request('GET', '/api/auth/cashiers', staff: false);
    return List.unmodifiable(
      (data as List).map(
        (v) => CashierRosterEntry.fromJson(Map<String, dynamic>.from(v as Map)),
      ),
    );
  }

  Future<({StaffProfile profile, String accessToken, String refreshToken})>
  loginPin(String cashierId, String pin) async {
    if (!_uuid.hasMatch(cashierId) || !RegExp(r'^\d{6}$').hasMatch(pin)) {
      throw const ApiException('Pilih kasir dan masukkan PIN 6 angka');
    }
    final data = Map<String, dynamic>.from(
      await _request(
        'POST',
        '/api/auth/cashier-pin',
        body: {'cashier_id': cashierId, 'pin': pin},
        staff: false,
      ) as Map,
    );
    final session = Map<String, dynamic>.from(data['session'] as Map);
    return (
      profile: StaffProfile.fromJson(
        Map<String, dynamic>.from(data['profile'] as Map),
      ),
      accessToken: session['access_token'] as String,
      refreshToken: session['refresh_token'] as String,
    );
  }

  Future<({StaffProfile profile, String accessToken, String refreshToken})>
  loginStaff(String identifier, String password) async {
    final id = identifier.trim();
    if (id.isEmpty ||
        id.length > 254 ||
        password.isEmpty ||
        password.length > 128) {
      throw const ApiException('Isi username/email dan kata sandi akun staf');
    }
    final data = Map<String, dynamic>.from(
      await _request(
        'POST',
        '/api/auth/staff-login',
        body: {'email': id, 'password': password, 'area': 'cashier'},
        staff: false,
      ) as Map,
    );
    final session = Map<String, dynamic>.from(data['session'] as Map);
    return (
      profile: StaffProfile.fromJson(
        Map<String, dynamic>.from(data['profile'] as Map),
      ),
      accessToken: session['access_token'] as String,
      refreshToken: session['refresh_token'] as String,
    );
  }

  Future<void> logoutStaff() async {
    await _request('POST', '/api/auth/staff-logout', body: const {});
  }

  Future<Catalog> menu() async => Catalog.fromJson(
    Map<String, dynamic>.from(
      await _request('GET', 'menu', staff: false) as Map,
    ),
  );
  Future<OrderRecord> _post(
    String path,
    Object body, {
    Map<String, String> headers = const {},
  }) async => OrderRecord.fromJson(
    Map<String, dynamic>.from(
      await _request('POST', path, body: body, headers: headers) as Map,
    ),
  );
  Future<OrderRecord> review(
    String id,
    int version,
    List<OrderDraftLine> items,
  ) => _post(_orderPath(id, 'review'), {
    'expected_version': version,
    'items': items.map((i) => i.toJson()).toList(),
  });
  Future<OrderRecord> claimPos(
    String id,
    int version, {
    String takeoverReason = '',
  }) {
    final reason = takeoverReason.trim();
    if ((reason.isNotEmpty && reason.runes.length < 5) ||
        reason.runes.length > 200 ||
        reason.contains(RegExp(r'[\x00-\x1f\x7f]'))) {
      throw const ApiException('Alasan pengambilalihan tidak valid');
    }
    return _post(_orderPath(id, 'claim-pos'), {
      'expected_version': version,
      if (reason.isNotEmpty) 'takeover_reason': reason,
    });
  }

  Future<OrderRecord> forwardPos(
    String id,
    int version, {
    String reference = '',
  }) {
    final value = reference.trim();
    if (value.runes.length > 80 || value.contains(RegExp(r'[\x00-\x1f\x7f]'))) {
      throw const ApiException('Referensi POS tidak valid');
    }
    return _post(_orderPath(id, 'forward-pos'), {
      'expected_version': version,
      'pos_reference': value,
      'entered_in_pos': true,
      'paid_in_pos': true,
    });
  }

  Future<ReorderDraft> reorder(String id) async => ReorderDraft.fromJson(
    Map<String, dynamic>.from(
      await _request('GET', _orderPath(id, 'reorder')) as Map,
    ),
  );
  Future<OrderRecord> createOrder(
    ReorderDraft draft,
    String key,
    String orderToken,
  ) {
    if (key.length < 16 ||
        key.length > 128 ||
        orderToken.length < 24 ||
        orderToken.length > 256) {
      throw const ApiException('Invalid checkout attempt');
    }
    return _post(
      'orders',
      draft.toJson(),
      headers: {'Idempotency-Key': key, 'X-Order-Token': orderToken},
    );
  }

  void close() {
    _closed = true;
    _abortRequests();
    unawaited(_authSubscription.cancel());
    _client.close();
  }
}

dynamic _decodeJson(String body) => jsonDecode(body);
Future<List<int>> _boundedBytes(Stream<List<int>> stream) async {
  final bytes = <int>[];
  await for (final chunk in stream) {
    if (bytes.length + chunk.length > 4 * 1024 * 1024) {
      throw const FormatException('Response too large');
    }
    bytes.addAll(chunk);
  }
  return bytes;
}
