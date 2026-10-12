import 'package:flutter_test/flutter_test.dart';
import 'package:simple_live_app/services/live_playback_monitor.dart';

void main() {
  PlaybackHealth sample(LivePlaybackMonitor monitor, int now, int position,
      {bool playing = true, bool buffering = false, bool enabled = true}) {
    return monitor.observe(
        now: Duration(seconds: now),
        position: Duration(seconds: position),
        playing: playing,
        buffering: buffering,
        enabled: enabled);
  }

  test('silent buffering stall recovers even while playing remains true', () {
    final monitor = LivePlaybackMonitor();
    sample(monitor, 0, 5);
    expect(sample(monitor, 29, 5, buffering: true), PlaybackHealth.waiting);
    expect(sample(monitor, 30, 5, buffering: true), PlaybackHealth.stalled);
  });

  test('pausing and disabled monitoring never trigger reconnection', () {
    final monitor = LivePlaybackMonitor();
    sample(monitor, 0, 5);
    expect(sample(monitor, 60, 5, playing: false), PlaybackHealth.waiting);
    expect(sample(monitor, 120, 5, enabled: false), PlaybackHealth.waiting);
    expect(sample(monitor, 121, 5), PlaybackHealth.waiting);
  });

  test('retry budget resets after sustained progress following buffering', () {
    final monitor = LivePlaybackMonitor();
    sample(monitor, 0, 0);
    sample(monitor, 2, 2);
    sample(monitor, 30, 29, buffering: true);
    expect(sample(monitor, 32, 30), PlaybackHealth.waiting);
    expect(sample(monitor, 60, 58), PlaybackHealth.waiting);
    expect(sample(monitor, 62, 60), PlaybackHealth.healthy);
  });

  test('timestamp discontinuities and new sources restart health tracking', () {
    final monitor = LivePlaybackMonitor();
    sample(monitor, 0, 100);
    sample(monitor, 2, 102);
    expect(sample(monitor, 30, 1), PlaybackHealth.waiting);
    expect(sample(monitor, 31, 2), PlaybackHealth.waiting);
    monitor.reset();
    expect(sample(monitor, 90, 0), PlaybackHealth.waiting);
  });
}
