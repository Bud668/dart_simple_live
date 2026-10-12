import 'dart:async';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:simple_live_core/simple_live_core.dart';
import 'package:simple_live_core/src/common/http_client.dart';

class CdnFixture extends DouyuSite {
  final requested = <String>[];
  final release = Completer<void>();
  @override
  Future<String> getPlayUrl(
      String roomId, String args, int rate, String cdn) async {
    requested.add(cdn);
    await release.future;
    if (cdn == 'failed') throw StateError('CDN unavailable');
    return 'https://example.com/live.flv';
  }
}

void main() {
  final room = LiveRoomDetail(
      roomId: '123',
      title: '',
      cover: '',
      userName: '',
      userAvatar: '',
      online: 0,
      status: true,
      data: 'signed=test',
      url: '');
  test('CDNs are requested together and failures preserve usable URLs',
      () async {
    final site = CdnFixture();
    final request = site.getPlayUrls(
        detail: room,
        quality: LivePlayQuality(
            quality: 'test',
            data: DouyuPlayData(
                0, ['failed', 'working', 'duplicate', 'working'])));
    expect(site.requested, ['failed', 'working', 'duplicate']);
    site.release.complete();
    expect((await request).urls, ['https://example.com/live.flv']);
  });
  test('empty and rejected API responses are not returned as null/null URLs',
      () async {
    var response = <String, dynamic>{'error': 0, 'data': {}};
    final interceptor = InterceptorsWrapper(onRequest: (options, handler) {
      handler.resolve(
          Response(requestOptions: options, statusCode: 200, data: response));
    });
    HttpClient.instance.dio.interceptors.add(interceptor);
    try {
      await expectLater(DouyuSite().getPlayUrl('123', 'signed=test', 0, 'cdn'),
          throwsException);
      response = {
        'error': 1,
        'data': {'rtmp_url': 'https://example.com', 'rtmp_live': 'live.flv'}
      };
      await expectLater(DouyuSite().getPlayUrl('123', 'signed=test', 0, 'cdn'),
          throwsException);
    } finally {
      HttpClient.instance.dio.interceptors.remove(interceptor);
    }
  });
}
