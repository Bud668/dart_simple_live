import 'dart:async';
import 'package:flutter/widgets.dart';
import 'package:get/get.dart';
import 'package:simple_live_app/app/sites.dart';
import 'package:simple_live_app/modules/multi_live/multi_live_room.dart';

class MultiLiveController extends GetxController {
  MultiLiveController(
      {MultiLiveRoom Function(Site, String)? createRoom,
      Future<void> Function()? afterFrame,
      this.volume = 70})
      : _createRoom = createRoom ?? MultiLiveRoom.new,
        _afterFrame = afterFrame ?? (() => WidgetsBinding.instance.endOfFrame);
  final MultiLiveRoom Function(Site, String) _createRoom;
  final Future<void> Function() _afterFrame;
  final double volume;
  final rooms = <MultiLiveRoom>[].obs;
  final audibleRooms = <MultiLiveRoom>{}.obs;
  final focusedRoom = Rxn<MultiLiveRoom>();
  final audioError = ''.obs;
  bool _closed = false;
  Future<void> _audioTask = Future<void>.value();
  final _retiring = <Future<void>>{};

  MultiLiveRoom? add(Site site, String id) {
    if (_closed || id.trim().isEmpty) return null;
    for (final room in rooms) {
      if (room.site.id == site.id &&
          (room.roomId == id || room.requestedId == id)) {
        return room;
      }
    }
    if (rooms.length >= 9) return null;
    final room = _createRoom(site, id.trim());
    rooms.add(room);
    focusedRoom.value = null;
    // New streams always start muted, including those imported from a mini player.
    room.start();
    return room;
  }

  void toggleFocus(MultiLiveRoom room) {
    if (!rooms.contains(room)) return;
    focusedRoom.value = identical(focusedRoom.value, room) ? null : room;
  }

  bool isAudible(MultiLiveRoom room) => audibleRooms.contains(room);

  Future<void> setAudioEnabled(MultiLiveRoom room, bool enabled) {
    if (_closed || !rooms.contains(room)) return Future.value();
    if (enabled) {
      audibleRooms.add(room);
    } else {
      audibleRooms.remove(room);
    }
    return _queueAudio();
  }

  Future<void> toggleAudio(MultiLiveRoom room) =>
      setAudioEnabled(room, !isAudible(room));

  Future<void> muteAll() {
    audibleRooms.clear();
    return _queueAudio();
  }

  Future<void> _queueAudio() {
    // Each queued update reads the latest independent choices for all rooms.
    _audioTask = _audioTask.then((_) async {
      if (_closed) return;
      await Future.wait(rooms
          .toList()
          .map((room) => room.setAudioVolume(isAudible(room) ? volume : 0)));
      audioError.value = '';
    }).catchError((Object _) {
      audioError.value = '声音设置失败，请重试';
    });
    return _audioTask;
  }

  Future<void> remove(MultiLiveRoom room) async {
    if (!rooms.remove(room)) return;
    if (identical(focusedRoom.value, room)) focusedRoom.value = null;
    audibleRooms.remove(room);
    final retiring = _retire(room);
    _retiring.add(retiring);
    try {
      await retiring;
    } finally {
      _retiring.remove(retiring);
    }
  }

  Future<void> _retire(MultiLiveRoom room) async {
    final stopped = room.stop();
    await _afterFrame();
    await stopped;
    await _audioTask;
    await room.dispose();
  }

  Future<void> clear() async {
    final previous = rooms.toList();
    rooms.clear();
    audibleRooms.clear();
    focusedRoom.value = null;
    final work = previous.map(_retire).toList();
    _retiring.addAll(work);
    try {
      await Future.wait(work);
    } finally {
      _retiring.removeAll(work);
    }
  }

  Future<void> shutdown() async {
    if (_closed) return;
    _closed = true;
    await clear();
    await Future.wait(_retiring.toList());
  }

  @override
  void onClose() {
    unawaited(shutdown());
    super.onClose();
  }
}
