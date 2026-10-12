import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:dio/dio.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:get/get.dart';
import 'package:hive/hive.dart';
import 'package:media_kit/media_kit.dart';
import 'package:simple_live_app/main.dart' as app;
import 'package:simple_live_app/app/sites.dart';
import 'package:simple_live_app/routes/app_navigation.dart';
import 'package:simple_live_app/routes/route_path.dart';
import 'package:simple_live_app/services/live_room_session_service.dart';
import 'package:simple_live_app/services/sync_service.dart';
import 'package:simple_live_app/modules/search/search_controller.dart';
// Private client access is used only for counting playback requests in this probe.
// ignore: implementation_imports
import 'package:simple_live_core/src/common/http_client.dart' as core_http;
import 'package:window_manager/window_manager.dart';

class QuietMiniSyncService extends SyncService {
  @override
  // The probe deliberately avoids LAN discovery.
  // ignore: must_call_super
  void onInit() {}
}

Future<void> main(List<String> args) async {
  WidgetsFlutterBinding.ensureInitialized();
  MediaKit.ensureInitialized();
  final output = File(args.first);
  final report = <String, Object?>{};
  final flutterErrors = <String>[];
  FlutterError.onError = (details) {
    flutterErrors.add(details.exceptionAsString());
  };
  Future<void> save() =>
      output.writeAsString(const JsonEncoder.withIndent('  ').convert(report));
  Future<void> waitFor(bool Function() condition, String label,
      {int seconds = 40}) async {
    final deadline = DateTime.now().add(Duration(seconds: seconds));
    while (!condition()) {
      if (DateTime.now().isAfter(deadline)) {
        throw StateError('Timed out: $label');
      }
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
    await Future<void>.delayed(const Duration(milliseconds: 300));
  }

  void check(bool value, String label) {
    if (!value) throw StateError(label);
  }

  Element? findElement(bool Function(Widget) matches) {
    Element? found;
    void visit(Element element) {
      if (found != null) return;
      final widget = element.widget;
      if ((widget is Offstage && widget.offstage) ||
          (widget is TickerMode && !widget.enabled)) {
        return;
      }
      if (matches(element.widget)) {
        found = element;
        return;
      }
      element.visitChildren(visit);
    }

    final root = WidgetsBinding.instance.rootElement;
    if (root != null) visit(root);
    return found;
  }

  Rect rectFor(bool Function(Widget) matches) {
    final element = findElement(matches);
    final box = element?.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize) throw StateError('UI target missing');
    return box.localToGlobal(Offset.zero) & box.size;
  }

  bool isMini(Widget widget) =>
      widget.key == const ValueKey('live-mini-player');
  Future<void> tap(Offset point) async {
    GestureBinding.instance.handlePointerEvent(PointerDownEvent(
        pointer: 900,
        position: point,
        kind: ui.PointerDeviceKind.mouse,
        buttons: kPrimaryMouseButton));
    await Future<void>.delayed(const Duration(milliseconds: 60));
    GestureBinding.instance.handlePointerEvent(PointerUpEvent(
        pointer: 900, position: point, kind: ui.PointerDeviceKind.mouse));
    await Future<void>.delayed(const Duration(milliseconds: 300));
  }

  Future<void> tapTooltip(String message) =>
      tap(rectFor((widget) => widget is Tooltip && widget.message == message)
          .center);

  final profile = Directory('${output.parent.path}/profile');
  await profile.create(recursive: true);
  Hive.init(profile.path);
  Get.put<SyncService>(QuietMiniSyncService());
  var playRequests = 0;
  final counter = InterceptorsWrapper(onRequest: (options, handler) {
    if (options.uri.path.contains('/getH5Play/')) playRequests++;
    handler.next(options);
  });
  core_http.HttpClient.instance.dio.interceptors.add(counter);
  try {
    await app.initServices();
    await windowManager.ensureInitialized();
    await windowManager.setSize(const Size(1100, 760));
    final boundaryKey = GlobalKey();
    runApp(RepaintBoundary(key: boundaryKey, child: const app.MyApp()));
    await Future<void>.delayed(const Duration(seconds: 2));
    final rooms = <String>[];
    final site = Sites.allSites['douyu']!;
    final recommended = await site.liveSite.getRecommendRooms();
    for (final item in recommended.items.take(8)) {
      final detail = await site.liveSite.getRoomDetail(roomId: item.roomId);
      if (detail.status) rooms.add(detail.roomId);
      if (rooms.length >= 2) break;
    }
    check(rooms.length >= 2, 'Two live rooms required');
    final session = LiveRoomSessionService.instance;
    AppNavigator.toLiveRoomDetail(site: site, roomId: rooms.first);
    await waitFor(
        () =>
            session.active.value != null &&
            session.active.value!.player.state.playing &&
            (session.active.value!.player.state.width ?? 0) > 0 &&
            !session.active.value!.player.state.buffering,
        'initial room');
    await Future<void>.delayed(const Duration(seconds: 2));
    final room = session.active.value!;
    final requestsBefore = playRequests;
    final oldSource = room.playUrls[room.currentLineIndex];
    Get.back<void>();
    await waitFor(() => session.floating.value && findElement(isMini) != null,
        'mini after navigating back');
    final positionBefore = room.player.state.position;
    await Future<void>.delayed(const Duration(seconds: 2));
    check(
        room.player.state.position > positionBefore, 'mini playback progress');
    check(!room.isClosed, 'retained controller disposed on room pop');
    final beforeDrag = rectFor(isMini);
    final start = beforeDrag.topLeft + const Offset(70, 20);
    GestureBinding.instance.handlePointerEvent(PointerDownEvent(
        pointer: 901,
        position: start,
        kind: ui.PointerDeviceKind.mouse,
        buttons: kPrimaryMouseButton));
    for (var step = 1; step <= 5; step++) {
      GestureBinding.instance.handlePointerEvent(PointerMoveEvent(
          pointer: 901,
          position: start + Offset(-30.0 * step, -15.0 * step),
          delta: const Offset(-30, -15),
          kind: ui.PointerDeviceKind.mouse,
          buttons: kPrimaryMouseButton));
      await Future<void>.delayed(const Duration(milliseconds: 60));
    }
    GestureBinding.instance.handlePointerEvent(PointerUpEvent(
        pointer: 901,
        position: start + const Offset(-150, -75),
        kind: ui.PointerDeviceKind.mouse));
    await Future<void>.delayed(const Duration(milliseconds: 200));
    final afterDrag = rectFor(isMini);
    check(afterDrag.left < beforeDrag.left - 20, 'mini dragging');
    await windowManager.setSize(const Size(850, 620));
    await Future<void>.delayed(const Duration(milliseconds: 500));
    final resized = rectFor(isMini);
    final appSize =
        (boundaryKey.currentContext!.findRenderObject() as RenderBox).size;
    check(
        resized.left >= 0 &&
            resized.top >= 0 &&
            resized.right <= appSize.width + 1 &&
            resized.bottom <= appSize.height + 1,
        'mini bounds after resize');
    await Get.toNamed<void>(RoutePath.kSearch)
        ?.timeout(const Duration(milliseconds: 1), onTimeout: () {});
    await Future<void>.delayed(const Duration(milliseconds: 500));
    check(session.floating.value && room.player.state.playing,
        'search while playing');
    final search = Get.find<AppSearchController>();
    final douyuTabRect = rectFor((widget) {
      if (widget is! Tab || widget.child is! Row) return false;
      return (widget.child as Row)
          .children
          .whereType<Text>()
          .any((text) => text.data == '斗鱼直播');
    });
    await tap(douyuTabRect.center);
    await waitFor(() => search.tabController.index == 1,
        'search tab click while floating',
        seconds: 5);
    final pauseTooltip =
        findElement((widget) => widget is Tooltip && widget.message == '暂停');
    final tooltipState =
        (pauseTooltip as StatefulElement).state as TooltipState;
    tooltipState.ensureTooltipVisible();
    await Future<void>.delayed(const Duration(milliseconds: 300));
    check(flutterErrors.isEmpty, 'mini tooltip errors: $flutterErrors');
    final boundary =
        boundaryKey.currentContext!.findRenderObject() as RenderRepaintBoundary;
    final screenshot = await boundary.toImage(pixelRatio: 1);
    final png = await screenshot.toByteData(format: ui.ImageByteFormat.png);
    if (png != null) {
      await File('${output.parent.path}/mini-player.png')
          .writeAsBytes(png.buffer.asUint8List());
    }
    screenshot.dispose();
    await tapTooltip('暂停');
    await waitFor(() => !room.player.state.playing, 'pause from mini',
        seconds: 5);
    final miniRect = rectFor(isMini);
    await tap(miniRect.center + const Offset(0, 20));
    await waitFor(
        () =>
            Uri.parse(Get.currentRoute).path == RoutePath.kLiveRoomDetail &&
            !session.floating.value,
        'tap to return',
        seconds: 5);
    check(identical(session.active.value, room), 'return recreated controller');
    check(!room.player.state.playing, 'return lost paused state');
    check(playRequests == requestsBefore, 'leave/return fetched a new source');
    check(room.playUrls[room.currentLineIndex] == oldSource,
        'return replaced live URL');
    AppNavigator.toLiveRoomDetail(site: site, roomId: rooms.first);
    await Future<void>.delayed(const Duration(milliseconds: 500));
    check(
        identical(session.active.value, room) &&
            !room.player.state.playing &&
            playRequests == requestsBefore,
        'opening the current room recreated playback');
    Get.back<void>();
    await waitFor(() => session.floating.value && findElement(isMini) != null,
        'second mini',
        seconds: 5);
    await tapTooltip('继续播放');
    await waitFor(() => room.player.state.playing, 'resume from mini',
        seconds: 5);
    final beforeRecovery = playRequests;
    room.mediaError('verification: dropped connection in floating player');
    await waitFor(
        () =>
            playRequests > beforeRecovery &&
            !room.reconnecting.value &&
            room.player.state.playing,
        'mini recovery');
    check(session.floating.value, 'recovery closed the floating player');
    report['retainedPlayback'] = {
      'playing': room.player.state.playing,
      'sameControllerAndSourceOnReturn': true,
      'additionalRequestsOnReturn': 0,
      'dragged': true,
      'clampedAfterResize': true,
      'searchWhilePlaying': true,
      'searchTabReceivesPointer': true,
      'tooltipVisibleWithoutErrors': true,
      'pausePreservedOnReturn': true,
      'resumeFromMini': true,
      'freshRequestsDuringMiniRecovery': playRequests - beforeRecovery
    };
    await save();
    AppNavigator.toLiveRoomDetail(site: site, roomId: rooms[1]);
    await waitFor(
        () =>
            session.active.value != null &&
            !identical(session.active.value, room) &&
            session.active.value!.player.state.playing &&
            (session.active.value!.player.state.width ?? 0) > 0 &&
            room.isClosed,
        'replacement room');
    check(
        !room.player.state.playing, 'old room still playing after replacement');
    final replacement = session.active.value!;
    AppNavigator.toLiveRoomDetail(site: site, roomId: rooms.first);
    await waitFor(
        () =>
            session.active.value != null &&
            !identical(session.active.value, replacement) &&
            session.active.value!.player.state.playing &&
            (session.active.value!.player.state.width ?? 0) > 0 &&
            replacement.isClosed,
        'direct room replacement');
    check(!replacement.player.state.playing,
        'direct room replacement retained old sound');
    final finalRoom = session.active.value!;
    Get.back<void>();
    await waitFor(() => session.floating.value && findElement(isMini) != null,
        'replacement mini');
    await tapTooltip('关闭小窗并停止播放');
    await waitFor(
        () =>
            session.active.value == null &&
            findElement(isMini) == null &&
            finalRoom.isClosed,
        'close mini',
        seconds: 5);
    report['replacementAndClose'] = {
      'oldRoomStopped': true,
      'newRoomDecoded': true,
      'directRoomReplacement': true,
      'closedPlayerDisposed': true,
      'miniRemoved': true
    };
    report['flutterErrors'] = flutterErrors;
    check(flutterErrors.isEmpty, 'Flutter errors: $flutterErrors');
    report['passed'] = true;
  } catch (error, stack) {
    report['passed'] = false;
    report['error'] = error
        .toString()
        .replaceAll(RegExp(r'(https?://[^\s?]+)\?[^\s]+'), r'$1?[redacted]');
    report['stack'] = stack.toString();
    report['currentRoute'] = Get.currentRoute;
    if (Get.isRegistered<LiveRoomSessionService>()) {
      report['floatingAtFailure'] =
          LiveRoomSessionService.instance.floating.value;
    }
    report['flutterErrors'] = flutterErrors;
  } finally {
    core_http.HttpClient.instance.dio.interceptors.remove(counter);
    await save();
    exit(0);
  }
}
