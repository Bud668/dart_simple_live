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
  final layout = 2.obs;
  final audioRoom = Rxn<MultiLiveRoom>();
  final focusedRoom = Rxn<MultiLiveRoom>();
  final audioError = ''.obs;
  bool _closed = false;
  bool _mutedByUser = false;
  Future<void> _audioTask = Future<void>.value();
  final _retiring = <Future<void>>{};
  static const layouts = [2, 3, 4, 9];

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
    if (rooms.length > layout.value) {
      layout.value = layouts.firstWhere((size) => size >= rooms.length);
    }
    room.start();
    if (audioRoom.value == null && !_mutedByUser) unawaited(selectAudio(room));
    return room;
  }

  bool setLayout(int size) {
    if (!layouts.contains(size) || rooms.length > size) return false;
    focusedRoom.value = null;
    layout.value = size;
    return true;
  }

  void toggleFocus(MultiLiveRoom room) {
    if (!rooms.contains(room)) return;
    focusedRoom.value = identical(focusedRoom.value, room) ? null : room;
  }

  Future<void> selectAudio(MultiLiveRoom? room) {
    if (_closed || (room != null && !rooms.contains(room))) {
      return Future.value();
    }
    _mutedByUser = room == null;
    audioRoom.value = room;
    return _queueAudio();
  }

  Future<void> _queueAudio() {
    // Mute all first and serialize changes so rapid clicks never unmute two rooms.
    _audioTask = _audioTask.then((_) async {
      if (_closed) return;
      final selected = audioRoom.value;
      await Future.wait(rooms.toList().map((room) => room.setAudioVolume(0)));
      if (!_closed &&
          selected != null &&
          identical(selected, audioRoom.value) &&
          rooms.contains(selected) &&
          !selected.isClosed) {
        await selected.setAudioVolume(volume);
      }
      audioError.value = '';
    }).catchError((Object _) {
      audioError.value = '声音切换失败，请重新选择';
    });
    return _audioTask;
  }

  Future<void> remove(MultiLiveRoom room) async {
    if (!rooms.remove(room)) return;
    if (identical(focusedRoom.value, room)) focusedRoom.value = null;
    if (identical(audioRoom.value, room)) {
      audioRoom.value = _mutedByUser ? null : rooms.firstOrNull;
      unawaited(_queueAudio());
    }
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
    audioRoom.value = null;
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
