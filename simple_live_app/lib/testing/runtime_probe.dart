import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:window_manager/window_manager.dart';
import 'package:simple_live_core/simple_live_core.dart';
import 'package:hive/hive.dart';
import 'package:get/get.dart';
import 'package:simple_live_app/main.dart' as repair;
import 'package:simple_live_app/services/sync_service.dart';
import 'package:simple_live_app/app/sites.dart';
import 'package:simple_live_app/modules/live_room/live_room_controller.dart';
// Test instrumentation needs access to the shared HTTP client.
// ignore: implementation_imports
import 'package:simple_live_core/src/common/http_client.dart' as core_http;
import 'package:dio/dio.dart';

class QuietSyncService extends SyncService {
  @override
  // Calling SyncService.onInit would start LAN discovery in this isolated probe.
  // ignore: must_call_super
  void onInit() {} // Do not bind or broadcast on the user's LAN during tests.
}

/// A separate entry point for checking the portable Windows runtime, without
/// opening the user's databases or changing the running application.
Future<void> main(List<String> args) async {
  WidgetsFlutterBinding.ensureInitialized();
  MediaKit.ensureInitialized();
  final report = <String, Object?>{};
  final output = File(args.first);
  String? verifiedRoomId;
  Future<LiveRoomDetail> chooseLiveRoom(DouyuSite site) async {
    var room = await site.getRoomDetail(roomId: '6561377');
    if (!room.status) {
      final recommendations = await site.getRecommendRooms();
      for (final item in recommendations.items.take(3)) {
        room = await site.getRoomDetail(roomId: item.roomId);
        if (room.status) break;
      }
    }
    if (!room.status) {
      throw StateError('No live room available for playback check');
    }
    verifiedRoomId = room.roomId;
    return room;
  }

  Future<void> record(String name, Future<Object?> Function() action,
      {Duration timeout = const Duration(seconds: 40)}) async {
    try {
      report[name] = await action().timeout(timeout);
    } catch (error) {
      report[name] = {
        'error': error
            .toString()
            .replaceAll(RegExp(r'(https?://[^\s?]+)\?[^\s]+'), r'$1?[redacted]')
      };
    }
    await output
        .writeAsString(const JsonEncoder.withIndent('  ').convert(report));
  }

  await record(
      'packageInfo', () async => (await PackageInfo.fromPlatform()).version);
  await record('windowManager', () async {
    await windowManager.ensureInitialized();
    return (await windowManager.getBounds()).toString();
  });
  await record('webViewVersion',
      () async => await WebViewEnvironment.getAvailableVersion());
  if (!args.contains('--soak')) await record('douyuPlayback', () async {
    MediaKit.ensureInitialized();
    final site = DouyuSite();
    final room = await chooseLiveRoom(site);
    if (!room.status) return {'offline': true};
    final qualities = await site.getPlayQualites(detail: room);
    final urls = await site.getPlayUrls(detail: room, quality: qualities.last);
    final player = Player(
        configuration: const PlayerConfiguration(logLevel: MPVLogLevel.error));
    final video = VideoController(player);
    runApp(Directionality(
        textDirection: TextDirection.ltr,
        child: Video(controller: video, controls: null)));
    final errors = <String>[];
    final errorEvents = player.stream.error.listen((message) {
      errors.add(message.replaceAll(
          RegExp(r'(https?://[^\s?]+)\?[^\s]+'), r'$1?[redacted]'));
    });
    try {
      await (player.platform as NativePlayer)
          .setProperty('cache-on-disk', 'no');
      await (player.platform as NativePlayer)
          .setProperty('network-timeout', '15');
      final ready =
          player.stream.width.firstWhere((value) => value != null && value > 0);
      await player.open(Media(urls.urls.first, httpHeaders: urls.headers));
      final width =
          await ready.timeout(const Duration(seconds: 25), onTimeout: () {
        throw StateError(
            'No decoded video; errors=$errors; playing=${player.state.playing}');
      });
      return {'decodedVideoWidth': width, 'playing': player.state.playing};
    } finally {
      await errorEvents.cancel();
      // Unmount Video before freeing its native texture and player.
      runApp(const SizedBox.shrink());
      await WidgetsBinding.instance.endOfFrame;
      await player.dispose();
    }
  });
  if (!args.contains('--soak')) await record('douyinWebSearch', () async {
    final loaded = Completer<Map<String, Object?>>();
    final webView = HeadlessInAppWebView(
      initialSize: const Size(1280, 720),
      initialUrlRequest: URLRequest(
          url: WebUri(
              'https://www.douyin.com/search/%E6%B8%B8%E6%88%8F?type=user')),
      initialSettings: InAppWebViewSettings(),
      onLoadStop: (controller, uri) async {
        if (loaded.isCompleted) return;
        await Future<void>.delayed(const Duration(seconds: 15));
        final body = await controller.evaluateJavascript(
            source: 'document.body.innerText.slice(0, 2000)');
        final screenshot = await controller.takeScreenshot();
        if (screenshot != null) {
          await File('${output.parent.path}/douyin-search-probe.png')
              .writeAsBytes(screenshot);
        }
        if (!loaded.isCompleted) {
          loaded.complete({
            'title': await controller.getTitle(),
            'visibleText': body,
            'readyState': await controller.evaluateJavascript(
                source: 'document.readyState'),
            'searchInputs': await controller.evaluateJavascript(
                source:
                    'Array.from(document.querySelectorAll("input")).map(e=>({value:e.value,placeholder:e.placeholder}))'),
          });
        }
      },
      onReceivedError: (_, request, error) {
        if (request.isForMainFrame == true && !loaded.isCompleted) {
          loaded.complete({'error': error.description});
        }
      },
    );
    try {
      await webView.run();
      return await loaded.future.timeout(const Duration(seconds: 30));
    } finally {
      await webView.dispose();
    }
  });
  await record('applicationStartup', () async {
    final profile = Directory('${output.parent.path}/isolated-probe-profile');
    await profile.create(recursive: true);
    Hive.init(profile.path);
    Get.put<SyncService>(QuietSyncService());
    await repair.initServices();
    runApp(const repair.MyApp());
    await Future<void>.delayed(const Duration(seconds: 2));
    return {'initialized': true, 'isolatedProfile': true};
  });
  await record('controllerRecovery', () async {
    var playRequests = 0;
    final requestCounter = InterceptorsWrapper(onRequest: (options, handler) {
      if (options.uri.path.contains('/getH5Play/')) playRequests++;
      handler.next(options);
    });
    core_http.HttpClient.instance.dio.interceptors.add(requestCounter);
    final controller = Get.put(LiveRoomController(
      pSite: Sites.allSites['douyu']!,
      pRoomId: verifiedRoomId ?? (await chooseLiveRoom(DouyuSite())).roomId,
    ));
    try {
      unawaited(Get.to<void>(() => Scaffold(
                body: Video(
                    controller: controller.videoController, controls: null),
              )) ??
          Future<void>.value());
      final deadline = DateTime.now().add(const Duration(seconds: 25));
      while ((controller.playUrls.isEmpty ||
              !controller.player.state.playing ||
              (controller.player.state.width ?? 0) <= 0) &&
          DateTime.now().isBefore(deadline)) {
        await Future<void>.delayed(const Duration(milliseconds: 100));
      }
      if (controller.playUrls.isEmpty) {
        throw StateError('initial live URLs unavailable');
      }
      if (controller.isClosed) throw StateError('test controller was disposed');
      await Future<void>.delayed(const Duration(seconds: 3));
      final originalUrl = controller.playUrls.first;
      final originalLine = controller.currentLineIndex;
      final initialRequests = playRequests;
      controller.mediaError('verification: simulated dropped connection');
      final recoveryDeadline = DateTime.now().add(const Duration(seconds: 25));
      while ((playRequests <= initialRequests ||
              controller.reconnecting.value ||
              !controller.player.state.playing) &&
          DateTime.now().isBefore(recoveryDeadline)) {
        await Future<void>.delayed(const Duration(milliseconds: 100));
      }
      if (playRequests <= initialRequests ||
          controller.reconnecting.value ||
          !controller.player.state.playing ||
          !controller.liveStatus.value) {
        throw StateError('fresh source did not restore live playback');
      }
      final result = <String, Object?>{
        'newSignedAddress': controller.playUrls.first != originalUrl,
        'freshPlayApiRequests': playRequests - initialRequests,
        'lineChanged': controller.currentLineIndex != originalLine,
        'playing': controller.player.state.playing,
        'positionMilliseconds': controller.player.state.position.inMilliseconds,
        'stillLive': controller.liveStatus.value,
        'reportedOffline': !controller.liveStatus.value,
      };
      if (args.contains('--soak')) {
        final clock = Stopwatch()..start();
        var progressSamples = 0;
        var previousPosition = controller.player.state.position;
        var injectedRecoveries = 1;
        var nextInjection = 180;
        var longestNoProgress = 0;
        var lastProgress = 0;
        while (clock.elapsed.inSeconds < 720) {
          await Future<void>.delayed(const Duration(seconds: 2));
          final seconds = clock.elapsed.inSeconds;
          if (controller.player.state.position != previousPosition) {
            progressSamples++;
            previousPosition = controller.player.state.position;
            lastProgress = seconds;
          }
          if (seconds - lastProgress > longestNoProgress) {
            longestNoProgress = seconds - lastProgress;
          }
          if (seconds >= nextInjection && nextInjection <= 540) {
            controller.mediaError('verification: repeated dropped connection');
            injectedRecoveries++;
            nextInjection += 180;
          }
          if (seconds % 20 < 2) {
            report['soakProgress'] = {
              'elapsedSeconds': seconds,
              'progressSamples': progressSamples,
              'playing': controller.player.state.playing,
              'reconnecting': controller.reconnecting.value,
              'stillLive': controller.liveStatus.value,
              'freshPlayApiRequests': playRequests - initialRequests
            };
            await output.writeAsString(
                const JsonEncoder.withIndent('  ').convert(report));
          }
          if (!controller.liveStatus.value ||
              controller.errorMsg.value.isNotEmpty) {
            throw StateError(
                'soak interrupted: live=${controller.liveStatus.value}; '
                'message=${controller.errorMsg.value}');
          }
        }
        result['soak'] = {
          'elapsedSeconds': clock.elapsed.inSeconds,
          'progressSamples': progressSamples,
          'injectedRecoveries': injectedRecoveries,
          'freshPlayApiRequests': playRequests - initialRequests,
          'longestNoProgressSeconds': longestNoProgress,
          'playing': controller.player.state.playing,
          'stillLive': controller.liveStatus.value
        };
      }
      return result;
    } finally {
      core_http.HttpClient.instance.dio.interceptors.remove(requestCounter);
      await Get.delete<LiveRoomController>(force: true);
    }
  },
      timeout: args.contains('--soak')
          ? const Duration(minutes: 16)
          : const Duration(seconds: 80));
  await output
      .writeAsString(const JsonEncoder.withIndent('  ').convert(report));
  exit(0);
}
