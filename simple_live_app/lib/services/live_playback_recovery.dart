import 'dart:async';

enum PlaybackRecoveryOutcome { reopened, offline }

/// Coalesces player error/end events and bounds retries until playback is stable.
class LivePlaybackRecovery {
  LivePlaybackRecovery({
    required this.attempt,
    required this.onExhausted,
    this.maxAttempts = 3,
    this.attemptTimeout = const Duration(seconds: 45),
    Future<void> Function(Duration)? delay,
  }) : _delay = delay ?? Future<void>.delayed;

  final Future<PlaybackRecoveryOutcome> Function(bool Function() isCurrent)
      attempt;
  final void Function(Object error) onExhausted;
  final int maxAttempts;
  final Duration attemptTimeout;
  final Future<void> Function(Duration) _delay;
  int _generation = 0;
  int attempts = 0;
  bool _closed = false;
  bool _exhausted = false;
  int _attemptSerial = 0;
  Future<void>? _inFlight;
  bool get isRecovering => _inFlight != null;
  bool get isExhausted => _exhausted;

  Future<void> recover() {
    if (_closed) return Future<void>.value();
    if (_inFlight != null) {
      return _inFlight!;
    }
    if (attempts >= maxAttempts) {
      _notifyExhausted(StateError('直播连接多次中断'));
      return Future<void>.value();
    }
    final generation = _generation;
    final completer = Completer<void>();
    _inFlight = completer.future;
    unawaited(_run(generation).whenComplete(() {
      if (generation == _generation) _inFlight = null;
      completer.complete();
    }));
    return completer.future;
  }

  Future<void> _run(int generation) async {
    bool isCurrent() => !_closed && generation == _generation;
    Object lastError = StateError('直播连接中断');
    while (isCurrent() && attempts < maxAttempts) {
      attempts++;
      await _delay(Duration(seconds: 1 << (attempts - 1)));
      if (!isCurrent()) return;
      final serial = ++_attemptSerial;
      bool attemptIsCurrent() => isCurrent() && serial == _attemptSerial;
      try {
        // The callback must verify actual playback, not just player.open().
        final outcome = await attempt(attemptIsCurrent).timeout(attemptTimeout);
        if (!isCurrent()) return;
        if (outcome == PlaybackRecoveryOutcome.offline ||
            outcome == PlaybackRecoveryOutcome.reopened) {
          return;
        }
      } catch (error) {
        lastError = error;
      } finally {
        // A timed-out response may still arrive; prevent it applying old data.
        if (serial == _attemptSerial) _attemptSerial++;
      }
    }
    if (isCurrent()) _notifyExhausted(lastError);
  }

  void _notifyExhausted(Object error) {
    if (_exhausted) return;
    _exhausted = true;
    onExhausted(error);
  }

  void markHealthy() {
    if (!_closed && _inFlight == null) {
      attempts = 0;
      _exhausted = false;
    }
  }

  /// Invalidates any delayed/network work from the previous playback session.
  void reset() {
    _generation++;
    attempts = 0;
    _exhausted = false;
    _attemptSerial++;
    _inFlight = null;
  }

  void close() {
    _closed = true;
    reset();
  }
}
