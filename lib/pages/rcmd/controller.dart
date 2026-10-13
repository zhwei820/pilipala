import 'package:flutter/cupertino.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:get/get.dart';
import 'package:hive/hive.dart';
import 'package:pilipala/http/video.dart';
import 'package:pilipala/models/home/rcmd/result.dart';
import 'package:pilipala/models/model_rec_video_item.dart';
import 'package:pilipala/utils/storage.dart';

class RcmdController extends GetxController {
  final ScrollController scrollController = ScrollController();
  int _currentPage = 0;
  // RxList<RecVideoItemAppModel> appVideoList = <RecVideoItemAppModel>[].obs;
  // RxList<RecVideoItemModel> webVideoList = <RecVideoItemModel>[].obs;
  bool isLoadingMore = true;
  OverlayEntry? popupDialog;
  Box setting = GStrorage.setting;
  RxInt crossAxisCount = 2.obs;
  late bool enableSaveLastData;
  late String defaultRcmdType = 'web';
  late RxList<dynamic> videoList;
  // 网格行高 + 行间距，由视图按当前列数与字体缩放写入
  double rowExtent = 0;

  @override
  void onInit() {
    super.onInit();
    crossAxisCount.value =
        setting.get(SettingBoxKey.customRows, defaultValue: 2);
    enableSaveLastData =
        setting.get(SettingBoxKey.enableSaveLastData, defaultValue: false);
    defaultRcmdType =
        setting.get(SettingBoxKey.defaultRcmdType, defaultValue: 'web');
    if (defaultRcmdType == 'web') {
      videoList = <RecVideoItemModel>[].obs;
    } else {
      videoList = <RecVideoItemAppModel>[].obs;
    }
  }

  // 获取推荐
  Future queryRcmdFeed(type) async {
    if (isLoadingMore == false) {
      return;
    }
    if (type == 'onRefresh') {
      _currentPage = 0;
    }
    late final Map<String, dynamic> res;
    switch (defaultRcmdType) {
      case 'app':
      case 'notLogin':
        res = await VideoHttp.rcmdVideoListApp(
          loginStatus: defaultRcmdType != 'notLogin',
          freshIdx: _currentPage,
        );
        break;
      default: //'web'
        res = await VideoHttp.rcmdVideoList(
          freshIdx: _currentPage,
          ps: 20,
        );
    }
    if (res['status']) {
      if (type == 'init') {
        if (videoList.isNotEmpty) {
          videoList.addAll(res['data']);
        } else {
          videoList.value = res['data'];
        }
      } else if (type == 'onRefresh') {
        if (enableSaveLastData) {
          videoList.insertAll(0, res['data']);
        } else {
          videoList.value = res['data'];
        }
      } else if (type == 'onLoad') {
        videoList.addAll(res['data']);
      } else if (type == 'appendBelow') {
        _insertBelowViewport(res['data']);
      }
      _currentPage += 1;
      // 若videoList数量太小，可能会影响翻页，此时再次请求
      // 为避免请求到的数据太少时还在反复请求，要求本次返回数据大于1条才触发
      if (res['data'].length > 1 && videoList.length < 10) {
        queryRcmdFeed('onLoad');
      }
    }
    isLoadingMore = false;
    return res;
  }

  // 下拉刷新
  Future onRefresh() async {
    isLoadingMore = true;
    queryRcmdFeed('onRefresh');
  }

  /// 双击首页：保留当前卡片，把新推荐接在屏幕可见卡片之后并上滚到新卡片
  Future appendBelow() async {
    isLoadingMore = true;
    await queryRcmdFeed('appendBelow');
  }

  void _insertBelowViewport(List data) {
    if (data.isEmpty) return;
    if (rowExtent <= 0 || !scrollController.hasClients) {
      videoList.addAll(data);
      return;
    }
    final int columns = crossAxisCount.value;
    final ScrollPosition pos = scrollController.position;
    // 第一行完全位于屏幕下方的行，新卡片从这里插入；部分可见的卡片保留在上方
    final int row =
        ((pos.pixels + pos.viewportDimension) / rowExtent).ceil();
    final int index = (row * columns).clamp(0, videoList.length);
    videoList.insertAll(index, data);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!scrollController.hasClients) return;
      final double target = ((index ~/ columns) * rowExtent)
          .clamp(0.0, scrollController.position.maxScrollExtent);
      scrollController.animateTo(target,
          duration: const Duration(milliseconds: 500), curve: Curves.easeInOut);
    });
  }

  // 上拉加载
  Future onLoad() async {
    queryRcmdFeed('onLoad');
  }

  // 返回顶部
  void animateToTop() async {
    if (scrollController.offset >=
        MediaQuery.of(Get.context!).size.height * 5) {
      scrollController.jumpTo(0);
    } else {
      await scrollController.animateTo(0,
          duration: const Duration(milliseconds: 500), curve: Curves.easeInOut);
    }
  }

  void blockUserCb(mid) {
    videoList.removeWhere((e) => e.owner.mid == mid);
    videoList.refresh();
    SmartDialog.showToast('已移除相关视频');
  }
}
