import 'dart:io';

import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:pilipala/models/download/download_task.dart';
import 'package:pilipala/plugin/pl_player/index.dart';
import 'package:pilipala/plugin/pl_player/models/bottom_control_type.dart';
import 'package:pilipala/services/download_service.dart';

class DownloadPlayerPage extends StatefulWidget {
  const DownloadPlayerPage({super.key});

  @override
  State<DownloadPlayerPage> createState() => _DownloadPlayerPageState();
}

class _DownloadPlayerPageState extends State<DownloadPlayerPage> {
  final DownloadTask task = Get.arguments;
  final PlPlayerController plPlayerController = PlPlayerController();
  late final Future<void> _initFuture;

  @override
  void initState() {
    super.initState();
    _initFuture = _init();
  }

  Future<void> _init() async {
    final DownloadService service = DownloadService.to;
    final String video = service.videoPath(task);
    await plPlayerController.setDataSource(
      DataSource(
        type: DataSourceType.file,
        file: File(video),
        videoSource: video,
        audioSource: task.hasAudio ? service.audioPath(task) : null,
      ),
      enableHA: true,
      autoplay: true,
      width: task.width?.toDouble(),
      height: task.height?.toDouble(),
      direction: task.width != null &&
              task.height != null &&
              task.height! > task.width!
          ? 'vertical'
          : 'horizontal',
      // 离线播放不上报观看历史
      enableHeart: false,
    );
  }

  @override
  void dispose() {
    plPlayerController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bool landscape =
        MediaQuery.of(context).orientation == Orientation.landscape;
    final Widget player = FutureBuilder(
      future: _initFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }
        return PLVideoPlayer(
          controller: plPlayerController,
          bottomList: const [
            BottomControlType.playOrPause,
            BottomControlType.time,
            BottomControlType.space,
            BottomControlType.speed,
            BottomControlType.fit,
            BottomControlType.fullscreen,
          ],
        );
      },
    );

    return PopScope(
      canPop: !plPlayerController.isFullScreen.value,
      onPopInvoked: (bool didPop) {
        if (plPlayerController.isFullScreen.value) {
          plPlayerController.triggerFullScreen(status: false);
        }
        if (landscape) {
          verticalScreen();
        }
      },
      child: Scaffold(
        backgroundColor: landscape ? Colors.black : null,
        appBar: landscape ? null : AppBar(title: const Text('离线播放')),
        body: landscape
            ? SizedBox.expand(child: player)
            : Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    color: Colors.black,
                    width: double.infinity,
                    height: MediaQuery.of(context).size.width * 9 / 16,
                    child: player,
                  ),
                  Padding(
                    padding: const EdgeInsets.all(14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(task.title, style: const TextStyle(fontSize: 16)),
                        if (task.partTitle != null) ...[
                          const SizedBox(height: 4),
                          Text(
                            task.partTitle!,
                            style: TextStyle(
                                color: Theme.of(context).colorScheme.outline),
                          ),
                        ],
                        const SizedBox(height: 4),
                        Text(
                          task.qnDesc,
                          style: TextStyle(
                              fontSize: 12,
                              color: Theme.of(context).colorScheme.outline),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}
