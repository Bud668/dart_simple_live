import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:simple_live_app/modules/search/search_list_controller.dart';
import 'package:simple_live_app/app/sites.dart';
import 'package:simple_live_app/modules/search/douyin/douyin_search_controller.dart';
import 'package:simple_live_core/simple_live_core.dart';
import 'package:simple_live_core/src/scripts/douyin_sign.dart';
import 'package:simple_live_core/src/common/http_client.dart';
import 'package:dio/dio.dart';

class SearchFixture extends DouyinSite {
  final requests = <Completer<LiveSearchRoomResult>>[];
  @override
  Future<LiveSearchRoomResult> searchRooms(String keyword, {int page = 1}) {
    final request = Completer<LiveSearchRoomResult>();
    requests.add(request);
    return request.future;
  }

  @override
  Future<LiveSearchAnchorResult> searchAnchors(String keyword, {int page = 1}) {
    throw StateError('unsupported endpoint must not be called');
  }
}

SearchListController searchController(SearchFixture fixture) =>
    SearchListController(
        Site(id: 'douyin', liveSite: fixture, name: '抖音', logo: ''))
      ..keyword = '游戏';

void main() {
  CoreLog.enableLog = false;
  test('anchor search uses the official user tab without the unsupported API',
      () async {
    final controller = searchController(SearchFixture())..searchMode.value = 1;
    await controller.refreshData();
    expect(controller.useWebSearch.value, isTrue);
    expect(controller.pageError.value, isFalse);
    final url = Uri.parse(DouyinSearchController.searchUrlFor(' 游戏 ', 1));
    expect(url.pathSegments.last, '游戏');
    expect(url.queryParameters['type'], 'user');
    expect(
        Uri.parse(DouyinSearchController.searchUrlFor('游戏', 0))
            .queryParameters['type'],
        'live');
  });
  test('rapid searches discard old errors and keep the latest results',
      () async {
    final fixture = SearchFixture();
    final controller = searchController(fixture);
    final oldRequest = controller.refreshData();
    controller.keyword = '新的关键词';
    final latestRequest = controller.refreshData();
    fixture.requests[1].complete(LiveSearchRoomResult(hasMore: false, items: [
      LiveRoomItem(
          roomId: '123', title: '新结果', cover: '', userName: '主播', online: 1)
    ]));
    await latestRequest;
    fixture.requests[0].completeError(StateError('old timeout'));
    await oldRequest;
    expect(controller.list.single.roomId, '123');
    expect(controller.canLoadMore.value, isFalse);
    expect(controller.useWebSearch.value, isFalse);
  });
  test(
      'room search errors switch to official web search without an error screen',
      () async {
    final fixture = SearchFixture();
    final controller = searchController(fixture);
    final request = controller.refreshData();
    fixture.requests.single.completeError(StateError('login required'));
    await request;
    expect(controller.useWebSearch.value, isTrue);
    expect(controller.pageError.value, isFalse);
    expect(controller.pageLoadding.value, isFalse);
  });
  test('authentication errors are not shown as empty search results', () async {
    final interceptor = InterceptorsWrapper(onRequest: (options, handler) {
      handler.resolve(Response(
          requestOptions: options,
          statusCode: 200,
          data: {'status_code': 2483, 'data': []}));
    });
    HttpClient.instance.dio.interceptors.add(interceptor);
    try {
      await expectLater(DouyinSite().searchRooms('游戏'), throwsException);
    } finally {
      HttpClient.instance.dio.interceptors.remove(interceptor);
    }
  });
  test('signing preserves Chinese keywords and replaces an empty token', () {
    final uri = Uri.parse(DouyinSign.getAbogusUrl(
      'https://www.douyin.com/search?keyword=%E6%B8%B8%E6%88%8F&msToken=&a_bogus=old',
      DouyinSite.kDefaultUserAgent,
    ));
    expect(uri.queryParameters['keyword'], '游戏');
    expect(uri.queryParametersAll['msToken'], hasLength(1));
    expect(uri.queryParameters['msToken'], isNotEmpty);
    expect(uri.queryParametersAll['a_bogus'], hasLength(1));
    expect(uri.queryParameters['a_bogus'], isNot('old'));
  });

  test(
      'search signs requests, preserves session cookie and handles mixed results',
      () async {
    final site = DouyinSite()..cookie = 'ttwid=test-session';
    late RequestOptions request;
    final interceptor = InterceptorsWrapper(onRequest: (options, handler) {
      request = options;
      handler.resolve(Response(requestOptions: options, statusCode: 200, data: {
        'data': [
          {
            'lives': {
              'rawdata': {
                'owner': {'web_rid': '12345', 'nickname': '主播'},
                'title': '直播',
                'cover': {
                  'url_list': ['https://example.com/cover']
                },
                'stats': {'total_user': 3}
              }
            }
          },
          {'type': 'unrelated-search-item'},
        ],
      }));
    });
    HttpClient.instance.dio.interceptors.add(interceptor);
    try {
      final result = await site.searchRooms('游戏');
      expect(request.uri.queryParameters['a_bogus'], isNotEmpty);
      expect(request.headers['cookie'], 'ttwid=test-session');
      expect(result.items.single.roomId, '12345');
      expect(result.items.single.userName, '主播');
    } finally {
      HttpClient.instance.dio.interceptors.remove(interceptor);
    }
  });

  test(
      'intercepts live room links without intercepting unrelated or spoofed hosts',
      () {
    expect(
        DouyinSearchController.roomIdFromUrl(
            Uri.parse('https://live.douyin.com/12345?from=search')),
        '12345');
    expect(
        DouyinSearchController.roomIdFromUrl(
            Uri.parse('https://www.douyin.com/search/游戏')),
        isNull);
    expect(
        DouyinSearchController.roomIdFromUrl(
            Uri.parse('https://live.douyin.com.evil.test/12345')),
        isNull);
    expect(
        DouyinSearchController.roomIdFromUrl(
            Uri.parse('https://live.douyin.com/')),
        isNull);
  });
}
