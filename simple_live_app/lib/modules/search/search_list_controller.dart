import 'package:get/get.dart';
import 'package:simple_live_app/app/controller/base_controller.dart';
import 'package:simple_live_app/app/sites.dart';
import 'package:simple_live_app/app/constant.dart';

class SearchListController extends BasePageController {
  String keyword = "";
  final useWebSearch = false.obs;
  int _queryGeneration = 0;

  /// 搜索模式，0=直播间，1=主播
  var searchMode = 0.obs;
  final Site site;
  SearchListController(
    this.site,
  );

  @override
  Future<void> refreshData() async {
    final generation = ++_queryGeneration;
    currentPage = 1;
    list.clear();
    if (site.id == Constant.kDouyin && searchMode.value == 1) {
      openWebSearch();
    }
    if (keyword.trim().isEmpty || useWebSearch.value) return;
    await _loadPage(generation);
  }

  @override
  Future<void> loadData() async {
    if (loadding || useWebSearch.value || keyword.trim().isEmpty) return;
    await _loadPage(_queryGeneration);
  }

  Future<void> _loadPage(int generation) async {
    final query = keyword.trim();
    final mode = searchMode.value;
    final page = currentPage;
    bool isCurrent() => !isClosed && generation == _queryGeneration;
    loadding = true;
    pageLoadding.value = page == 1;
    pageError.value = false;
    pageEmpty.value = false;
    try {
      late List items;
      late bool hasMore;
      if (mode == 1) {
        final result = await site.liveSite.searchAnchors(query, page: page);
        items = result.items;
        hasMore = result.hasMore;
      } else {
        final result = await site.liveSite.searchRooms(query, page: page);
        items = result.items;
        hasMore = result.hasMore;
      }
      if (!isCurrent()) return;
      list.addAll(items);
      currentPage = page + 1;
      canLoadMore.value = hasMore && items.isNotEmpty;
      pageEmpty.value = list.isEmpty;
    } catch (error) {
      if (!isCurrent()) return;
      if (site.id == Constant.kDouyin) {
        openWebSearch();
      } else {
        handleError(error, showPageError: page == 1);
      }
    } finally {
      if (isCurrent()) {
        loadding = false;
        pageLoadding.value = false;
      }
    }
  }

  void openWebSearch() {
    _queryGeneration++;
    useWebSearch.value = true;
    loadding = false;
    pageLoadding.value = false;
    pageError.value = false;
    pageEmpty.value = false;
    canLoadMore.value = false;
  }

  void clear() {
    _queryGeneration++;
    loadding = false;
    pageLoadding.value = false;
    pageError.value = false;
    pageEmpty.value = false;
    canLoadMore.value = false;
    list.clear();
  }

  @override
  void onClose() {
    _queryGeneration++;
    scrollController.dispose();
    easyRefreshController.dispose();
    super.onClose();
  }
}
