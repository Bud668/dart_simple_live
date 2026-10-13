import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'package:flutter/services.dart';
import 'package:window_manager/window_manager.dart';
import 'package:simple_live_app/modules/multi_live/multi_live_danmaku.dart';
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

class _MultiLivePageState extends State<MultiLivePage>
    with WindowListener, WidgetsBindingObserver {
  late final controller = Get.find<MultiLiveController>();
  bool _fullScreen = false;
  bool _showTools = true;
  bool _changingFullScreen = false;
  Timer? _hideTools;
  final _keyboardFocus = FocusNode();

  bool get _desktop =>
      Platform.isWindows || Platform.isLinux || Platform.isMacOS;

  Future<void> _setFullScreen(bool value) async {
    if (_changingFullScreen || _fullScreen == value) return;
    _changingFullScreen = true;
    try {
      if (_desktop) {
        await windowManager.setFullScreen(value);
      } else {
        await SystemChrome.setEnabledSystemUIMode(
            value ? SystemUiMode.immersiveSticky : SystemUiMode.edgeToEdge);
      }
      if (!mounted) {
        if (value) {
          if (_desktop) {
            await windowManager.setFullScreen(false);
          } else {
            await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
          }
        }
        return;
      }
      setState(() => _fullScreen = value);
      _revealTools();
    } catch (_) {
      message('全屏切换失败，请重试');
    } finally {
      _changingFullScreen = false;
    }
  }

  void _revealTools() {
    _hideTools?.cancel();
    if (!_showTools && mounted) setState(() => _showTools = true);
    if (_fullScreen) {
      _hideTools = Timer(const Duration(seconds: 3), () {
        if (mounted) setState(() => _showTools = false);
      });
    }
  }

  @override
  void didChangeMetrics() {
    // Windows may resize without emitting the plugin full-screen event.
    unawaited(_syncNativeFullScreen());
  }

  Future<void> _syncNativeFullScreen() async {
    if (!_desktop || !_fullScreen || _changingFullScreen) return;
    try {
      final nativeFullScreen = await windowManager.isFullScreen();
      if (mounted && !_changingFullScreen && !nativeFullScreen) {
        onWindowLeaveFullScreen();
      }
    } catch (_) {/* A later window event can resynchronize. */}
  }

  @override
  void onWindowLeaveFullScreen() {
    if (!mounted || !_fullScreen) return;
    _hideTools?.cancel();
    setState(() {
      _fullScreen = false;
      _showTools = true;
    });
  }

  @override
  void initState() {
    super.initState();
    if (_desktop) windowManager.addListener(this);
    WidgetsBinding.instance.addObserver(this);
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
    _hideTools?.cancel();
    if (_desktop) windowManager.removeListener(this);
    WidgetsBinding.instance.removeObserver(this);
    _keyboardFocus.dispose();
    if (_fullScreen) {
      if (_desktop) {
        unawaited(windowManager.setFullScreen(false));
      } else {
        unawaited(SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge));
      }
    }
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
    if (!mounted) return;
    _keyboardFocus.requestFocus();
    _revealTools();
    if (parsed == null) return;
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

  List<Widget> _actions() => [
        IconButton(
            tooltip: '添加直播', onPressed: addRoom, icon: const Icon(Icons.add)),
        Obx(() => IconButton(
              tooltip: '全部静音',
              onPressed:
                  controller.audibleRooms.isEmpty ? null : controller.muteAll,
              icon: Icon(controller.audibleRooms.isEmpty
                  ? Icons.volume_off
                  : Icons.volume_up),
            )),
        IconButton(
          tooltip: _fullScreen ? '退出多画面全屏（Esc）' : '多画面全屏（F11）',
          onPressed: () => _setFullScreen(!_fullScreen),
          icon: Icon(_fullScreen ? Icons.fullscreen_exit : Icons.fullscreen),
        ),
        PopupMenuButton<String>(
          tooltip: '多画面选项',
          onSelected: (_) => controller.clear(),
          itemBuilder: (_) =>
              [const PopupMenuItem(value: 'clear', child: Text('关闭全部画面'))],
        ),
      ];

  @override
  Widget build(BuildContext context) => CallbackShortcuts(
        bindings: {
          const SingleActivator(LogicalKeyboardKey.f11): () =>
              _setFullScreen(!_fullScreen),
          const SingleActivator(LogicalKeyboardKey.escape): () {
            if (_fullScreen) {
              unawaited(_setFullScreen(false));
            } else {
              controller.focusedRoom.value = null;
            }
          },
        },
        child: Focus(
          focusNode: _keyboardFocus,
          autofocus: true,
          child: PopScope(
            canPop: !_fullScreen,
            onPopInvokedWithResult: (didPop, _) {
              if (!didPop && _fullScreen) unawaited(_setFullScreen(false));
            },
            child: Scaffold(
              appBar: _fullScreen
                  ? null
                  : AppBar(
                      title:
                          Obx(() => Text('多画面 · ${controller.rooms.length} 路')),
                      actions: _actions(),
                    ),
              body: SafeArea(
                child: MouseRegion(
                  onHover: (_) {
                    if (_fullScreen) _revealTools();
                  },
                  child: GestureDetector(
                    behavior: HitTestBehavior.translucent,
                    onTap: () {
                      if (_fullScreen) _revealTools();
                    },
                    child: Stack(fit: StackFit.expand, children: [
                      Positioned.fill(
                          child: ColoredBox(
                        color: const Color(0xff101317),
                        child: LayoutBuilder(
                            builder: (context, bounds) => Obx(() {
                                  final rooms = controller.rooms.toList();
                                  final focused = controller.focusedRoom.value;
                                  if (rooms.isEmpty) {
                                    return Center(
                                        child: FilledButton.icon(
                                      onPressed: addRoom,
                                      icon: const Icon(Icons.add),
                                      label: const Text('添加直播'),
                                    ));
                                  }
                                  final rects = multiLiveRects(
                                      rooms.length, bounds.biggest);
                                  if (rects.isEmpty) {
                                    return const SizedBox.shrink();
                                  }
                                  return Stack(children: [
                                    for (var i = 0; i < rooms.length; i++)
                                      Positioned.fromRect(
                                        key: ValueKey(rooms[i].key),
                                        rect: identical(rooms[i], focused)
                                            ? Offset.zero & bounds.biggest
                                            : rects[i],
                                        child: Offstage(
                                          offstage: focused != null &&
                                              !identical(rooms[i], focused),
                                          child: Padding(
                                            padding: EdgeInsets.all(
                                                _fullScreen ? 2 : 4),
                                            child: _RoomTile(
                                                room: rooms[i],
                                                controller: controller,
                                                showTools:
                                                    !_fullScreen || _showTools),
                                          ),
                                        ),
                                      ),
                                  ]);
                                })),
                      )),
                      if (_fullScreen && _showTools)
                        Positioned(
                            top: 8,
                            right: 8,
                            child: Material(
                              color: Theme.of(context)
                                  .colorScheme
                                  .surface
                                  .withValues(alpha: .93),
                              borderRadius: BorderRadius.circular(12),
                              child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: _actions()),
                            )),
                      Obx(() => controller.audioError.value.isEmpty
                          ? const SizedBox.shrink()
                          : Positioned(
                              bottom: 8,
                              left: 12,
                              right: 12,
                              child: Material(
                                  child: Padding(
                                      padding: const EdgeInsets.all(8),
                                      child:
                                          Text(controller.audioError.value))),
                            )),
                    ]),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
}

/// Keyed video tiles retain their players while every count fills the viewport.
List<Rect> multiLiveRects(int count, Size size) {
  if (count <= 0 || size.isEmpty) return [];
  var bestRows = 1;
  var bestScore = double.infinity;
  for (var rows = 1; rows <= count; rows++) {
    var score = 0.0;
    for (var row = 0; row < rows; row++) {
      final columns = count ~/ rows + (row < count % rows ? 1 : 0);
      final aspect = (size.width / columns) / (size.height / rows);
      final difference = math.log(aspect / (16 / 9));
      score += columns * difference * difference;
    }
    if (score < bestScore) {
      bestScore = score;
      bestRows = rows;
    }
  }
  final result = <Rect>[];
  for (var row = 0; row < bestRows; row++) {
    final columns = count ~/ bestRows + (row < count % bestRows ? 1 : 0);
    for (var column = 0; column < columns; column++) {
      result.add(Rect.fromLTRB(
          size.width * column / columns,
          size.height * row / bestRows,
          size.width * (column + 1) / columns,
          size.height * (row + 1) / bestRows));
    }
  }
  return result;
}

class _RoomTile extends StatelessWidget {
  const _RoomTile(
      {required this.room, required this.controller, required this.showTools});
  final MultiLiveRoom room;
  final MultiLiveController controller;
  final bool showTools;

  @override
  Widget build(BuildContext context) => Obx(() {
        final audible = controller.isAudible(room);
        final danmakuEnabled = room.danmakuEnabled.value;
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
                    if (showTools)
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
                                            color: Colors.white,
                                            fontSize: 12)))),
                            IconButton(
                                tooltip: audible ? '静音此画面' : '收听此画面',
                                constraints: const BoxConstraints.tightFor(
                                    width: 32, height: 34),
                                padding: EdgeInsets.zero,
                                onPressed: () => controller.toggleAudio(room),
                                icon: Icon(
                                    audible
                                        ? Icons.volume_up
                                        : Icons.volume_off,
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
                                    if (value == 'danmaku') {
                                      room.danmakuEnabled.toggle();
                                    }
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
                                      unawaited(room
                                          .selectQuality(value.substring(8)));
                                    }
                                  },
                                  itemBuilder: (_) => [
                                    CheckedPopupMenuItem(
                                        value: 'danmaku',
                                        checked: room.danmakuEnabled.value,
                                        child: const Text('顶部弹幕（小画面自动隐藏）')),
                                    PopupMenuItem(
                                        value: 'pause',
                                        child: Text(
                                            room.paused.value ? '继续播放' : '暂停')),
                                    const PopupMenuItem(
                                        value: 'refresh',
                                        child: Text('刷新 / 重连')),
                                    PopupMenuItem(
                                        value: 'focus',
                                        child:
                                            Text(focused ? '还原分屏' : '放大此画面')),
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
                        if (danmakuEnabled &&
                            !room.paused.value &&
                            !room.offline.value &&
                            detail != null &&
                            (controller.focusedRoom.value == null || focused) &&
                            bounds.maxWidth >= 320 &&
                            bounds.maxHeight >= 240)
                          Positioned(
                              top: 0,
                              left: 0,
                              right: 0,
                              height: math.min(
                                  30,
                                  (bounds.maxHeight - (showTools ? 38 : 0)) *
                                      .15),
                              child: MultiLiveDanmaku(
                                key: ValueKey('danmaku-${room.key}'),
                                createDanmaku: room.site.liveSite.getDanmaku,
                                args: detail.danmakuData,
                              )),
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
  void initState() {
    super.initState();
    final follows = FollowService.instance;
    if (follows.followList.isEmpty) {
      unawaited(follows.loadData());
    } else if (!follows.updating.value) {
      follows.startUpdateStatus();
    }
  }

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
                Row(children: [
                  const Expanded(child: Text('或从关注中选择')),
                  Obx(() => IconButton(
                        tooltip: '刷新开播状态',
                        onPressed: FollowService.instance.updating.value
                            ? null
                            : FollowService.instance.startUpdateStatus,
                        icon: FollowService.instance.updating.value
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child:
                                    CircularProgressIndicator(strokeWidth: 2))
                            : const Icon(Icons.refresh),
                      )),
                ]),
                const Divider(),
                SizedBox(
                    height: 220,
                    child: Obx(() {
                      final follows =
                          FollowService.instance.followList.toList();
                      final states = {
                        for (final user in follows)
                          user.id: user.liveStatus.value
                      };
                      follows.sort(
                          (a, b) => states[b.id]!.compareTo(states[a.id]!));
                      if (follows.isEmpty) {
                        return const Center(child: Text('暂无关注，先用链接或房间号添加'));
                      }
                      return ListView.builder(
                          itemCount: follows.length,
                          itemBuilder: (_, index) {
                            final user = follows[index];
                            return ListTile(
                                key: ValueKey('multi-follow-${user.id}'),
                                dense: true,
                                title: Text(user.userName,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis),
                                subtitle: Text(
                                    Sites.allSites[user.siteId]?.name ??
                                        user.siteId),
                                leading: Obx(() => FollowLiveStatus(
                                      status: user.liveStatus.value,
                                      updating:
                                          FollowService.instance.updating.value,
                                    )),
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

/// Unknown/failed requests are distinct from an explicit offline response.
class FollowLiveStatus extends StatelessWidget {
  const FollowLiveStatus(
      {super.key, required this.status, required this.updating});
  final int status;
  final bool updating;
  @override
  Widget build(BuildContext context) {
    final text = status == 2
        ? '直播中'
        : status == 1
            ? '未开播'
            : updating
                ? '查询中…'
                : '状态未知';
    final color = status == 2
        ? const Color(0xff16865e)
        : Theme.of(context).colorScheme.onSurfaceVariant;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
          color: color.withValues(alpha: .1),
          borderRadius: BorderRadius.circular(6)),
      child: Text(text, style: TextStyle(color: color, fontSize: 12)),
    );
  }
}
