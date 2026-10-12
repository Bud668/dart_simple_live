import 'dart:io';

import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:get/get.dart';
import 'package:simple_live_app/app/controller/base_controller.dart';
import 'package:simple_live_app/app/sites.dart';
import 'package:simple_live_app/routes/app_navigation.dart';
import 'package:simple_live_core/simple_live_core.dart';
import 'package:url_launcher/url_launcher_string.dart';

class DouyinSearchController extends BaseController {
  InAppWebViewController? webViewController;

  void onWebViewCreated(InAppWebViewController controller) {
    webViewController = controller;
  }

  RxList<LiveRoomItem> list = <LiveRoomItem>[].obs;

  String keyword = "";

  /// 搜索模式，0=直播间，1=主播
  var searchMode = 0.obs;
  final Site site;
  DouyinSearchController(
    this.site,
  );

  String get searchUrl => searchUrlFor(keyword, searchMode.value);

  static String searchUrlFor(String keyword, int mode) {
    return 'https://www.douyin.com/search/${Uri.encodeComponent(keyword.trim())}'
        '?type=${mode == 1 ? 'user' : 'live'}';
  }

  void reloadWebView() {
    if (keyword.isEmpty) {
      return;
    }
    pageError.value = false;
    if (Platform.isAndroid ||
        Platform.isIOS ||
        Platform.isWindows ||
        Platform.isMacOS) {
      webViewController?.loadUrl(
        urlRequest: URLRequest(
          url: WebUri(searchUrl),
        ),
      );
    }
  }

  void onLoadStop(InAppWebViewController controller, Uri? uri) async {
    pageLoadding.value = false;
  }

  void onLoadStart(InAppWebViewController controller, Uri? uri) async {
    pageError.value = false;
    pageLoadding.value = true;
  }

  Future<bool?> onCreateWindow(InAppWebViewController controller,
      CreateWindowAction createWindowAction) async {
    final uri = createWindowAction.request.url;
    final id = roomIdFromUrl(uri);
    if (id != null) {
      AppNavigator.toLiveRoomDetail(site: site, roomId: id);
    } else if (uri != null && (uri.scheme == 'https' || uri.scheme == 'http')) {
      await controller.loadUrl(urlRequest: URLRequest(url: uri));
    }
    return false;
  }

  static String? roomIdFromUrl(Uri? uri) {
    if (uri == null ||
        uri.host != 'live.douyin.com' ||
        uri.pathSegments.isEmpty) {
      return null;
    }
    final id = uri.pathSegments.first;
    return RegExp(r'^\d+$').hasMatch(id) ? id : null;
  }

  void openBrowser() {
    launchUrlString(searchUrl, mode: LaunchMode.externalApplication);
  }

  @override
  void onClose() {
    webViewController = null;
    super.onClose();
  }
}
