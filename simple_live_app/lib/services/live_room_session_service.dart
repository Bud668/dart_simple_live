import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:get/get.dart';
import 'package:simple_live_app/app/log.dart';
import 'package:simple_live_app/app/sites.dart';
import 'package:simple_live_app/modules/live_room/live_room_controller.dart';
import 'package:simple_live_app/routes/route_path.dart';

/// Owns playback independently of the room route. At most one room plays.
class LiveRoomSessionService extends GetxService {
  LiveRoomSessionService({
    LiveRoomController Function(Site, String)? createController,
    Future<void> Function()? afterFrame,
  })  : _createController = createController ??
            ((site, id) => LiveRoomController(pSite: site, pRoomId: id)),
        _afterFrame = afterFrame ?? (() => WidgetsBinding.instance.endOfFrame);

  static LiveRoomSessionService get instance => Get.find();
  final LiveRoomController Function(Site, String) _createController;
  final Future<void> Function() _afterFrame;
  final active = Rxn<LiveRoomController>();
  final floating = false.obs;
  String? _activeTag;
  int _serial = 0;
  bool _resuming = false;

  LiveRoomController enter(Site site, String roomId) {
    final previous = active.value;
    if (previous != null &&
        previous.site.id == site.id &&
        (previous.roomId == roomId || previous.pRoomId == roomId)) {
      floating.value = false;
      return previous; // Preserve the player, signed URL and paused state.
    }
    final oldTag = _activeTag;
    floating.value = false;
    _activeTag = 'live-session-${++_serial}';
    final controller = Get.put(_createController(site, roomId),
        tag: _activeTag, permanent: true);
    active.value = controller;
    if (previous != null && oldTag != null) {
      unawaited(_retire(previous, oldTag));
    }
    return controller;
  }

  void leave(LiveRoomController controller) {
    if (!identical(active.value, controller)) return;
    if (controller.loadError.value ||
        (controller.detail.value != null && !controller.liveStatus.value)) {
      unawaited(stop());
      return;
    }
    controller.detachRoomUi();
    floating.value = true;
  }

  Future<void> resume() async {
    final controller = active.value;
    if (controller == null || _resuming) return;
    _resuming = true;
    floating.value = false;
    try {
      // Remove the mini Video before mounting the same controller in the room.
      await _afterFrame();
      if (!identical(active.value, controller)) return;
      if (Uri.parse(Get.currentRoute).path != RoutePath.kLiveRoomDetail) {
        unawaited(Get.toNamed<void>(RoutePath.kLiveRoomDetail,
                arguments: controller.site,
                parameters: {'roomId': controller.roomId}) ??
            Future<void>.value());
      }
    } finally {
      _resuming = false;
    }
  }

  Future<void> stop() async {
    final controller = active.value;
    final tag = _activeTag;
    floating.value = false;
    active.value = null;
    _activeTag = null;
    if (controller != null && tag != null) await _retire(controller, tag);
  }

  Future<void> _retire(LiveRoomController controller, String tag) async {
    // Stop sound/requests immediately, dispose the renderer after it unmounts.
    final stopped = controller.stopSessionPlayback().catchError((Object error) {
      Log.e('关闭直播播放失败：$error', StackTrace.current);
    });
    await _afterFrame();
    await stopped;
    if (Get.isRegistered<LiveRoomController>(tag: tag) &&
        identical(Get.find<LiveRoomController>(tag: tag), controller)) {
      Get.delete<LiveRoomController>(tag: tag, force: true);
    }
  }
}
