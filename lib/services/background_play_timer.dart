import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:hive/hive.dart';
import 'package:pilipala/plugin/pl_player/index.dart';
import 'package:pilipala/utils/storage.dart';

// 进入后台/息屏后按设置的时长继续播放，到时自动暂停；回到前台即取消计时
class BackgroundPlayTimer {
  static AppLifecycleListener? _listener;
  static Timer? _timer;

  static const List<int> options = [0, 15, 30, 45, 60, 90, 120];

  static void init() {
    _listener ??= AppLifecycleListener(
      onPause: _start,
      onResume: () => _timer?.cancel(),
    );
  }

  static void _start() {
    _timer?.cancel();
    final Box setting = GStrorage.setting;
    if (!setting.get(SettingBoxKey.enableBackgroundPlay, defaultValue: false)) {
      return;
    }
    final int minutes =
        setting.get(SettingBoxKey.backgroundPlayMinutes, defaultValue: 0);
    if (minutes <= 0) return;
    _timer = Timer(Duration(minutes: minutes), () {
      final PlPlayerController? player = PlPlayerController.current;
      if (player != null && player.playerStatus.playing) {
        player.pause();
      }
    });
  }
}
