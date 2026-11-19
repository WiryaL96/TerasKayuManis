import 'dart:async';
import 'dart:collection';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Local, bounded diagnostics. No URLs, headers, order IDs, names or raw errors.
class Diagnostics {
  static final instance = Diagnostics();
  final _events = ListQueue<Map<String, Object>>();
  int _requests = 0, _failures = 0;
  final _storage = const FlutterSecureStorage();
  static const _key = 'tkm.diagnostics.failure.v1';
  String? _previousFailure;
  bool _saving = false;
  void request(Duration elapsed, bool succeeded, {int? status}) {
    _requests++;
    if (!succeeded) _failures++;
    _record({
      'kind': 'request',
      'ms': elapsed.inMilliseconds,
      'ok': succeeded,
      'status': status ?? 0,
    });
  }

  void failure(String source) {
    _record({'kind': 'error', 'source': source});
    if (_saving) return;
    _saving = true;
    unawaited(
      _storage
          .write(
            key: _key,
            value: jsonEncode({
              'at': DateTime.now().toUtc().toIso8601String(),
              'source': source,
            }),
          )
          .timeout(const Duration(seconds: 2))
          .catchError((Object _) {})
          .whenComplete(() => _saving = false),
    );
  }

  Future<void> restore() async {
    try {
      _previousFailure = await _storage
          .read(key: _key)
          .timeout(const Duration(seconds: 2));
    } catch (_) {}
  }

  void _record(Map<String, Object> event) {
    _events.add({'at': DateTime.now().toUtc().toIso8601String(), ...event});
    while (_events.length > 80) {
      _events.removeFirst();
    }
  }

  String report() => const JsonEncoder.withIndent('  ').convert({
    'version': '0.2.0+2',
    'mode': kReleaseMode
        ? 'release'
        : kProfileMode
        ? 'profile'
        : 'debug',
    'requests': _requests,
    'failures': _failures,
    'previous_failure': _previousFailure,
    'events': _events.toList(),
  });
  static void install() {
    final previous = FlutterError.onError;
    FlutterError.onError = (details) {
      instance.failure('flutter');
      if (!kReleaseMode) previous?.call(details);
    };
    PlatformDispatcher.instance.onError = (error, stack) {
      instance.failure('platform');
      if (!kReleaseMode) {
        FlutterError.presentError(
          FlutterErrorDetails(exception: error, stack: stack),
        );
      }
      return true;
    };
  }
}
