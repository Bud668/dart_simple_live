import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:simple_live_app/services/live_room_session_service.dart';

/// A draggable player above the app's navigator, retained while browsing pages.
class LiveMiniPlayer extends StatefulWidget {
  const LiveMiniPlayer({super.key});

  @override
  State<LiveMiniPlayer> createState() => _LiveMiniPlayerState();
}

class _LiveMiniPlayerState extends State<LiveMiniPlayer> {
  Offset? _position;

  @override
  Widget build(BuildContext context) {
    final session = LiveRoomSessionService.instance;
    return Obx(() {
      final controller = session.active.value;
      if (!session.floating.value || controller == null) {
        return const SizedBox.shrink();
      }
      return LayoutBuilder(builder: (context, bounds) {
        final width = math.min(320.0, math.max(0.0, bounds.maxWidth - 24));
        final height =
            math.min(width * 9 / 16 + 40, math.max(0.0, bounds.maxHeight - 24));
        if (width == 0 || height <= 40) return const SizedBox.shrink();
        final maxX = math.max(0.0, bounds.maxWidth - width);
        final maxY = math.max(0.0, bounds.maxHeight - height);
        final preferred = _position ?? Offset(maxX - 12, maxY - 72);
        final position = Offset(
            preferred.dx.clamp(0.0, maxX), preferred.dy.clamp(0.0, maxY));
        return Stack(children: [
          Positioned(
            left: position.dx,
            top: position.dy,
            width: width,
            height: height,
            child: GestureDetector(
              key: const ValueKey('live-mini-player'),
              onTap: session.resume,
              onPanUpdate: (event) => setState(() {
                final next = position + event.delta;
                _position =
                    Offset(next.dx.clamp(0.0, maxX), next.dy.clamp(0.0, maxY));
              }),
              child: Material(
                elevation: 12,
                color: Colors.black,
                borderRadius: BorderRadius.circular(12),
                clipBehavior: Clip.antiAlias,
                child: Column(children: [
                  SizedBox(
                      height: 40,
                      child: Row(children: [
                        const SizedBox(width: 10),
                        Expanded(
                            child: Obx(() => Text(
                                controller.detail.value?.userName ??
                                    controller.site.name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                    color: Colors.white, fontSize: 13)))),
                        IconButton(
                            tooltip: '返回直播间',
                            onPressed: session.resume,
                            icon: const Icon(Icons.open_in_full,
                                color: Colors.white, size: 18)),
                        IconButton(
                            tooltip: '关闭小窗并停止播放',
                            onPressed: session.stop,
                            icon: const Icon(Icons.close,
                                color: Colors.white, size: 18)),
                      ])),
                  Expanded(
                      child: Stack(fit: StackFit.expand, children: [
                    Video(
                        key: controller.globalPlayerKey,
                        controller: controller.videoController,
                        controls: NoVideoControls,
                        wakelock: false,
                        fit: BoxFit.contain),
                    Obx(() {
                      final message = controller.loadError.value
                          ? '加载失败，点击返回重试'
                          : controller.reconnecting.value
                              ? '正在重新连接'
                              : controller.errorMsg.value.isNotEmpty
                                  ? '连接中断，点击返回重试'
                                  : !controller.liveStatus.value
                                      ? '正在加载直播'
                                      : '';
                      if (message.isEmpty) return const SizedBox.shrink();
                      return IgnorePointer(
                          child: Center(
                              child: Container(
                                  padding: const EdgeInsets.all(8),
                                  color: Colors.black54,
                                  child: Text(message,
                                      style: const TextStyle(
                                          color: Colors.white,
                                          fontSize: 12)))));
                    }),
                    Positioned(
                        left: 4,
                        bottom: 0,
                        child: StreamBuilder<bool>(
                            stream: controller.player.stream.playing,
                            initialData: controller.player.state.playing,
                            builder: (context, snapshot) => IconButton(
                                  tooltip:
                                      snapshot.data == true ? '暂停' : '继续播放',
                                  onPressed: controller.player.playOrPause,
                                  icon: Icon(
                                      snapshot.data == true
                                          ? Icons.pause
                                          : Icons.play_arrow,
                                      color: Colors.white),
                                ))),
                    const Positioned(
                        right: 8,
                        bottom: 10,
                        child: IgnorePointer(
                            child: Text('点击画面返回直播间',
                                style: TextStyle(
                                    color: Colors.white70, fontSize: 11)))),
                  ])),
                ]),
              ),
            ),
          ),
        ]);
      });
    });
  }
}
