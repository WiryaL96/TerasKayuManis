import 'dart:async';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/services.dart';

/// Plays the bundled "new order" chime.
///
/// A single player is reused so rapid order bursts never stack overlapping
/// audio tracks. The asset is pre-loaded early so the first chime is not
/// delayed by file copying, and a system alert is used as a last-resort
/// fallback if the media pipeline is unavailable on the device.
class OrderChime {
  OrderChime({AudioPlayer? player}) : _player = player ?? AudioPlayer();
  static const asset = 'sound/chaching_notif.mp3';

  final AudioPlayer _player;
  bool _disposed = false;
  bool _prepared = false;
  Future<void>? _preparing;
  bool _playing = false;
  int _generation = 0;

  /// Pre-loads and configures the player. Safe to call repeatedly.
  Future<void> warmUp() {
    if (_disposed || _prepared) return Future.value();
    return _preparing ??= _prepare().whenComplete(() => _preparing = null);
  }

  Future<void> _prepare() async {
    try {
      await _player.setReleaseMode(ReleaseMode.stop);
      await _player.setPlayerMode(PlayerMode.mediaPlayer);
      await _player.setAudioContext(
        AudioContext(
          android: const AudioContextAndroid(
            isSpeakerphoneOn: false,
            stayAwake: false,
            contentType: AndroidContentType.sonification,
            usageType: AndroidUsageType.notification,
            audioFocus: AndroidAudioFocus.gainTransientMayDuck,
          ),
          // Ambient mixes implicitly. Explicit mixWithOthers is invalid for
          // this category and asserts even when constructing on Android.
          iOS: AudioContextIOS(category: AVAudioSessionCategory.ambient),
        ),
      );
      await _player.setSource(AssetSource(asset));
      _prepared = true;
    } catch (_) {
      _prepared = false;
    }
  }

  Future<void> play() async {
    if (_disposed || _playing) return;
    final generation = _generation;
    _playing = true;
    try {
      await warmUp();
      if (_disposed || generation != _generation) return;
      final finished = Completer<void>();
      void complete() {
        if (!finished.isCompleted) finished.complete();
      }

      final subscription = _player.onPlayerComplete.listen(
        (_) => complete(),
        onError: (Object _) => complete(),
        onDone: complete,
      );
      try {
        await _playOnce(generation);
        await finished.future.timeout(
          const Duration(seconds: 3),
          onTimeout: () {},
        );
      } finally {
        // Future.timeout alone does not cancel a stream subscription.
        await subscription.cancel();
      }
    } finally {
      _playing = false;
    }
  }

  Future<void> _playOnce(int generation) async {
    try {
      await warmUp();
      if (_disposed || generation != _generation) return;
      await _player.seek(Duration.zero);
      if (_disposed || generation != _generation) return;
      await _player.resume();
      if (!_disposed && generation != _generation) await _player.stop();
      return;
    } catch (_) {
      _prepared = false;
    }
    if (_disposed || generation != _generation) return;
    try {
      await _player.play(AssetSource(asset));
      if (!_disposed && generation != _generation) await _player.stop();
      return;
    } catch (_) {
      // Never let a missing audio route silence a new-order alert.
    }
    if (_disposed || generation != _generation) return;
    try {
      await SystemSound.play(SystemSoundType.alert);
    } catch (_) {}
  }

  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    _generation++;
    try {
      await _player.dispose();
    } catch (_) {}
  }

  Future<void> stop() async {
    _generation++;
    try {
      await _player.stop();
    } catch (_) {}
  }
}
