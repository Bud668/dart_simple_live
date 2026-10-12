import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:simple_live_app/services/live_playback_recovery.dart';

void main() {
  test('simultaneous error/end events fetch and open one fresh source',
      () async {
    final delay = Completer<void>();
    var fetches = 0;
    final recovery = LivePlaybackRecovery(
      delay: (_) => delay.future,
      attempt: (_) async {
        fetches++;
        return PlaybackRecoveryOutcome.reopened;
      },
      onExhausted: (_) => fail('must restore the stream'),
    );
    final first = recovery.recover();
    final second = recovery.recover();
    expect(identical(first, second), isTrue);
    delay.complete();
    await first;
    expect(fetches, 1);
  });

  test('failed requests back off and exhaust without reporting offline',
      () async {
    final delays = <int>[];
    var failures = 0;
    final recovery = LivePlaybackRecovery(
      delay: (duration) async {
        delays.add(duration.inSeconds);
      },
      attempt: (_) async => throw StateError('network timeout'),
      onExhausted: (_) => failures++,
    );
    await recovery.recover();
    await recovery.recover();
    expect(delays, [1, 2, 4]);
    expect(failures, 1);
  });

  test('failure to confirm playback retries and duplicate events are coalesced',
      () async {
    var fetches = 0;
    late LivePlaybackRecovery recovery;
    recovery = LivePlaybackRecovery(
      delay: (_) async {},
      attempt: (_) async {
        fetches++;
        if (fetches == 1) {
          unawaited(recovery.recover());
          throw StateError('no playback progress');
        }
        return PlaybackRecoveryOutcome.reopened;
      },
      onExhausted: (_) => fail('second address should work'),
    );
    await recovery.recover();
    expect(fetches, 2);
  });

  test('timed-out requests cannot apply a response to a later attempt',
      () async {
    final source = Completer<void>();
    var calls = 0;
    var staleApplied = false;
    final recovery = LivePlaybackRecovery(
      attemptTimeout: const Duration(milliseconds: 10),
      delay: (_) async {},
      attempt: (isCurrent) async {
        calls++;
        if (calls == 1) {
          await source.future;
          staleApplied = isCurrent();
        }
        return PlaybackRecoveryOutcome.reopened;
      },
      onExhausted: (_) => fail('second request should succeed'),
    );
    await recovery.recover();
    source.complete();
    await Future<void>.delayed(Duration.zero);
    expect(calls, 2);
    expect(staleApplied, isFalse);
  });

  test('confirmed offline stops retries', () async {
    var fetches = 0;
    final recovery = LivePlaybackRecovery(
      delay: (_) async {},
      attempt: (_) async {
        fetches++;
        return PlaybackRecoveryOutcome.offline;
      },
      onExhausted: (_) => fail('offline is a platform result'),
    );
    await recovery.recover();
    expect(fetches, 1);
  });

  test('closing during backoff prevents source requests', () async {
    final delay = Completer<void>();
    final recovery = LivePlaybackRecovery(
      delay: (_) => delay.future,
      attempt: (_) async => throw StateError('must not run'),
      onExhausted: (_) => fail('closed controllers must not update UI'),
    );
    final future = recovery.recover();
    recovery.close();
    delay.complete();
    await future;
  });

  test('manual refresh invalidates an in-flight source response', () async {
    final source = Completer<void>();
    var applied = false;
    final recovery = LivePlaybackRecovery(
      delay: (_) async {},
      attempt: (isCurrent) async {
        await source.future;
        if (isCurrent()) applied = true;
        return PlaybackRecoveryOutcome.reopened;
      },
      onExhausted: (_) => fail('stale response must be ignored'),
    );
    final future = recovery.recover();
    await Future<void>.delayed(Duration.zero);
    recovery.reset();
    source.complete();
    await future;
    expect(applied, isFalse);
  });

  test('short repeated disconnects stop until playback becomes healthy',
      () async {
    var failures = 0;
    var fetches = 0;
    final recovery = LivePlaybackRecovery(
      delay: (_) async {},
      attempt: (_) async {
        fetches++;
        return PlaybackRecoveryOutcome.reopened;
      },
      onExhausted: (_) => failures++,
    );
    for (var i = 0; i < 5; i++) {
      await recovery.recover();
    }
    expect(fetches, 3);
    expect(failures, 1);
    recovery.markHealthy();
    await recovery.recover();
    expect(fetches, 4);
    expect(recovery.attempts, 1);
  });
}
