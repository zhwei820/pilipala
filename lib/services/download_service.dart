import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:get/get.dart' hide Response;
import 'package:path_provider/path_provider.dart';
import 'package:pilipala/http/constants.dart';
import 'package:pilipala/http/video.dart';
import 'package:pilipala/models/download/download_task.dart';
import 'package:pilipala/models/video/play/url.dart';
import 'package:pilipala/utils/storage.dart';
import 'package:pilipala/utils/video_utils.dart';

class DownloadService extends GetxService {
  static DownloadService get to => Get.isRegistered<DownloadService>()
      ? Get.find<DownloadService>()
      : Get.put(DownloadService(), permanent: true);

  final RxList<DownloadTask> tasks = <DownloadTask>[].obs;

  // CDN 校验 referer，缺失会 403
  final Dio _dio = Dio(BaseOptions(
    connectTimeout: const Duration(seconds: 15),
    receiveTimeout: const Duration(seconds: 30),
    headers: {
      'user-agent':
          'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/15.2 Safari/605.1.15',
      'referer': HttpString.baseUrl,
    },
  ));

  late final Future<void> _ready;
  late final String _rootDir;
  DownloadTask? _running;
  CancelToken? _cancelToken;
  int _lastNotify = 0;
  int _lastPersist = 0;

  @override
  void onInit() {
    super.onInit();
    _ready = _load();
  }

  Future<void> _load() async {
    final Directory dir = await getApplicationDocumentsDirectory();
    _rootDir = '${dir.path}/download';
    final List<DownloadTask> list = GStrorage.download.values
        .map((e) => DownloadTask.fromJson(Map.from(e)))
        .toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    // 上次进程被杀时未完成的任务不自动续传，避免静默消耗流量
    for (final DownloadTask t in list) {
      if (t.status == DownloadStatus.downloading ||
          t.status == DownloadStatus.waiting) {
        t.status = DownloadStatus.paused;
      }
    }
    tasks.assignAll(list);
  }

  Future<void> get ready => _ready;

  String taskDir(DownloadTask t) => '$_rootDir/${t.id}';
  String videoPath(DownloadTask t) => '${taskDir(t)}/video.m4s';
  String audioPath(DownloadTask t) => '${taskDir(t)}/audio.m4s';
  String coverPath(DownloadTask t) => '${taskDir(t)}/cover.jpg';

  DownloadTask? find(String bvid, int cid) =>
      tasks.firstWhereOrNull((t) => t.bvid == bvid && t.cid == cid);

  Future<void> add(DownloadTask task) async {
    await _ready;
    final DownloadTask? exist = find(task.bvid, task.cid);
    if (exist != null) {
      SmartDialog.showToast(
          exist.status == DownloadStatus.completed ? '已缓存过该视频' : '已在缓存列表中');
      return;
    }
    tasks.insert(0, task);
    _persist(task);
    SmartDialog.showToast('已加入缓存队列');
    _schedule();
  }

  void pause(DownloadTask t) {
    if (t.status != DownloadStatus.downloading &&
        t.status != DownloadStatus.waiting) {
      return;
    }
    t.status = DownloadStatus.paused;
    if (identical(_running, t)) {
      _cancelToken?.cancel();
    }
    _persist(t);
    tasks.refresh();
  }

  void resume(DownloadTask t) {
    if (t.status != DownloadStatus.paused &&
        t.status != DownloadStatus.failed) {
      return;
    }
    t.status = DownloadStatus.waiting;
    t.error = null;
    _persist(t);
    tasks.refresh();
    _schedule();
  }

  Future<void> remove(DownloadTask t) async {
    tasks.remove(t);
    await GStrorage.download.delete(t.id);
    if (identical(_running, t)) {
      _cancelToken?.cancel();
    }
    final Directory dir = Directory(taskDir(t));
    if (await dir.exists()) {
      await dir.delete(recursive: true);
    }
  }

  void _persist(DownloadTask t) {
    if (!tasks.contains(t)) return;
    GStrorage.download.put(t.id, t.toJson());
  }

  void _schedule() {
    if (_running != null) return;
    // 列表按新到旧排列，队列按加入顺序执行
    final Iterable<DownloadTask> waiting =
        tasks.where((t) => t.status == DownloadStatus.waiting);
    if (waiting.isNotEmpty) {
      _run(waiting.last);
    }
  }

  Future<void> _run(DownloadTask t) async {
    _running = t;
    final CancelToken token = _cancelToken = CancelToken();
    t.status = DownloadStatus.downloading;
    t.error = null;
    _persist(t);
    tasks.refresh();
    try {
      // 播放地址约两小时过期，每次开始/续传都重新获取
      final _Streams streams = await _resolveStreams(t);
      t.width = streams.width;
      t.height = streams.height;
      t.hasAudio = streams.audioUrl != null;
      await Directory(taskDir(t)).create(recursive: true);
      await _downloadCover(t);

      final int videoTotal = await _probeSize(streams.videoUrl, token);
      final int audioTotal = streams.audioUrl != null
          ? await _probeSize(streams.audioUrl!, token)
          : 0;
      t.totalBytes = videoTotal + audioTotal;

      await _downloadFile(streams.videoUrl, videoPath(t), videoTotal, token,
          (int received) => _onProgress(t, received));
      if (streams.audioUrl != null) {
        await _downloadFile(streams.audioUrl!, audioPath(t), audioTotal, token,
            (int received) => _onProgress(t, videoTotal + received));
      }
      t.receivedBytes = t.totalBytes;
      t.status = DownloadStatus.completed;
    } catch (err) {
      // 暂停/删除会取消请求，此时状态已由调用方设置
      if (!token.isCancelled) {
        t.status = DownloadStatus.failed;
        t.error = err is DioException ? (err.message ?? err.type.name) : '$err';
      }
    } finally {
      _running = null;
      _cancelToken = null;
      _persist(t);
      tasks.refresh();
      _schedule();
    }
  }

  void _onProgress(DownloadTask t, int received) {
    t.receivedBytes = received;
    final int now = DateTime.now().millisecondsSinceEpoch;
    if (now - _lastNotify > 300) {
      _lastNotify = now;
      tasks.refresh();
    }
    if (now - _lastPersist > 2000) {
      _lastPersist = now;
      _persist(t);
    }
  }

  Future<_Streams> _resolveStreams(DownloadTask t) async {
    final res = await VideoHttp.videoUrl(bvid: t.bvid, cid: t.cid, qn: t.qn);
    if (!res['status']) {
      throw res['msg'] ?? '获取播放地址失败';
    }
    final PlayUrlModel data = res['data'];
    final bool enableCDN =
        GStrorage.setting.get(SettingBoxKey.enableCDN, defaultValue: true);
    String urlOf(dynamic item) => enableCDN
        ? VideoUtils.getCdnUrl(item)
        : (item.backupUrl ?? item.baseUrl!);

    final List<VideoItem> videos = data.dash?.video ?? [];
    if (videos.isNotEmpty) {
      // 会员过期等情况下拿不到原画质时，退到不高于它的最高画质
      List<VideoItem> candidates = videos.where((e) => e.id == t.qn).toList();
      if (candidates.isEmpty) {
        final List<int> ids = videos.map((e) => e.id!).toSet().toList()
          ..sort((a, b) => b.compareTo(a));
        final int fallback =
            ids.firstWhere((id) => id <= t.qn, orElse: () => ids.last);
        candidates = videos.where((e) => e.id == fallback).toList();
      }
      // AVC 兼容性最好，部分设备硬解不了 HEVC/AV1
      final VideoItem video = candidates
              .firstWhereOrNull((e) => e.codecs?.startsWith('avc') ?? false) ??
          candidates
              .firstWhereOrNull((e) => e.codecs?.startsWith('hev') ?? false) ??
          candidates.first;
      final List<AudioItem> audios = [...?data.dash?.audio]
        ..sort((a, b) => (b.bandWidth ?? 0).compareTo(a.bandWidth ?? 0));
      return _Streams(
        videoUrl: urlOf(video),
        audioUrl: audios.isNotEmpty ? urlOf(audios.first) : null,
        width: video.width,
        height: video.height,
      );
    }
    final List<Durl> durl = data.durl ?? [];
    if (durl.length == 1 && durl.first.url != null) {
      return _Streams(videoUrl: durl.first.url!);
    }
    throw '暂不支持该视频的缓存格式';
  }

  Future<void> _downloadCover(DownloadTask t) async {
    final File file = File(coverPath(t));
    if (t.cover.isEmpty || await file.exists()) return;
    try {
      final String url =
          t.cover.startsWith('//') ? 'https:${t.cover}' : t.cover;
      await _dio.download(url, file.path);
    } catch (_) {
      // 封面缺失不影响离线播放
    }
  }

  Future<int> _probeSize(String url, CancelToken token) async {
    final Response res = await _dio.get(
      url,
      cancelToken: token,
      options: Options(
        headers: {'range': 'bytes=0-0'},
        responseType: ResponseType.bytes,
      ),
    );
    final String? range = res.headers.value('content-range');
    final int? total =
        range != null ? int.tryParse(range.split('/').last) : null;
    if (total == null) {
      throw '无法获取文件大小';
    }
    return total;
  }

  /// 以 `.part` 临时文件断点续传，完整后再重命名
  Future<void> _downloadFile(
    String url,
    String path,
    int total,
    CancelToken token,
    void Function(int received) onReceived,
  ) async {
    final File done = File(path);
    if (await done.exists() && await done.length() == total) {
      onReceived(total);
      return;
    }
    final File part = File('$path.part');
    int start = await part.exists() ? await part.length() : 0;
    // 换了 CDN 节点或画质导致文件不一致时从头下载
    if (start > total) {
      await part.delete();
      start = 0;
    }
    if (start < total) {
      final Response<ResponseBody> res = await _dio.get<ResponseBody>(
        url,
        cancelToken: token,
        options: Options(
          headers: {'range': 'bytes=$start-'},
          responseType: ResponseType.stream,
        ),
      );
      // 服务端忽略 Range 时返回整个文件
      if (res.statusCode == 200 && start > 0) {
        start = 0;
      }
      final IOSink sink =
          part.openWrite(mode: start == 0 ? FileMode.write : FileMode.append);
      int received = start;
      try {
        await for (final List<int> chunk in res.data!.stream) {
          sink.add(chunk);
          received += chunk.length;
          onReceived(received);
        }
      } finally {
        await sink.flush();
        await sink.close();
      }
      if (received != total) {
        throw '下载不完整 ($received/$total)';
      }
    }
    await part.rename(path);
    onReceived(total);
  }
}

class _Streams {
  _Streams({required this.videoUrl, this.audioUrl, this.width, this.height});

  final String videoUrl;
  final String? audioUrl;
  final int? width;
  final int? height;
}
