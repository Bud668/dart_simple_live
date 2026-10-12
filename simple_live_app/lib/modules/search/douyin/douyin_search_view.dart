import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

import 'package:get/get.dart';
import 'package:simple_live_app/app/app_style.dart';
import 'package:simple_live_app/modules/search/douyin/douyin_search_controller.dart';
import 'package:simple_live_app/routes/app_navigation.dart';
import 'package:simple_live_app/widgets/keep_alive_wrapper.dart';
import 'package:simple_live_app/widgets/status/app_loadding_widget.dart';

class DouyinSearchView extends StatelessWidget {
  const DouyinSearchView({Key? key}) : super(key: key);
  DouyinSearchController get controller => Get.find<DouyinSearchController>();

  @override
  Widget build(BuildContext context) {
    return KeepAliveWrapper(
      child: Column(children: [
        Padding(
            padding: AppStyle.edgeInsetsH12,
            child: Row(children: [
              const Expanded(child: Text('抖音官网搜索；提示登录或验证码时，请在此页面完成')),
              TextButton(
                  onPressed: controller.reloadWebView, child: const Text('刷新')),
              TextButton(
                  onPressed: controller.openBrowser,
                  child: const Text('浏览器打开')),
            ])),
        Expanded(
            child: Stack(
          children: [
            SizedBox(
              width: double.infinity,
              height: double.infinity,
              child: Center(
                child: Padding(
                  padding: AppStyle.edgeInsetsA12,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      const Text(
                        "请打开抖音搜索，然后复制直播间链接进行解析",
                        textAlign: TextAlign.center,
                      ),
                      TextButton.icon(
                        onPressed: controller.openBrowser,
                        icon: const Icon(Icons.open_in_browser),
                        label: const Text("打开浏览器"),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            if (Platform.isAndroid ||
                Platform.isIOS ||
                Platform.isWindows ||
                Platform.isMacOS)
              InAppWebView(
                initialUrlRequest:
                    URLRequest(url: WebUri(controller.searchUrl)),
                onWebViewCreated: controller.onWebViewCreated,
                onLoadStop: controller.onLoadStop,
                onLoadStart: controller.onLoadStart,
                initialSettings: InAppWebViewSettings(
                  useOnLoadResource: true,
                  userAgent: Platform.isWindows || Platform.isMacOS
                      ? null
                      : "Mozilla/5.0 (iPhone; CPU iPhone OS 13_2_3 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/13.0.3 Mobile/15E148 Safari/604.1 Edg/118.0.0.0",
                  supportMultipleWindows: true,
                  useShouldOverrideUrlLoading: true,
                ),
                onCreateWindow: controller.onCreateWindow,
                onReceivedError: (webController, request, error) {
                  if (request.isForMainFrame == true) {
                    controller.pageLoadding.value = false;
                    controller.pageError.value = true;
                  }
                },
                onReceivedHttpError: (webController, request, response) {
                  if (request.isForMainFrame == true &&
                      (response.statusCode ?? 0) >= 400) {
                    controller.pageLoadding.value = false;
                    controller.pageError.value = true;
                  }
                },
                shouldOverrideUrlLoading:
                    (webController, navigationAction) async {
                  var uri = navigationAction.request.url;
                  if (uri == null) {
                    return NavigationActionPolicy.ALLOW;
                  }
                  final id = DouyinSearchController.roomIdFromUrl(uri);
                  if (id != null) {
                    AppNavigator.toLiveRoomDetail(
                        site: controller.site, roomId: id);
                    return NavigationActionPolicy.CANCEL;
                  }
                  return NavigationActionPolicy.ALLOW;
                },
              ),
            Obx(
              () => Visibility(
                visible: controller.pageError.value,
                child: ColoredBox(
                  color: Theme.of(context).scaffoldBackgroundColor,
                  child: Center(
                      child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text('抖音网页暂时无法打开'),
                      TextButton(
                          onPressed: controller.reloadWebView,
                          child: const Text('重试')),
                      TextButton(
                          onPressed: controller.openBrowser,
                          child: const Text('在浏览器中打开')),
                    ],
                  )),
                ),
              ),
            ),
            Obx(
              () => Visibility(
                visible: controller.pageLoadding.value,
                child: const AppLoaddingWidget(),
              ),
            ),
          ],
        )),
      ]),
    );
  }
}
