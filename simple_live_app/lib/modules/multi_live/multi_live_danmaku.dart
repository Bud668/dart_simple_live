import 'dart:async';
import 'package:canvas_danmaku/canvas_danmaku.dart';
import 'package:flutter/material.dart';
import 'package:simple_live_app/app/controller/app_settings_controller.dart';
import 'package:simple_live_app/app/utils.dart';
import 'package:simple_live_core/simple_live_core.dart';

/// Only mounted for a visible, enabled tile. No chat history or unbounded queue.
class MultiLiveDanmaku extends StatefulWidget {
  const MultiLiveDanmaku(
      {super.key, required this.createDanmaku, required this.args});
  final LiveDanmaku Function() createDanmaku;
  final dynamic args;
  @override
  State<MultiLiveDanmaku> createState() => _MultiLiveDanmakuState();
}

class _MultiLiveDanmakuState extends State<MultiLiveDanmaku> {
  DanmakuController? _renderer;
  LiveDanmaku? _channel;
  final _clock = Stopwatch()..start();
  int _lastMessage = -1000;
  Future<void> _pending = Future.value();
  int _generation = 0;

  @override
  void initState() {
    super.initState();
    _connect();
  }

  @override
  void didUpdateWidget(covariant MultiLiveDanmaku oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.args != widget.args) _connect();
  }

  void _connect() {
    final generation = ++_generation;
    final args = widget.args;
    final create = widget.createDanmaku;
    _pending = _pending.then((_) async {
      await _stopChannel();
      if (!mounted || generation != _generation) return;
      final channel = create();
      _channel = channel;
      channel.onMessage = (message) {
        if (!mounted ||
            generation != _generation ||
            !identical(_channel, channel) ||
            message.type != LiveMessageType.chat ||
            _renderer == null ||
            _clock.elapsedMilliseconds - _lastMessage < 1000) {
          return;
        }
        for (final keyword in AppSettingsController.instance.shieldList) {
          try {
            final Pattern pattern = Utils.isRegexFormat(keyword)
                ? RegExp(Utils.removeRegexFormat(keyword))
                : keyword;
            if (message.message.contains(pattern)) return;
          } on FormatException {/* Invalid stored filters do not stop chat. */}
        }
        final text = String.fromCharCodes(message.message.runes.take(80))
            .replaceAll(RegExp(r'\s+'), ' ')
            .trim();
        if (text.isEmpty) return;
        _lastMessage = _clock.elapsedMilliseconds;
        _renderer?.addDanmaku(DanmakuContentItem(text, color: Colors.white));
      };
      try {
        await channel.start(args);
      } catch (_) {
        // Chat availability never interrupts video or starts playback recovery.
        await _stopChannel();
      }
      if (!mounted || generation != _generation) {
        channel.onMessage = null;
        channel.onReady = null;
        channel.onClose = null;
        await channel.stop();
        if (identical(_channel, channel)) _channel = null;
      }
    }).catchError((Object _) {});
  }

  Future<void> _stopChannel() async {
    final channel = _channel;
    _channel = null;
    if (channel == null) return;
    channel.onMessage = null;
    channel.onReady = null;
    channel.onClose = null;
    try {
      await channel.stop();
    } catch (_) {/* Best-effort chat cleanup. */}
  }

  @override
  void dispose() {
    _generation++;
    _renderer = null;
    _clock.stop();
    unawaited(_stopChannel());
    // A delayed start may allocate a socket after the first stop.
    unawaited(_pending.then((_) => _stopChannel()));
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => IgnorePointer(
        child: ExcludeSemantics(
            child: ClipRect(
                child: DanmakuScreen(
          createdController: (controller) => _renderer = controller,
          option: DanmakuOption(
              fontSize: 12,
              duration: 8,
              opacity: .55,
              area: 1,
              safeArea: false,
              massiveMode: false,
              hideTop: true,
              hideBottom: true,
              hideSpecial: true),
        ))),
      );
}
