import 'package:dio/dio.dart';

class ParsedLiveRoom {
  const ParsedLiveRoom(this.siteId, this.roomId);
  final String siteId;
  final String roomId;
}

/// Resolves supported public room links, including mobile share text.
class LiveRoomLinkParser {
  LiveRoomLinkParser({Future<Uri?> Function(Uri)? redirect})
      : _redirect = redirect ?? _requestRedirect;
  final Future<Uri?> Function(Uri) _redirect;

  static Future<Uri?> _requestRedirect(Uri uri) async {
    final dio = Dio(BaseOptions(
      connectTimeout: const Duration(seconds: 8),
      receiveTimeout: const Duration(seconds: 8),
      followRedirects: false,
      validateStatus: (status) =>
          status != null && status >= 200 && status < 400,
    ));
    try {
      final response = await dio.getUri(uri);
      final location = response.headers.value('location');
      return location == null ? null : uri.resolve(location);
    } finally {
      dio.close(force: true);
    }
  }

  Future<ParsedLiveRoom?> parse(String input, {String? defaultSiteId}) async {
    final match = RegExp(r'''https?://[^\s<>"，。]+''').firstMatch(input);
    if (match == null) {
      final id = input.trim();
      if (defaultSiteId != null &&
          RegExp(r'^[a-zA-Z0-9_]{1,64}$').hasMatch(id)) {
        return ParsedLiveRoom(defaultSiteId, id);
      }
      return null;
    }
    var uri = Uri.tryParse(match.group(0)!.replaceFirst(RegExp(r'[)）]+$'), ''));
    final visited = <String>{};
    try {
      for (var hop = 0; hop < 5 && uri != null; hop++) {
        if (!{'http', 'https'}.contains(uri.scheme) ||
            !visited.add(uri.toString())) {
          return null;
        }
        final host = uri.host.toLowerCase();
        final parts =
            uri.pathSegments.where((part) => part.isNotEmpty).toList();
        String? id;
        String? site;
        if (host == 'live.douyin.com') {
          site = 'douyin';
          id = parts.firstOrNull;
        } else if (host == 'webcast.amemv.com') {
          site = 'douyin';
          final index = parts.indexOf('reflow');
          if (index >= 0 && index + 1 < parts.length) id = parts[index + 1];
        } else if (host == 'live.bilibili.com') {
          site = 'bilibili';
          id = parts.firstOrNull;
        } else if (host == 'douyu.com' ||
            host == 'www.douyu.com' ||
            host == 'm.douyu.com') {
          site = 'douyu';
          id = parts.firstOrNull == 'topic'
              ? uri.queryParameters['rid']
              : parts.firstOrNull;
        } else if (host == 'huya.com' ||
            host == 'www.huya.com' ||
            host == 'm.huya.com') {
          site = 'huya';
          id = parts.firstOrNull;
        } else if (host == 'v.douyin.com' || host == 'b23.tv') {
          uri = await _redirect(uri);
          continue;
        }
        if (site != null &&
            id != null &&
            RegExp(r'^[a-zA-Z0-9_]{1,64}$').hasMatch(id)) {
          return ParsedLiveRoom(site, id);
        }
        return null;
      }
    } catch (_) {
      return null;
    }
    return null;
  }
}
