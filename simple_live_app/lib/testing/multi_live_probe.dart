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
import 'package:simple_live_app/app/controller/app_settings_controller.dart';
import 'package:simple_live_app/routes/app_navigation.dart';
import 'package:simple_live_app/services/live_room_session_service.dart';
import 'package:simple_live_app/services/sync_service.dart';
import 'package:simple_live_app/modules/multi_live/multi_live_controller.dart';
import 'package:simple_live_app/modules/multi_live/multi_live_room.dart';
// Private client access is used only for counting playback requests in this probe.
// ignore: implementation_imports
import 'package:simple_live_core/src/common/http_client.dart' as core_http;
import 'package:window_manager/window_manager.dart';
import 'package:flutter/services.dart';
import 'package:simple_live_app/modules/multi_live/multi_live_danmaku.dart';
import 'package:simple_live_app/services/follow_service.dart';
import 'package:simple_live_app/models/db/follow_user.dart';

class QuietMiniSyncService extends SyncService {
  @override
  // The probe deliberately avoids LAN discovery.
  // ignore: must_call_super
  void onInit() {}
}

class ProbeFollowService extends FollowService {
  @override
  // ignore: must_call_super
  void onInit() {}
  @override
  void startUpdateStatus() {
    updating.value = false;
  }
}

Future<void> main(List<String> args) async {
  WidgetsFlutterBinding.ensureInitialized();
  MediaKit.ensureInitialized();
  final output = File(args.first);
  final report = <String, Object?>{};
  final flutterErrors = <String>[];
  FlutterError.onError = (details) {
    flutterErrors.add('${details.exceptionAsString()}\n${details.stack}');
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
    AppSettingsController.instance.firstRun = false;
    AppSettingsController.instance.setNoFirstRun();
    AppSettingsController.instance.autoUpdateFollowEnable.value = false;
    await Get.delete<FollowService>(force: true);
    final follows = Get.put<FollowService>(ProbeFollowService());
    await windowManager.ensureInitialized();
    await windowManager
        .waitUntilReadyToShow(const WindowOptions(minimumSize: Size(280, 280)));
    await windowManager.setFullScreen(false);
    await windowManager.restore();
    await windowManager.setTitle('Simple Live V5 validation');
    await windowManager.setSize(const Size(1280, 860));
    runApp(RepaintBoundary(key: boundaryKey, child: const app.MyApp()));
    await windowManager.show();
    await Future<void>.delayed(const Duration(seconds: 2));
    AppNavigator.toMultiLive();
    await waitFor(() => Get.isRegistered<MultiLiveController>(), 'grid route');
    final c = Get.find<MultiLiveController>();
    final site = Sites.allSites['douyu']!;
    final ids =
        (args.length > 1 ? args[1] : '24422,5720533,6496945').split(',');
    final a = c.add(site, ids[0])!;
    await waitFor(() => decoded(a), 'first stream', seconds: 65);
    await waitFor(() => a.player.state.volume == 0, 'first stream muted');
    await screenshot('one-auto');
    final videoState = a.globalPlayerKey.currentState;
    for (var i = 0; i < 3; i++) {
      follows.followList.add(FollowUser(
          id: 'fixture-$i',
          roomId: ids[i],
          siteId: 'douyu',
          userName: ['直播中示例', '未开播示例', '状态未知示例'][i],
          face: '',
          addTime: DateTime.now())
        ..liveStatus.value = [2, 1, 0][i]);
    }
    await tapTooltip('添加直播');
    check(
        findElement((w) => w is Text && w.data == '直播中') != null, 'live badge');
    check(findElement((w) => w is Text && w.data == '未开播') != null,
        'offline badge');
    check(findElement((w) => w is Text && w.data == '状态未知') != null,
        'unknown badge');
    await screenshot('follow-status');
    final field = findElement((w) => w is TextField)!.widget as TextField;
    field.controller!.text = ids[1];
    await tap(rectFor((w) => w is Text && w.data == '添加到多画面').center);
    await waitFor(
        () => c.rooms.length == 2 && c.rooms.every(decoded), 'second stream',
        seconds: 65);
    final b = c.rooms[1];
    final third = c.add(site, ids[2])!;
    await waitFor(() => c.rooms.every(decoded), 'three streams', seconds: 65);
    await waitFor(() => c.rooms.every((r) => r.player.state.volume == 0),
        'all additions silent');
    check(identical(a.globalPlayerKey.currentState, videoState),
        'addition retains video');
    check(
        findElement((w) => w is ChoiceChip) == null, 'no fixed layout buttons');
    await screenshot('three-auto');
    await c.setAudioEnabled(a, true);
    await c.setAudioEnabled(b, true);
    await waitFor(
        () =>
            a.player.state.volume > 0 &&
            b.player.state.volume > 0 &&
            third.player.state.volume == 0,
        'two independently audible streams');
    await Future.wait([
      c.setAudioEnabled(a, false),
      c.setAudioEnabled(b, false),
      c.setAudioEnabled(b, true)
    ]);
    await waitFor(() => a.player.state.volume == 0 && b.player.state.volume > 0,
        'rapid audio choices');
    await tapTooltip('全部静音');
    await waitFor(
        () => c.rooms.every((r) => r.player.state.volume == 0), 'mute all');
    report['audio'] = {
      'defaultMuted': true,
      'simultaneousAudio': true,
      'independentToggle': true,
      'muteAll': true
    };
    await save();

    a.danmakuEnabled.value = true;
    await waitFor(() => findElement((w) => w is MultiLiveDanmaku) != null,
        'danmaku mounted');
    await Future<void>.delayed(const Duration(seconds: 8));
    await screenshot('top-danmaku');
    final overlay = rectFor((w) => w is MultiLiveDanmaku);
    check(overlay.height <= 30.1, 'bounded chat height');
    final beforeResize = a.player.state.position;
    await windowManager.setSize(const Size(360, 640));
    await Future<void>.delayed(const Duration(seconds: 2));
    final nativeSize = await windowManager.getSize();
    final view = ui.PlatformDispatcher.instance.implicitView!;
    report['portraitMetrics'] = {
      'nativeWidth': nativeSize.width,
      'nativeHeight': nativeSize.height,
      'viewWidth': view.physicalSize.width / view.devicePixelRatio,
      'viewHeight': view.physicalSize.height / view.devicePixelRatio,
      'minimized': await windowManager.isMinimized(),
      'maximized': await windowManager.isMaximized(),
    };
    await save();
    await waitFor(
        () =>
            (boundaryKey.currentContext!.findRenderObject() as RenderBox)
                .size
                .width <
            600,
        'native resize reached Flutter',
        seconds: 10);
    check(findElement((w) => w is MultiLiveDanmaku) == null,
        'small tiles hide chat');
    await screenshot('portrait-auto');
    await windowManager.setSize(const Size(1280, 860));
    await waitFor(() => findElement((w) => w is MultiLiveDanmaku) != null,
        'chat returns on larger tile');
    report['resizePlayback'] = {
      'retainsVideoState':
          identical(a.globalPlayerKey.currentState, videoState),
      'beforeMs': beforeResize.inMilliseconds,
      'afterMs': a.player.state.position.inMilliseconds,
    };
    await save();
    check(identical(a.globalPlayerKey.currentState, videoState),
        'resize retains video state');
    final resizedPosition = a.player.state.position;
    await waitFor(() => decoded(a) && a.player.state.position > resizedPosition,
        'playback advances after resize',
        seconds: 30);
    a.danmakuEnabled.value = false;
    await waitFor(
        () => findElement((w) => w is MultiLiveDanmaku) == null, 'chat off');
    report['danmaku'] = {
      'boundedTopArea': true,
      'smallTilesHidden': true,
      'toggle': true
    };

    await tapTooltip('多画面全屏（F11）');
    await Future<void>.delayed(const Duration(seconds: 4));
    check(await windowManager.isFullScreen(), 'native full screen');
    check(findElement((w) => w is AppBar) == null, 'fullscreen appbar hidden');
    check(
        findElement((w) => w is Tooltip && w.message == '退出多画面全屏（Esc）') == null,
        'idle toolbar hidden');
    await screenshot('fullscreen-clean');
    // Invoke the registered keyboard shortcut; it must restore the window.
    final shortcuts =
        findElement((w) => w is CallbackShortcuts)!.widget as CallbackShortcuts;
    shortcuts.bindings[const SingleActivator(LogicalKeyboardKey.escape)]!();
    await Future<void>.delayed(const Duration(seconds: 1));
    check(!await windowManager.isFullScreen(), 'escape exits fullscreen');
    check(identical(a.globalPlayerKey.currentState, videoState),
        'fullscreen retains video');
    // Native exits also occur through the app's global mouse-back handler.
    await tapTooltip('多画面全屏（F11）');
    await Future<void>.delayed(const Duration(seconds: 1));
    await windowManager.setFullScreen(false);
    await waitFor(() => findElement((w) => w is AppBar) != null,
        'external exit restores toolbar');
    report['fullscreen'] = {
      'externalExitRestoresToolbar': true,
      'entered': true,
      'idleToolbarHidden': true,
      'escapeExits': true,
      'retainsVideo': true
    };
    await save();

    final spareIds = <String>[];
    final recommended = await site.liveSite.getRecommendRooms(page: 1);
    for (final item in recommended.items) {
      if (ids.contains(item.roomId) || spareIds.contains(item.roomId)) continue;
      final candidate = c.add(site, item.roomId);
      if (candidate == null) break;
      try {
        await waitFor(() => decoded(candidate), 'extra stream', seconds: 35);
        spareIds.add(item.roomId);
      } catch (_) {
        await c.remove(candidate);
      }
      if (spareIds.length == 2) break;
    }
    check(c.rooms.length == 5, 'five adaptive cells');
    await screenshot('five-auto');
    check(identical(a.globalPlayerKey.currentState, videoState),
        'five cells retain first video');
    for (final extra in c.rooms.skip(3).toList()) {
      await c.remove(extra);
    }
    await Future<void>.delayed(const Duration(seconds: 1));
    check(
        c.rooms.length == 3 &&
            identical(a.globalPlayerKey.currentState, videoState),
        'removal rearranges without restart');
    c.toggleFocus(a);
    await screenshot('focused');
    c.toggleFocus(a);
    report['layout'] = {
      'counts1To5': true,
      'noFixedButtons': true,
      'resize': true,
      'additionAndRemovalRetainVideo': true,
      'focus': true
    };
    await b.refresh();
    await waitFor(() => c.rooms.every(decoded), 'refresh playback');
    check(c.rooms.every((r) => r.player.state.volume == 0),
        'refresh retains mute');
    final positions = c.rooms.map((r) => r.player.state.position).toList();
    await Future<void>.delayed(const Duration(seconds: 20));
    check(
        List.generate(3, (i) => c.rooms[i].player.state.position > positions[i])
            .every((v) => v),
        'three streams continued');
    final finalRooms = c.rooms.toList();
    Get.back<void>();
    await waitFor(
        () => finalRooms.every((r) => r.isDisposed), 'all players disposed');
    check(finalRooms.every((r) => !r.player.state.playing),
        'all players stopped');
    check(flutterErrors.isEmpty, 'Flutter errors: $flutterErrors');
    report['lifecycle'] = {'playersStoppedAndDisposed': true};
    report['flutterErrors'] = flutterErrors;
    report['passed'] = true;
    await screenshot('returned-home');
  } catch (error, stack) {
    report['passed'] = false;
    report['error'] =
        error.toString().replaceAll(RegExp(r'https?://\S+'), '<url-redacted>');
    report['stack'] = stack.toString();
    report['flutterErrors'] = flutterErrors;
    await screenshot('failure');
  } finally {
    core_http.HttpClient.instance.dio.interceptors.remove(counter);
    if (Get.isRegistered<MultiLiveController>()) {
      await Get.find<MultiLiveController>().shutdown();
    }
    await LiveRoomSessionService.instance.stop();
    report['playRequests'] = playRequests;
    report['nativeExit'] = 'pending external process verification';
    await save();
    await windowManager.setFullScreen(false);
    await windowManager.setPreventClose(false);
    await windowManager.close();
  }
}
