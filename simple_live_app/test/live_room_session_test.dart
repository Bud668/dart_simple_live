import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:simple_live_app/app/sites.dart';
import 'package:simple_live_app/modules/live_room/live_room_controller.dart';
import 'package:simple_live_app/services/live_room_session_service.dart';
import 'package:simple_live_core/simple_live_core.dart';

class FixtureRoom extends LiveRoomController {
  FixtureRoom(Site site, String id) : super(pSite: site, pRoomId: id);
  int stopped = 0;
  int disposed = 0;

  @override
  // The fixture exercises session ownership without starting native playback.
  // ignore: must_call_super
  void onInit() {
    liveStatus.value = true;
    playUrls.add('https://example.com/current-live.flv');
  }

  @override
  Future<void> stopSessionPlayback() async {
    stopped++;
    liveStatus.value = false;
  }

  @override
  // The native player is deliberately never created by this fixture.
  // ignore: must_call_super
  void onClose() {
    disposed++;
  }
}

void main() {
  setUp(() => Get.testMode = true);
  tearDown(() => Get.reset());
  final site = Site(id: 'douyu', name: '斗鱼', logo: '', liveSite: DouyuSite());
  test(
      'leaving and returning to the same room retains its controller and source',
      () {
    var created = 0;
    final session = LiveRoomSessionService(
        createController: (site, id) {
          created++;
          return FixtureRoom(site, id);
        },
        afterFrame: () async {});
    final room = session.enter(site, '123') as FixtureRoom;
    session.leave(room);
    expect(session.floating.value, isTrue);
    expect(room.isClosed, isFalse);
    final restored = session.enter(site, '123');
    expect(identical(restored, room), isTrue);
    expect(created, 1);
    expect(session.floating.value, isFalse);
    expect(restored.playUrls.single, 'https://example.com/current-live.flv');
    expect(room.stopped, 0);
  });
  test('rapid room changes stop old sound and dispose only retired sessions',
      () async {
    final frame = Completer<void>();
    final session = LiveRoomSessionService(
        createController: FixtureRoom.new, afterFrame: () => frame.future);
    final a = session.enter(site, 'a') as FixtureRoom;
    session.leave(a);
    final b = session.enter(site, 'b') as FixtureRoom;
    final c = session.enter(site, 'c') as FixtureRoom;
    expect(a.stopped, 1);
    expect(b.stopped, 1);
    expect(a.disposed, 0);
    frame.complete();
    await Future<void>.delayed(Duration.zero);
    expect(a.disposed, 1);
    expect(b.disposed, 1);
    expect(c.disposed, 0);
    expect(identical(session.active.value, c), isTrue);
    session.leave(a); // A late pop from an old room cannot hide the new room.
    expect(session.floating.value, isFalse);
  });
  test(
      'closing the floating player clears playback and releases its controller',
      () async {
    final session = LiveRoomSessionService(
        createController: FixtureRoom.new, afterFrame: () async {});
    final room = session.enter(site, '123') as FixtureRoom;
    session.leave(room);
    await session.stop();
    await session.stop();
    expect(session.floating.value, isFalse);
    expect(session.active.value, isNull);
    expect(room.stopped, 1);
    expect(room.disposed, 1);
  });
  test('leaving a failed room cleans up instead of retaining a dead player',
      () async {
    final session = LiveRoomSessionService(
        createController: FixtureRoom.new, afterFrame: () async {});
    final room = session.enter(site, '123') as FixtureRoom;
    room.loadError.value = true;
    session.leave(room);
    await Future<void>.delayed(Duration.zero);
    expect(session.active.value, isNull);
    expect(session.floating.value, isFalse);
    expect(room.disposed, 1);
  });
  test('canonical room IDs reuse the retained session', () {
    final session = LiveRoomSessionService(
        createController: FixtureRoom.new, afterFrame: () async {});
    final room = session.enter(site, 'old-web-id');
    room.rxRoomId.value = 'canonical-id';
    expect(session.enter(site, 'canonical-id'), same(room));
    expect(session.enter(site, 'old-web-id'), same(room));
  });
}
