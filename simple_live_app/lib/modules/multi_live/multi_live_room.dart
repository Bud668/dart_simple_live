import 'dart:async';
import 'dart:math' as math;

import 'package:get/get.dart';
import 'package:media_kit/media_kit.dart';
import 'package:simple_live_app/app/controller/app_settings_controller.dart';
import 'package:simple_live_app/app/sites.dart';
import 'package:simple_live_app/modules/live_room/player/player_controller.dart';
import 'package:simple_live_app/services/live_playback_monitor.dart';
import 'package:simple_live_app/services/live_playback_recovery.dart';
import 'package:simple_live_core/simple_live_core.dart';

/// One grid stream. No room-route, system-volume, chat or fullscreen ownership.
class MultiLiveRoom with PlayerMixin {
  MultiLiveRoom(this.site, this.requestedId);
  final Site site;
  final String requestedId;
  String get roomId => detail.value?.roomId ?? requestedId;
  String get key => '${site.id}:$requestedId';
  final detail = Rxn<LiveRoomDetail>();
  final loading = true.obs;
  final reconnecting = false.obs;
  final paused = false.obs;
  final offline = false.obs;
  final error = ''.obs;
  final qualities = <LivePlayQuality>[].obs;
  final qualityName = ''.obs;
  bool _closed = false;
  bool _disposed = false;
  bool get isClosed => _closed;
  bool get isDisposed => _disposed;
  bool _started = false;
  int _generation = 0;
  int _line = -1;
  bool _opening = false;
  int _openSerial = 0;
  Timer? _timer;
  final _clock = Stopwatch();
  final _monitor = LivePlaybackMonitor();
  final _subscriptions = <StreamSubscription<dynamic>>[];
  late final Future<void> _ready = _initialize();
  late final _recovery = LivePlaybackRecovery(
    attempt: (current) => _load(current, rotate: true),
    onExhausted: (_) {
      if (_closed) return;
      reconnecting.value = false;
      error.value = '连接中断，请刷新重试';
    },
  );

  @override
  int get playbackBufferSizeMb => math.min(16, super.playbackBufferSizeMb);

  Future<void> _initialize() async {
    // Mute before opening any media; only the grid coordinator grants sound.
    await player.setVolume(0);
    await initializePlayer();
  }

  void start() {
    if (_started || _closed) return;
    _started = true;
    _clock.start();
    _subscriptions.add(player.stream.error.listen((_) => recover()));
    _subscriptions.add(player.stream.completed.listen((done) {
      if (done) recover();
    }));
    _timer = Timer.periodic(const Duration(seconds: 2), (_) {
      final health = _monitor.observe(
        now: _clock.elapsed,
        position: player.state.position,
        playing: player.state.playing,
        buffering: player.state.buffering,
        enabled: !_closed &&
            !paused.value &&
            !loading.value &&
            !offline.value &&
            !_opening &&
            !_recovery.isRecovering &&
            !_recovery.isExhausted &&
            detail.value != null,
      );
      if (health == PlaybackHealth.stalled) recover();
      if (health == PlaybackHealth.healthy) _recovery.markHealthy();
    });
    unawaited(refresh());
  }

  Future<void> setAudioVolume(double value) async {
    if (_closed) return;
    await _ready;
    if (!_closed) await player.setVolume(value.clamp(0, 100));
  }

  Future<void> togglePause() async {
    if (_closed) return;
    paused.value = !paused.value;
    _monitor.reset();
    await _ready;
    if (_closed) return;
    if (paused.value) {
      await player.pause();
    } else if (error.value.isNotEmpty || offline.value) {
      await refresh();
    } else {
      await player.play();
    }
  }

  Future<void> selectQuality(String name) async {
    if (_closed || name == qualityName.value) return;
    qualityName.value = name;
    await refresh();
  }

  Future<void> refresh() async {
    if (_closed) return;
    final generation = ++_generation;
    _openSerial++;
    _opening = false;
    bool current() => !_closed && generation == _generation;
    _recovery.reset();
    _monitor.reset();
    reconnecting.value = false;
    loading.value = true;
    error.value = '';
    try {
      await _load(current).timeout(const Duration(seconds: 45));
    } catch (_) {
      if (current()) {
        _generation++; // Also invalidate a request that outlived the deadline.
        _openSerial++;
        _opening = false;
        error.value = '加载失败，请刷新重试';
        loading.value = false;
      }
    } finally {
      if (current()) loading.value = false;
    }
  }

  void recover() {
    if (_closed ||
        paused.value ||
        loading.value ||
        offline.value ||
        _opening ||
        _recovery.isRecovering ||
        _recovery.isExhausted ||
        detail.value == null) {
      return;
    }
    reconnecting.value = true;
    _monitor.reset();
    unawaited(_recovery.recover());
  }

  Future<PlaybackRecoveryOutcome> _load(bool Function() requestCurrent,
      {bool rotate = false}) async {
    final generation = _generation;
    bool current() => !_closed && generation == _generation && requestCurrent();
    final fresh = await site.liveSite
        .getRoomDetail(roomId: roomId)
        .timeout(const Duration(seconds: 15));
    if (!current()) return PlaybackRecoveryOutcome.offline;
    detail.value = fresh;
    if (!fresh.status && !fresh.isRecord) {
      offline.value = true;
      reconnecting.value = false;
      await _ready;
      if (current()) await player.stop();
      return PlaybackRecoveryOutcome.offline;
    }
    offline.value = false;
    final freshQualities = await site.liveSite
        .getPlayQualites(detail: fresh)
        .timeout(const Duration(seconds: 15));
    if (!current()) return PlaybackRecoveryOutcome.offline;
    if (freshQualities.isEmpty) throw StateError('No quality available');
    var index =
        freshQualities.indexWhere((q) => q.quality == qualityName.value);
    if (index < 0) index = freshQualities.length ~/ 2;
    final urls = await site.liveSite
        .getPlayUrls(detail: fresh, quality: freshQualities[index])
        .timeout(const Duration(seconds: 15));
    if (!current()) return PlaybackRecoveryOutcome.offline;
    if (urls.urls.isEmpty) throw StateError('No playable source');
    qualities.assignAll(freshQualities);
    qualityName.value = freshQualities[index].quality;
    _line = rotate ? (_line + 1) % urls.urls.length : 0;
    var url = urls.urls[_line];
    if (AppSettingsController.instance.playerForceHttps.value) {
      url = url.replaceFirst('http://', 'https://');
    }
    await _ready;
    if (!current()) return PlaybackRecoveryOutcome.offline;
    _opening = true;
    final serial = ++_openSerial;
    error.value = '';
    _monitor.reset();
    try {
      await player.open(Media(url, httpHeaders: urls.headers),
          play: !paused.value);
      if (!current()) return PlaybackRecoveryOutcome.offline;
      if (paused.value) await player.pause();
      final deadline = _clock.elapsed + const Duration(seconds: 25);
      var lastPosition = player.state.position;
      while (current() && !paused.value) {
        await Future<void>.delayed(const Duration(milliseconds: 200));
        if (!current()) return PlaybackRecoveryOutcome.offline;
        final position = player.state.position;
        if (player.state.playing &&
            !player.state.buffering &&
            !player.state.completed &&
            position > lastPosition) {
          break;
        }
        lastPosition = position;
        if (_clock.elapsed >= deadline) {
          throw TimeoutException('No playback progress');
        }
      }
      if (current()) reconnecting.value = false;
      return PlaybackRecoveryOutcome.reopened;
    } finally {
      // A stale operation must not clear a newer operation's opening state.
      if (serial == _openSerial) _opening = false;
    }
  }

  Future<void> stop() async {
    if (_closed) return;
    _closed = true;
    _generation++;
    _recovery.close();
    _timer?.cancel();
    _clock.stop();
    for (final subscription in _subscriptions) {
      await subscription.cancel();
    }
    if (_started) {
      try {
        await _ready;
      } catch (_) {/* Still release the native player. */}
      try {
        await player.stop();
      } catch (_) {/* Disposal still follows. */}
    }
  }

  Future<void> dispose() async {
    if (_disposed) return;
    await stop();
    _disposed = true;
    if (_started) await player.dispose();
  }
}
