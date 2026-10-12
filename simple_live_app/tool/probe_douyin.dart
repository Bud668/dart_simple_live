import 'dart:convert';
import 'package:simple_live_core/simple_live_core.dart';
import 'package:simple_live_core/src/scripts/douyin_sign.dart';

Future<void> main(List<String> args) async {
  final uri = Uri.parse(DouyinSign.getAbogusUrl(
    'https://www.douyin.com/aweme/v1/web/live/search/?keyword=%E6%B8%B8%E6%88%8F&msToken=',
    DouyinSite.kDefaultUserAgent,
  ));
  print(jsonEncode({
    'signaturePresent': uri.queryParameters['a_bogus']?.isNotEmpty == true,
    'msTokenCount': uri.queryParametersAll['msToken']?.length,
    'keywordPreserved': uri.queryParameters['keyword'] == '游戏',
  }));
  try {
    final result =
        await DouyinSite().searchRooms(args.isEmpty ? '游戏' : args.first);
    print(jsonEncode(
        {'searchCount': result.items.length, 'hasMore': result.hasMore}));
  } catch (error) {
    print(jsonEncode({'searchError': error.toString()}));
  }
}
