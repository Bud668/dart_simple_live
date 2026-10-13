import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:simple_live_app/app/sites.dart';
import 'package:simple_live_app/modules/multi_live/multi_live_controller.dart';
import 'package:simple_live_app/modules/multi_live/multi_live_page.dart';
import 'package:simple_live_app/modules/multi_live/multi_live_room.dart';
import 'package:simple_live_app/services/live_room_link_parser.dart';
import 'package:simple_live_core/simple_live_core.dart';

class FakeGridRoom extends MultiLiveRoom {
  FakeGridRoom(super.site, super.requestedId);
  double volume = 0;
  int starts = 0, stops = 0, disposals = 0;
  Completer<void>? volumeGate;
  @override
  void start() {
    starts++;
  }

  @override
  Future<void> setAudioVolume(double value) async {
    if (volumeGate != null) await volumeGate!.future;
    if (stops == 0) volume = value;
  }

  @override
  Future<void> stop() async {
    stops++;
    volume = 0;
  }

  @override
  Future<void> dispose() async {
    disposals++;
  }

  @override
  bool get isClosed => stops > 0;
}

void main() {
  final site = Site(id: 'douyu', name: '斗鱼', logo: '', liveSite: DouyuSite());
  MultiLiveController grid({Future<void> Function()? frame}) =>
      MultiLiveController(
          createRoom: FakeGridRoom.new, afterFrame: frame ?? () async {});

  test('grows through 2/3/4/9; never hides active streams or exceeds capacity',
      () async {
    final c = grid();
    for (var i = 1; i <= 9; i++) {
      expect(c.add(site, '$i'), isNotNull);
      expect(
          c.layout.value,
          i <= 2
              ? 2
              : i <= 4
                  ? i
                  : 9);
    }
    expect(c.add(site, '10'), isNull);
    expect(c.setLayout(4), isFalse);
    expect(c.add(site, '1'), same(c.rooms.first));
    expect((c.rooms.first as FakeGridRoom).starts, 1);
    await c.clear();
    expect(c.setLayout(3), isTrue);
    await c.shutdown();
    expect(c.add(site, 'new'), isNull);
  });

  test('sound switching is serialized; muted grids keep added rooms silent',
      () async {
    final c = grid();
    final a = c.add(site, 'a')! as FakeGridRoom;
    final b = c.add(site, 'b')! as FakeGridRoom;
    await c.selectAudio(a);
    expect([a.volume, b.volume], [70, 0]);
    final gate = Completer<void>();
    a.volumeGate = gate;
    final first = c.selectAudio(b);
    await Future<void>.delayed(Duration.zero);
    final second = c.selectAudio(a);
    gate.complete();
    await Future.wait([first, second]);
    expect([a.volume, b.volume], [70, 0]);
    await c.selectAudio(null);
    final added = c.add(site, 'c')! as FakeGridRoom;
    await Future<void>.delayed(Duration.zero);
    expect([a.volume, b.volume, added.volume], [0, 0, 0]);
    expect(c.audioRoom.value, isNull);
    await c.shutdown();
  });

  test('removing audible focused room stops now and disposes after frame',
      () async {
    final frame = Completer<void>();
    final c = grid(frame: () => frame.future);
    final a = c.add(site, 'a')! as FakeGridRoom;
    final b = c.add(site, 'b')! as FakeGridRoom;
    await c.selectAudio(a);
    c.toggleFocus(a);
    final removing = c.remove(a);
    expect(a.stops, 1);
    expect(a.disposals, 0);
    expect(c.focusedRoom.value, isNull);
    expect(c.audioRoom.value, same(b));
    final closing = c.shutdown();
    expect(b.stops, 1);
    frame.complete();
    await Future.wait([removing, closing]);
    expect([a.disposals, b.disposals], [1, 1]);
    expect([a.volume, b.volume], [0, 0]);
  });

  test('focus and layout changes preserve players and selected sound',
      () async {
    final c = grid();
    final a = c.add(site, 'a')!;
    final b = c.add(site, 'b')!;
    await c.selectAudio(b);
    c.toggleFocus(a);
    expect(c.focusedRoom.value, same(a));
    c.setLayout(9);
    expect(c.focusedRoom.value, isNull);
    expect(c.audioRoom.value, same(b));
    expect(c.rooms, [a, b]);
    await c.shutdown();
  });

  test('all supported layouts cover the viewport without overlap', () {
    for (final count in MultiLiveController.layouts) {
      for (final size in [const Size(1200, 650), const Size(360, 650)]) {
        final rects = multiLiveRects(count, size);
        expect(rects.length, count);
        var area = 0.0;
        for (var i = 0; i < rects.length; i++) {
          final rect = rects[i];
          expect(rect.left >= 0 && rect.top >= 0, isTrue);
          expect(
              rect.right <= size.width + .001 &&
                  rect.bottom <= size.height + .001,
              isTrue);
          area += rect.width * rect.height;
          for (var j = 0; j < i; j++) {
            expect(rect.overlaps(rects[j]), isFalse);
          }
        }
        expect(area, closeTo(size.width * size.height, .001));
      }
    }
  });

  test('parses share text, direct rooms, topics and explicit platform IDs',
      () async {
    final parser = LiveRoomLinkParser();
    for (final pair in {
      'https://live.douyin.com/317637694923': 'douyin:317637694923',
      '【分享】 https://www.douyu.com/123 来看看': 'douyu:123',
      'https://www.douyu.com/topic/game?rid=456': 'douyu:456',
      'https://m.douyu.com/123': 'douyu:123',
      'https://m.huya.com/abc': 'huya:abc',
      'https://www.huya.com/abc_1': 'huya:abc_1',
      'https://live.bilibili.com/789?from=share': 'bilibili:789',
      'https://webcast.amemv.com/douyin/webcast/reflow/12345': 'douyin:12345',
    }.entries) {
      final parsed = await parser.parse(pair.key);
      expect('${parsed?.siteId}:${parsed?.roomId}', pair.value);
    }
    expect((await parser.parse('123', defaultSiteId: 'douyu'))?.roomId, '123');
    expect(await parser.parse('123'), isNull);
    expect(await parser.parse('https://evil.test/huya.com/123'), isNull);
    expect(await parser.parse('https://live.douyin.com.evil.test/123'), isNull);
    expect(await parser.parse(''), isNull);
  });

  test('short links follow bounded redirects and fail without throwing',
      () async {
    final parser = LiveRoomLinkParser(
        redirect: (uri) async => uri.path == '/first'
            ? Uri.parse('https://v.douyin.com/second')
            : Uri.parse('https://live.douyin.com/123'));
    expect(
        (await parser.parse('正在直播 https://v.douyin.com/first'))?.roomId, '123');
    final loop = LiveRoomLinkParser(redirect: (uri) async => uri);
    expect(await loop.parse('https://b23.tv/loop'), isNull);
    final failure =
        LiveRoomLinkParser(redirect: (_) async => throw StateError('network'));
    expect(await failure.parse('https://b23.tv/fail'), isNull);
    var requests = 0;
    final endless = LiveRoomLinkParser(
        redirect: (_) async => Uri.parse('https://b23.tv/${++requests}'));
    expect(await endless.parse('https://b23.tv/start'), isNull);
    expect(requests, 5);
  });
}
