import 'dart:async';
import 'package:canvas_danmaku/canvas_danmaku.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:simple_live_app/modules/multi_live/multi_live_danmaku.dart';
import 'package:simple_live_core/simple_live_core.dart';

class FakeChat extends LiveDanmaku {
  int starts = 0, stops = 0;
  Completer<void>? gate;
  @override
  Future start(dynamic args) async {
    starts++;
    await gate?.future;
  }

  @override
  Future stop() async {
    stops++;
  }
}

void main() {
  testWidgets(
      'overlay passes pointer events and disconnects after delayed startup',
      (tester) async {
    final chat = FakeChat()..gate = Completer<void>();
    var tapped = 0;
    await tester.pumpWidget(MaterialApp(
        home: GestureDetector(
      onTap: () => tapped++,
      behavior: HitTestBehavior.opaque,
      child: SizedBox(
          width: 600,
          height: 30,
          child: MultiLiveDanmaku(createDanmaku: () => chat, args: 'room')),
    )));
    await tester.pump();
    expect(chat.starts, 1);
    await tester.tapAt(tester.getCenter(find.byType(MultiLiveDanmaku)));
    expect(tapped, 1);
    final option =
        tester.widget<DanmakuScreen>(find.byType(DanmakuScreen)).option;
    expect(option.massiveMode, false);
    expect(option.opacity, lessThanOrEqualTo(.6));
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
    expect(chat.stops, greaterThanOrEqualTo(1));
    expect(chat.onMessage, isNull);
    chat.gate!.complete();
    await tester.pump();
    expect(chat.stops, greaterThanOrEqualTo(2));
    // The renderer drains its final finite 100 ms cleanup delay after disposal.
    await tester.pump(const Duration(milliseconds: 200));
    expect(tester.takeException(), isNull);
  });
}
