enum PlaybackHealth { waiting, healthy, stalled }

/// Uses media progress instead of the optimistic `playing` flag to detect stalls.
class LivePlaybackMonitor {
  LivePlaybackMonitor({
    this.stallTimeout = const Duration(seconds: 30),
    this.healthyDuration = const Duration(seconds: 30),
  });

  final Duration stallTimeout;
  final Duration healthyDuration;
  Duration? _position;
  Duration? _lastProgress;
  Duration? _healthySince;

  PlaybackHealth observe({
    required Duration now,
    required Duration position,
    required bool playing,
    required bool buffering,
    required bool enabled,
  }) {
    if (!enabled || !playing) {
      reset(); // A user pause must not reopen the stream.
      return PlaybackHealth.waiting;
    }
    if (_position == null) {
      _position = position;
      _lastProgress = now;
      return PlaybackHealth.waiting;
    }
    final advanced = position > _position!;
    final timestampReset = position < _position!;
    _position = position;
    if (advanced || timestampReset) _lastProgress = now;
    if (advanced && !buffering) {
      _healthySince ??= now;
      if (now - _healthySince! >= healthyDuration) {
        return PlaybackHealth.healthy;
      }
    } else {
      _healthySince = null;
    }
    if (now - _lastProgress! >= stallTimeout) {
      reset();
      return PlaybackHealth.stalled;
    }
    return PlaybackHealth.waiting;
  }

  void reset() {
    _position = null;
    _lastProgress = null;
    _healthySince = null;
  }
}
