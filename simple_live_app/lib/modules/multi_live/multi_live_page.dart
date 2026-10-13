import 'dart:async';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:simple_live_app/app/sites.dart';
import 'package:simple_live_app/modules/multi_live/multi_live_controller.dart';
import 'package:simple_live_app/modules/multi_live/multi_live_room.dart';
import 'package:simple_live_app/services/follow_service.dart';
import 'package:simple_live_app/services/live_room_link_parser.dart';
import 'package:simple_live_app/services/live_room_session_service.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

class MultiLivePage extends StatefulWidget {
  const MultiLivePage({super.key});
  @override
  State<MultiLivePage> createState() => _MultiLivePageState();
}

class _MultiLivePageState extends State<MultiLivePage> {
  late final controller = Get.find<MultiLiveController>();

  @override
  void initState() {
    super.initState();
    final session = LiveRoomSessionService.instance;
    final previous = session.active.value;
    final id = previous?.roomId;
    session.floating.value = false;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      // Both the room route and floating Video must unmount before disposal.
      if (previous != null && identical(session.active.value, previous)) {
        await session.stop();
      }
      if (!mounted) return;
      unawaited(WakelockPlus.enable());
      if (previous != null && id != null) controller.add(previous.site, id);
    });
  }

  @override
  void dispose() {
    unawaited(WakelockPlus.disable());
    super.dispose();
  }

  void message(String text) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
    }
  }

  Future<void> addRoom() async {
    if (controller.rooms.length >= 9) {
      message('最多同时观看 9 个直播间，请先关闭一个画面');
      return;
    }
    final parsed = await showDialog<ParsedLiveRoom>(
        context: context, builder: (_) => const _AddRoomDialog());
    if (!mounted || parsed == null) return;
    final site = Sites.allSites[parsed.siteId];
    if (site == null) return;
    final before = controller.rooms.length;
    final added = controller.add(site, parsed.roomId);
    if (added == null) {
      message('最多同时观看 9 个直播间');
    } else if (controller.rooms.length == before) {
      message('这个直播间已经在多画面中');
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(
          title: const Text('多画面'),
          actions: [
            IconButton(
                tooltip: '添加直播',
                onPressed: addRoom,
                icon: const Icon(Icons.add)),
            Obx(() => IconButton(
                  tooltip: controller.audioRoom.value == null ? '开启声音' : '全部静音',
                  onPressed: () => controller.selectAudio(
                      controller.audioRoom.value == null
                          ? controller.rooms.firstOrNull
                          : null),
                  icon: Icon(controller.audioRoom.value == null
                      ? Icons.volume_off
                      : Icons.volume_up),
                )),
            PopupMenuButton<String>(
              tooltip: '多画面选项',
              onSelected: (_) => controller.clear(),
              itemBuilder: (_) =>
                  [const PopupMenuItem(value: 'clear', child: Text('关闭全部画面'))],
            ),
          ],
        ),
        body: SafeArea(
            child: Column(children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
            child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Obx(() => Row(children: [
                      for (final size in MultiLiveController.layouts)
                        Padding(
                            padding: const EdgeInsets.only(right: 8),
                            child: ChoiceChip(
                              label: Text('$size 画面'),
                              selected: controller.layout.value == size,
                              showCheckmark: false,
                              onSelected: (_) {
                                if (!controller.setLayout(size)) {
                                  message('请先关闭多余的画面，再切换布局');
                                }
                              },
                            )),
                    ]))),
          ),
          Expanded(
              child: ColoredBox(
            color: const Color(0xff101317),
            child: LayoutBuilder(
                builder: (context, bounds) => Obx(() {
                      final rooms = controller.rooms.toList();
                      final size = controller.layout.value;
                      final focused = controller.focusedRoom.value;
                      final rects = multiLiveRects(size, bounds.biggest);
                      return Stack(children: [
                        for (var i = 0; i < size; i++)
                          Positioned.fromRect(
                            key: i < rooms.length
                                ? ValueKey(rooms[i].key)
                                : ValueKey('empty-$i'),
                            rect: focused != null &&
                                    i < rooms.length &&
                                    identical(rooms[i], focused)
                                ? Offset.zero & bounds.biggest
                                : rects[i],
                            child: Offstage(
                              offstage: focused != null &&
                                  (i >= rooms.length ||
                                      !identical(rooms[i], focused)),
                              child: Padding(
                                padding: const EdgeInsets.all(4),
                                child: i < rooms.length
                                    ? _RoomTile(
                                        room: rooms[i], controller: controller)
                                    : Material(
                                        color: const Color(0xff1b2027),
                                        borderRadius: BorderRadius.circular(8),
                                        clipBehavior: Clip.antiAlias,
                                        child: InkWell(
                                            onTap: addRoom,
                                            child: const Center(
                                                child: Column(
                                              mainAxisSize: MainAxisSize.min,
                                              children: [
                                                Icon(Icons.add_circle_outline,
                                                    color: Colors.white54,
                                                    size: 30),
                                                SizedBox(height: 8),
                                                Text('添加直播',
                                                    style: TextStyle(
                                                        color: Colors.white60)),
                                              ],
                                            )))),
                              ),
                            ),
                          ),
                      ]);
                    })),
          )),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            child: Obx(() => Text(
                  controller.audioError.value.isNotEmpty
                      ? controller.audioError.value
                      : '同时观看 ${controller.rooms.length}/9 · 点喇叭切换声音 · 返回会停止多画面',
                  style: Theme.of(context).textTheme.bodySmall,
                  maxLines: 2,
                )),
          ),
        ])),
      );
}

/// Stable rectangles let each native Video retain its element across layouts.
List<Rect> multiLiveRects(int count, Size size) {
  final w = size.width;
  final h = size.height;
  final portrait = w < h;
  if (count == 2) {
    return portrait
        ? [Rect.fromLTWH(0, 0, w, h / 2), Rect.fromLTWH(0, h / 2, w, h / 2)]
        : [Rect.fromLTWH(0, 0, w / 2, h), Rect.fromLTWH(w / 2, 0, w / 2, h)];
  }
  if (count == 3) {
    return portrait
        ? [
            Rect.fromLTWH(0, 0, w, h / 2),
            Rect.fromLTWH(0, h / 2, w / 2, h / 2),
            Rect.fromLTWH(w / 2, h / 2, w / 2, h / 2)
          ]
        : [
            Rect.fromLTWH(0, 0, w * 2 / 3, h),
            Rect.fromLTWH(w * 2 / 3, 0, w / 3, h / 2),
            Rect.fromLTWH(w * 2 / 3, h / 2, w / 3, h / 2)
          ];
  }
  final columns = count == 9 ? 3 : 2;
  return List.generate(
      count,
      (i) => Rect.fromLTWH((i % columns) * w / columns,
          (i ~/ columns) * h / columns, w / columns, h / columns));
}

class _RoomTile extends StatelessWidget {
  const _RoomTile({required this.room, required this.controller});
  final MultiLiveRoom room;
  final MultiLiveController controller;

  @override
  Widget build(BuildContext context) => Obx(() {
        final audible = identical(controller.audioRoom.value, room);
        final focused = identical(controller.focusedRoom.value, room);
        final detail = room.detail.value;
        final status = room.offline.value
            ? '主播暂未开播'
            : room.error.value.isNotEmpty
                ? room.error.value
                : room.loading.value
                    ? '正在连接…'
                    : room.reconnecting.value
                        ? '断流重连中…'
                        : room.paused.value
                            ? '已暂停'
                            : '';
        return LayoutBuilder(
            builder: (context, bounds) => Container(
                  decoration: BoxDecoration(
                      color: Colors.black,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                          color: audible
                              ? const Color(0xff71d6be)
                              : const Color(0xff343a44),
                          width: 2)),
                  clipBehavior: Clip.antiAlias,
                  child: Column(children: [
                    Container(
                        color: const Color(0xff20262e),
                        height: bounds.maxHeight < 90 ? 24 : 38,
                        padding: const EdgeInsets.only(left: 8),
                        child: Row(children: [
                          Expanded(
                              child: Tooltip(
                                  message:
                                      '${room.site.name} · ${detail?.userName ?? room.roomId}',
                                  child: Text(
                                      detail?.userName ??
                                          '${room.site.name} ${room.roomId}',
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                          color: Colors.white, fontSize: 12)))),
                          IconButton(
                              tooltip: audible ? '静音此画面' : '收听此画面',
                              constraints: const BoxConstraints.tightFor(
                                  width: 32, height: 34),
                              padding: EdgeInsets.zero,
                              onPressed: () =>
                                  controller.selectAudio(audible ? null : room),
                              icon: Icon(
                                  audible ? Icons.volume_up : Icons.volume_off,
                                  size: 18,
                                  color: audible
                                      ? const Color(0xff71d6be)
                                      : Colors.white54)),
                          SizedBox(
                              width: 28,
                              child: PopupMenuButton<String>(
                                tooltip: '画面操作',
                                icon: const Icon(Icons.more_vert,
                                    size: 20, color: Colors.white70),
                                padding: EdgeInsets.zero,
                                constraints:
                                    const BoxConstraints(minWidth: 160),
                                onSelected: (value) {
                                  if (value == 'pause') {
                                    unawaited(room.togglePause());
                                  }
                                  if (value == 'refresh') {
                                    unawaited(room.refresh());
                                  }
                                  if (value == 'focus') {
                                    controller.toggleFocus(room);
                                  }
                                  if (value == 'remove') {
                                    unawaited(controller.remove(room));
                                  }
                                  if (value.startsWith('quality:')) {
                                    unawaited(
                                        room.selectQuality(value.substring(8)));
                                  }
                                },
                                itemBuilder: (_) => [
                                  PopupMenuItem(
                                      value: 'pause',
                                      child: Text(
                                          room.paused.value ? '继续播放' : '暂停')),
                                  const PopupMenuItem(
                                      value: 'refresh', child: Text('刷新 / 重连')),
                                  PopupMenuItem(
                                      value: 'focus',
                                      child: Text(focused ? '还原分屏' : '放大此画面')),
                                  if (room.qualities.isNotEmpty)
                                    const PopupMenuDivider(),
                                  for (final quality in room.qualities)
                                    CheckedPopupMenuItem(
                                        value: 'quality:${quality.quality}',
                                        checked: quality.quality ==
                                            room.qualityName.value,
                                        child: Text(quality.quality)),
                                  const PopupMenuDivider(),
                                  const PopupMenuItem(
                                      value: 'remove', child: Text('关闭此画面')),
                                ],
                              )),
                        ])),
                    Expanded(
                        child: GestureDetector(
                      onDoubleTap: () => controller.toggleFocus(room),
                      child: Stack(fit: StackFit.expand, children: [
                        Video(
                            key: room.globalPlayerKey,
                            controller: room.videoController,
                            controls: NoVideoControls,
                            wakelock: false,
                            pauseUponEnteringBackgroundMode: false,
                            resumeUponEnteringForegroundMode: false),
                        if (status.isNotEmpty)
                          Center(
                              child: Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 10, vertical: 6),
                                  color: Colors.black.withValues(alpha: 0.75),
                                  child: Text(status,
                                      textAlign: TextAlign.center,
                                      style: const TextStyle(
                                          color: Colors.white70,
                                          fontSize: 12)))),
                        if (focused)
                          Positioned(
                              right: 8,
                              bottom: 8,
                              child: IconButton.filledTonal(
                                  tooltip: '还原分屏',
                                  onPressed: () => controller.toggleFocus(room),
                                  icon: const Icon(Icons.fullscreen_exit))),
                      ]),
                    )),
                  ]),
                ));
      });
}

class _AddRoomDialog extends StatefulWidget {
  const _AddRoomDialog();
  @override
  State<_AddRoomDialog> createState() => _AddRoomDialogState();
}

class _AddRoomDialogState extends State<_AddRoomDialog> {
  final input = TextEditingController();
  String siteId = 'douyu';
  bool busy = false;
  String? error;
  @override
  void dispose() {
    input.dispose();
    super.dispose();
  }

  Future<void> parse() async {
    if (busy) return;
    setState(() {
      busy = true;
      error = null;
    });
    final result =
        await LiveRoomLinkParser().parse(input.text, defaultSiteId: siteId);
    if (!mounted) return;
    if (result != null) {
      Navigator.of(context).pop(result);
    } else {
      setState(() {
        busy = false;
        error = '无法识别，请检查链接，或选择平台并输入房间号';
      });
    }
  }

  @override
  Widget build(BuildContext context) => Dialog(
          child: SizedBox(
        width: 520,
        height: 560,
        child: Padding(
            padding: const EdgeInsets.all(20),
            child: SingleChildScrollView(
                child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(children: [
                  Expanded(
                      child: Text('添加直播',
                          style: Theme.of(context).textTheme.titleLarge)),
                  IconButton(
                      tooltip: '取消添加',
                      onPressed: () => Navigator.of(context).pop(),
                      icon: const Icon(Icons.close)),
                ]),
                DropdownButton<String>(
                    value: siteId,
                    isExpanded: true,
                    items: Sites.supportSites
                        .map((site) => DropdownMenuItem(
                            value: site.id, child: Text(site.name)))
                        .toList(),
                    onChanged: busy
                        ? null
                        : (value) => setState(() => siteId = value!)),
                TextField(
                    controller: input,
                    enabled: !busy,
                    onSubmitted: (_) => parse(),
                    decoration: InputDecoration(
                        labelText: '房间号或分享链接',
                        hintText: '支持粘贴手机里的整段分享文字',
                        errorText: error,
                        errorMaxLines: 2)),
                const SizedBox(height: 12),
                FilledButton.icon(
                    onPressed: busy ? null : parse,
                    icon: busy
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2))
                        : const Icon(Icons.add),
                    label: Text(busy ? '解析中…' : '添加到多画面')),
                const SizedBox(height: 16),
                const Text('或从关注中选择'),
                const Divider(),
                SizedBox(
                    height: 220,
                    child: Obx(() {
                      final follows =
                          FollowService.instance.followList.toList();
                      if (follows.isEmpty) {
                        return const Center(child: Text('暂无关注，先用链接或房间号添加'));
                      }
                      return ListView.builder(
                          itemCount: follows.length,
                          itemBuilder: (_, index) {
                            final user = follows[index];
                            return ListTile(
                                dense: true,
                                title: Text(user.userName,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis),
                                subtitle: Text(
                                    Sites.allSites[user.siteId]?.name ??
                                        user.siteId),
                                trailing: const Icon(Icons.add_circle_outline),
                                onTap: busy
                                    ? null
                                    : () => Navigator.of(context).pop(
                                        ParsedLiveRoom(
                                            user.siteId, user.roomId)));
                          });
                    })),
              ],
            ))),
      ));
}
