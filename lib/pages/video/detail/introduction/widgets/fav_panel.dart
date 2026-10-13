import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:get/get.dart';
import 'package:hive/hive.dart';
import 'package:pilipala/common/widgets/http_error.dart';
import 'package:pilipala/utils/storage.dart';

class FavPanel extends StatefulWidget {
  const FavPanel({super.key, this.ctr, this.scrollController});
  final dynamic ctr;
  final ScrollController? scrollController;

  @override
  State<FavPanel> createState() => _FavPanelState();
}

class _FavPanelState extends State<FavPanel> {
  final Box<dynamic> localCache = GStrorage.localCache;
  late Future _futureBuilderFuture;
  bool _submitting = false;

  @override
  void initState() {
    super.initState();
    _futureBuilderFuture = widget.ctr!.queryVideoInFolder();
  }

  Future<void> _chooseAndSubmit(bool checkValue, int index) async {
    if (_submitting) return;
    _submitting = true;
    widget.ctr!.onChoose(checkValue, index);
    try {
      await widget.ctr!.actionFavVideo();
    } finally {
      _submitting = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        AppBar(
          centerTitle: false,
          elevation: 0,
          automaticallyImplyLeading: false,
          leadingWidth: 0,
          title: Text(
            '选择收藏夹',
            style: Theme.of(context)
                .textTheme
                .titleMedium!
                .copyWith(fontWeight: FontWeight.bold),
          ),
        ),
        Expanded(
          child: Material(
            child: FutureBuilder(
              future: _futureBuilderFuture,
              builder: (BuildContext context, AsyncSnapshot snapshot) {
                if (snapshot.connectionState == ConnectionState.done) {
                  Map data = snapshot.data as Map;
                  if (data['status']) {
                    return Obx(
                      () => ListView.builder(
                        controller: widget.scrollController,
                        itemCount: widget.ctr!.favFolderData.value.list!.length,
                        itemBuilder: (context, index) {
                          final item =
                              widget.ctr!.favFolderData.value.list![index];
                          return ListTile(
                            onTap: () =>
                                _chooseAndSubmit(item.favState != 1, index),
                            dense: true,
                            leading: Icon([23, 1].contains(item.attr)
                                ? Icons.lock_outline
                                : Icons.folder_outlined),
                            minLeadingWidth: 0,
                            title: Text(item.title!),
                            subtitle: Text(
                              '${item.mediaCount}个内容 - ${[
                                23,
                                1
                              ].contains(item.attr) ? '私密' : '公开'}',
                            ),
                            trailing: Transform.scale(
                              scale: 0.9,
                              child: Checkbox(
                                value: item.favState == 1,
                                onChanged: (bool? checkValue) =>
                                    _chooseAndSubmit(checkValue!, index),
                              ),
                            ),
                          );
                        },
                      ),
                    );
                  } else {
                    return HttpError(
                      errMsg: data['msg'],
                      fn: () => setState(() {}),
                    );
                  }
                } else {
                  // 骨架屏
                  return const Text('请求中');
                }
              },
            ),
          ),
        ),
      ],
    );
  }
}
