import 'dart:async';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
// ignore: implementation_imports
import 'package:simple_live_core/src/common/web_socket_util.dart';

void main() {
  test('closing during handshake cannot resurrect callbacks or heartbeat',
      () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final arrived = Completer<HttpRequest>();
    final subscription = server.listen((request) => arrived.complete(request));
    var ready = 0;
    final client = WebScoketUtils(
        url: 'ws://127.0.0.1:${server.port}',
        heartBeatTime: 10,
        onReady: () => ready++);
    client.connect();
    final request = await arrived.future.timeout(const Duration(seconds: 3));
    client.close();
    final socket = await WebSocketTransformer.upgrade(request);
    await Future<void>.delayed(const Duration(milliseconds: 80));
    expect(ready, 0);
    expect(client.status, SocketStatus.closed);
    expect(client.heartBeatTimer, isNull);
    await socket.close();
    await subscription.cancel();
    await server.close(force: true);
  });
}
