import 'dart:io';

import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:pilipala/models/download/download_task.dart';
import 'package:pilipala/pages/download/player.dart';
import 'package:pilipala/services/download_service.dart';

/// 处理文件管理器通过「打开方式」传入的 .m4s
class OpenedFile {
  static const MethodChannel _channel = MethodChannel('pilipala/file');

  /// 需在首页构建完成后调用，否则路由跳转无效
  static Future<void> init() async {
    _channel.setMethodCallHandler((MethodCall call) async {
      if (call.method == 'fileOpened') {
        await _open(Map.from(call.arguments));
      }
    });
    final Map? pending = await _channel.invokeMethod<Map>('takeOpenedFile');
    if (pending != null) {
      await _open(Map.from(pending));
    }
  }

  static Future<void> _open(Map file) async {
    final DownloadService service = DownloadService.to;
    await service.ready;
    final String? path = file['path'];
    if (path == null || !_readable(path)) {
      // 拿不到可读路径时直接交给播放器读 content uri，此时无法找到独立音轨
      Get.toNamed('/downloadPlayer',
          arguments: LocalVideoSource(video: file['uri'], title: '本地视频'));
      return;
    }

    final String dir = File(path).parent.path;
    final DownloadTask? task = service.tasks.firstWhereOrNull((t) =>
        service.taskDir(t) == dir && t.status == DownloadStatus.completed);
    if (task != null) {
      Get.toNamed('/downloadPlayer', arguments: task);
      return;
    }

    // 不在缓存列表中（如手动拷贝来的目录）：按 video.m4s + audio.m4s 配对
    final String videoPath = '$dir/video.m4s';
    final String audioPath = '$dir/audio.m4s';
    final String video =
        path == audioPath && _readable(videoPath) ? videoPath : path;
    Get.toNamed(
      '/downloadPlayer',
      arguments: LocalVideoSource(
        video: video,
        audio: video != audioPath && _readable(audioPath) ? audioPath : null,
        title: '${dir.split('/').last}/${video.split('/').last}',
      ),
    );
  }

  static bool _readable(String path) {
    try {
      File(path).openSync().closeSync();
      return true;
    } catch (_) {
      return false;
    }
  }
}
