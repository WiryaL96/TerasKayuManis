import 'dart:async';

import 'package:audioplayers/audioplayers.dart';
import 'package:cashier/core/order_chime.dart';
import 'package:flutter_test/flutter_test.dart';

class ChimePlayer implements AudioPlayer {
  final complete = StreamController<void>.broadcast();
  final calls = <String>[];
  AudioContext? context;
  Source? loadedSource;
  Completer<void>? sourceGate;
  @override
  Future<void> setReleaseMode(ReleaseMode mode) async {
    expect(mode, ReleaseMode.stop);
    calls.add('releaseMode');
  }

  @override
  Future<void> setPlayerMode(PlayerMode mode) async {
    expect(mode, PlayerMode.mediaPlayer);
    calls.add('playerMode');
  }

  @override
  Future<void> setAudioContext(AudioContext ctx) async {
    context = ctx;
    calls.add('context');
  }

  @override
  Future<void> setSource(Source source) async {
    loadedSource = source;
    calls.add('source');
    await sourceGate?.future;
  }

  @override
  Future<void> seek(Duration position) async {
    expect(position, Duration.zero);
    calls.add('seek');
  }

  @override
  Future<void> resume() async {
    calls.add('resume');
    complete.add(null);
  }

  @override
  Stream<void> get onPlayerComplete => complete.stream;
  @override
  Future<void> stop() async => calls.add('stop');
  @override
  Future<void> dispose() async => complete.close();
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  test(
    'chime prepares notification audio without falling back to muted media',
    () async {
      final player = ChimePlayer();
      final chime = OrderChime(player: player);
      addTearDown(chime.dispose);
      await chime.warmUp();

      expect(player.calls, ['releaseMode', 'playerMode', 'context', 'source']);
      expect(player.context?.android.usageType, AndroidUsageType.notification);
      expect(
        player.context?.android.contentType,
        AndroidContentType.sonification,
      );
      expect(
        player.context?.android.audioFocus,
        AndroidAudioFocus.gainTransientMayDuck,
      );
      expect(player.context?.iOS.category, AVAudioSessionCategory.ambient);
      expect(player.context?.iOS.options, isEmpty);
      expect((player.loadedSource as AssetSource).path, OrderChime.asset);

      await chime.play();
      await chime.play();
      expect(player.calls.where((call) => call == 'source'), hasLength(1));
      expect(player.calls.where((call) => call == 'resume'), hasLength(2));
    },
  );

  test('muting during audio preparation prevents late playback', () async {
    final player = ChimePlayer()..sourceGate = Completer<void>();
    final chime = OrderChime(player: player);
    addTearDown(chime.dispose);
    final playing = chime.play();
    await Future<void>.delayed(Duration.zero);
    expect(player.loadedSource, isNotNull);
    await chime.stop();
    player.sourceGate!.complete();
    await playing;
    expect(player.calls, contains('stop'));
    expect(player.calls, isNot(contains('resume')));
  });
}
