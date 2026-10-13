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
import 'package:simple_live_app/modules/multi_live/multi_live_controller.dart';
import 'package:simple_live_app/modules/multi_live/multi_live_room.dart';
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
  final boundaryKey = GlobalKey();
  Future<void> screenshot(String name) async {
    await Future<void>.delayed(const Duration(milliseconds: 500));
    final boundary =
        boundaryKey.currentContext!.findRenderObject() as RenderRepaintBoundary;
    final image = await boundary.toImage(pixelRatio: 1);
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    if (data != null) {
      await File('${output.parent.path}/$name.png')
          .writeAsBytes(data.buffer.asUint8List());
    }
    image.dispose();
  }

  bool decoded(MultiLiveRoom room) =>
      room.player.state.playing &&
      (room.player.state.width ?? 0) > 0 &&
      !room.player.state.buffering &&
      !room.loading.value;
  try {
    await app.initServices();
    await windowManager.ensureInitialized();
    await windowManager.setSize(const Size(1280, 860));
    runApp(RepaintBoundary(key: boundaryKey, child: const app.MyApp()));
    await Future<void>.delayed(const Duration(seconds: 2));
    final site = Sites.allSites['douyu']!;
    final ids = <String>[];
    for (var page = 1; page <= 3 && ids.length < 15; page++) {
      final recommended = await site.liveSite.getRecommendRooms(page: page);
      for (final item in recommended.items.take(25)) {
        try {
          final detail = await site.liveSite.getRoomDetail(roomId: item.roomId);
          if (detail.status &&
              !detail.isRecord &&
              !ids.contains(detail.roomId)) {
            ids.add(detail.roomId);
          }
        } catch (_) {/* A recommendation may have just ended. */}
        if (ids.length >= 15) break;
      }
    }
    check(ids.length >= 9, 'Nine live rooms required');
    final session = LiveRoomSessionService.instance;
    if (args.length > 2) {
      final preferred = args[2].split(',');
      ids.removeWhere(preferred.contains);
      ids.insertAll(0, preferred);
    }
    var selected = false;
    for (final id in ids.toList().take(6)) {
      AppNavigator.toLiveRoomDetail(site: site, roomId: id);
      try {
        await waitFor(
            () =>
                session.active.value != null &&
                session.active.value!.player.state.playing &&
                (session.active.value!.player.state.width ?? 0) > 0,
            'single candidate',
            seconds: 35);
        ids.remove(id);
        ids.insert(0, id);
        selected = true;
        break;
      } catch (_) {
        final active = session.active.value;
        report['candidateFailure'] = {
          'id': id,
          'live': active?.liveStatus.value,
          'loadError': active?.loadError.value,
          'message': active?.errorMsg.value,
          'sourceCount': active?.playUrls.length
        };
        ids.remove(id);
        await save();
      }
    }
    check(selected, 'No candidate decoded');
    report.remove('candidateFailure');
    report['verifiedRoomIds'] = ids.take(3).toList();
    final old = session.active.value!;
    Get.back<void>();
    await waitFor(() => session.floating.value && findElement(isMini) != null,
        'mini player');
    AppNavigator.toMultiLive();
    await waitFor(
        () =>
            Get.isRegistered<MultiLiveController>() &&
            Get.find<MultiLiveController>().rooms.isNotEmpty &&
            session.active.value == null,
        'handoff');
    final c = Get.find<MultiLiveController>();
    final a = c.rooms.first;
    await waitFor(() => decoded(a) && old.isClosed, 'first grid video',
        seconds: 60);
    check(!session.floating.value && !old.player.state.playing,
        'single sound stopped');
    report['miniToGrid'] = true;
    await save();

    // Open the actual add dialog, enter a room ID and click its submit button.
    await tapTooltip('添加直播');
    final field = findElement((w) => w is TextField)!.widget as TextField;
    field.controller!.text = ids[1];
    await tap(rectFor((w) => w is Text && w.data == '添加到多画面').center);
    await waitFor(() => c.rooms.length == 2, 'dialog room add');
    final b = c.rooms[1];
    await waitFor(() => decoded(a) && decoded(b), 'two real streams',
        seconds: 60);
    await screenshot('multi-live-2');
    final third = c.add(site, ids[2])!;
    await waitFor(() => c.rooms.every(decoded), 'three real streams',
        seconds: 60);
    await screenshot('multi-live-3');
    await c.selectAudio(b);
    await waitFor(
        () =>
            c.rooms.where((r) => r.player.state.volume > 0).length == 1 &&
            b.player.state.volume > 0,
        'unique sound',
        seconds: 5);
    await Future.wait(
        [c.selectAudio(a), c.selectAudio(third), c.selectAudio(b)]);
    await waitFor(
        () =>
            c.rooms.where((r) => r.player.state.volume > 0).length == 1 &&
            b.player.state.volume > 0,
        'rapid sound switch',
        seconds: 5);
    await b.togglePause();
    final position = a.player.state.position;
    await Future<void>.delayed(const Duration(seconds: 2));
    check(!b.player.state.playing && a.player.state.position > position,
        'pause isolation');
    await b.togglePause();
    await waitFor(() => decoded(b), 'resume grid');
    final videoState = a.globalPlayerKey.currentState;
    c.toggleFocus(a);
    await screenshot('multi-live-focused');
    check(identical(a.globalPlayerKey.currentState, videoState),
        'focus retains Video state');
    c.toggleFocus(a);
    c.setLayout(4);
    await screenshot('multi-live-4');
    check(identical(a.globalPlayerKey.currentState, videoState),
        'layout retains Video state');
    final beforeRefresh = playRequests;
    final unaffectedBefore = a.player.state.position;
    await b.refresh();
    check(
        playRequests > beforeRefresh &&
            a.player.state.position > unaffectedBefore,
        'refresh isolation');
    final beforeRecovery = playRequests;
    await b.player.stop();
    b.recover();
    await waitFor(
        () =>
            playRequests > beforeRecovery &&
            decoded(b) &&
            !b.reconnecting.value,
        'independent recovery',
        seconds: 90);
    check(decoded(a) && decoded(third), 'recovery did not stop others');
    report['controls'] = {
      'addDialog': true,
      'layouts2And3And4': true,
      'singleAudio': true,
      'rapidAudioSwitch': true,
      'pauseIsolation': true,
      'refreshIsolation': true,
      'focusRetainsVideo': true,
      'layoutRetainsVideo': true,
      'independentRecovery': true,
    };
    await save();

    for (final id in ids.skip(3)) {
      if (c.rooms.length == 9) break;
      final next = c.add(site, id)!;
      try {
        await waitFor(() => decoded(next), 'additional stream', seconds: 50);
      } catch (_) {
        await c.remove(next);
      }
    }
    check(c.rooms.length == 9 && c.rooms.every(decoded),
        'nine simultaneous real streams');
    await screenshot('multi-live-9');
    await windowManager.setSize(const Size(360, 640));
    await screenshot('multi-live-9-small');
    await windowManager.setSize(const Size(1280, 860));
    final starts = c.rooms.map((r) => r.player.state.position).toList();
    await Future<void>.delayed(const Duration(seconds: 15));
    check(
        List.generate(9, (i) => c.rooms[i].player.state.position > starts[i])
            .every((e) => e),
        'nine streams progress');
    report['nineStreams'] = {
      'count': 9,
      'allDecoded': true,
      'allAdvancedFor15Seconds': true,
      'resize': true
    };
    await save();
    final retired = c.rooms.skip(3).toList();
    for (final r in retired) {
      await c.remove(r);
    }
    c.setLayout(3);
    check(retired.every((r) => r.isDisposed && !r.player.state.playing),
        'removed players disposed');

    // Cover the user's approximately ten-minute failure interval on three streams.
    final seconds = args.length > 1 ? int.parse(args[1]) : 660;
    final start = DateTime.now();
    var samples = 0;
    while (DateTime.now().difference(start).inSeconds < seconds) {
      await Future<void>.delayed(const Duration(seconds: 10));
      check(c.rooms.every((r) => !r.offline.value && r.error.value.isEmpty),
          'soak room error');
      samples++;
      report['soak'] = {
        'seconds': DateTime.now().difference(start).inSeconds,
        'rooms': c.rooms.length,
        'samples': samples,
        'playing': c.rooms.where(decoded).length
      };
      await save();
    }
    await waitFor(() => c.rooms.every(decoded), 'soak final playback');
    await screenshot('multi-live-final');
    final finalRooms = c.rooms.toList();
    Get.back<void>();
    await waitFor(() => finalRooms.every((r) => r.isDisposed), 'grid disposal');
    check(finalRooms.every((r) => !r.player.state.playing),
        'no sound after exit');
    check(session.active.value == null && !session.floating.value,
        'no leaked mini');

    // The direct room -> grid replacement and a rapid return are separate routes.
    AppNavigator.toLiveRoomDetail(site: site, roomId: ids.first);
    await waitFor(
        () =>
            session.active.value != null &&
            session.active.value!.player.state.playing,
        'second single room');
    final direct = session.active.value!;
    AppNavigator.toMultiLive();
    await waitFor(
        () =>
            Get.isRegistered<MultiLiveController>() &&
            Get.find<MultiLiveController>().rooms.isNotEmpty &&
            direct.isClosed,
        'direct room to grid');
    final directRooms = Get.find<MultiLiveController>().rooms.toList();
    Get.back<void>();
    await waitFor(
        () => directRooms.every((r) => r.isDisposed), 'exit during load');
    check(Uri.parse(Get.currentRoute).path != RoutePath.kLiveRoomDetail,
        'dead single route retained');
    check(flutterErrors.isEmpty, 'Flutter errors: $flutterErrors');
    report['lifecycle'] = {
      'removedPlayersDisposed': true,
      'exitStopsAll': true,
      'directRoomReplacement': true,
      'exitDuringLoad': true
    };
    report['flutterErrors'] = flutterErrors;
    report['passed'] = true;
  } catch (error, stack) {
    report['passed'] = false;
    report['error'] = error
        .toString()
        .replaceAll(RegExp(r'(https?://[^\s?]+)\?[^\s]+'), r'$1?[redacted]');
    report['stack'] = stack.toString();
    report['flutterErrors'] = flutterErrors;
    final active = LiveRoomSessionService.instance.active.value;
    if (active != null) {
      report['singleState'] = {
        'room': active.roomId,
        'live': active.liveStatus.value,
        'loadError': active.loadError.value,
        'playing': active.player.state.playing,
        'buffering': active.player.state.buffering
      };
    }
    if (Get.isRegistered<MultiLiveController>()) {
      report['roomStates'] = Get.find<MultiLiveController>()
          .rooms
          .map((r) => {
                'id': r.roomId,
                'playing': r.player.state.playing,
                'volume': r.player.state.volume,
                'buffering': r.player.state.buffering,
                'position': r.player.state.position.inSeconds,
                'loading': r.loading.value,
                'error': r.error.value,
                'offline': r.offline.value,
              })
          .toList();
    }
  } finally {
    core_http.HttpClient.instance.dio.interceptors.remove(counter);
    await save();
    exit(0);
  }
}
