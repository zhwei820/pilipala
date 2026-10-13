import 'dart:convert';
import 'dart:io';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:dio/dio.dart';
import 'package:flutter/services.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:get/get.dart' hide Response;
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:pilipala/http/constants.dart';
import 'package:pilipala/http/video.dart';
import 'package:pilipala/models/download/download_task.dart';
import 'package:pilipala/models/video/play/url.dart';
import 'package:pilipala/utils/id_utils.dart';
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
    final String privateRoot =
        '${(await getApplicationDocumentsDirectory()).path}/download';
    _rootDir = await _resolveRoot() ?? privateRoot;
    if (_rootDir != privateRoot) {
      await _migrate(privateRoot, _rootDir);
    }
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
    await _backfillFromEntry(list);
  }

  /// 早期导入的任务没有记录分P序号和UP主，从随视频一起移动过来的 entry.json 补齐
  Future<void> _backfillFromEntry(List<DownloadTask> list) async {
    final Map<String, Map<String, dynamic>> updated = {};
    for (final DownloadTask t in list) {
      if (t.page != null) continue;
      final File entryFile = File('${taskDir(t)}/entry.json');
      try {
        if (!await entryFile.exists()) continue;
        final Map entry = jsonDecode(await entryFile.readAsString());
        t.page = entry['page_data']?['page'];
        t.ownerName = entry['owner_name'];
        updated[t.id] = t.toJson();
      } catch (_) {}
    }
    if (updated.isNotEmpty) {
      await GStrorage.download.putAll(updated);
    }
  }

  Future<void> get ready => _ready;

  static const MethodChannel _channel = MethodChannel('pilipala/file');

  /// Android 放到公共 Download 目录，便于用户在文件管理器中查看；不可写时返回 null
  Future<String?> _resolveRoot() async {
    if (!Platform.isAndroid) return null;
    try {
      final int sdkInt = (await DeviceInfoPlugin().androidInfo).version.sdkInt;
      // Android 10 以上写自己创建的公共目录文件无需存储权限
      if (sdkInt < 29 && !await Permission.storage.request().isGranted) {
        return null;
      }
      final String? download =
          await _channel.invokeMethod<String>('downloadDir');
      if (download == null) return null;
      final Directory root = Directory('$download/PiliPala');
      await root.create(recursive: true);
      // 避免封面图出现在相册中
      final File noMedia = File('${root.path}/.nomedia');
      if (!await noMedia.exists()) {
        await noMedia.create();
      }
      return root.path;
    } catch (_) {
      return null;
    }
  }

  /// 迁移旧版本保存在应用私有目录中的缓存
  Future<void> _migrate(String from, String to) async {
    final Directory old = Directory(from);
    if (!await old.exists()) return;
    try {
      await for (final FileSystemEntity entity in old.list()) {
        if (entity is! Directory) continue;
        final String target = '$to/${entity.path.split('/').last}';
        await Directory(target).create(recursive: true);
        await for (final FileSystemEntity f in entity.list()) {
          if (f is File) {
            await f.copy('$target/${f.path.split('/').last}');
          }
        }
      }
      await old.delete(recursive: true);
    } catch (_) {
      // 迁移失败时保留旧目录，不影响新任务
    }
  }

  /// 用系统「文件」应用打开任务所在目录，失败返回 false
  Future<bool> openFolder(DownloadTask t) async {
    if (!Platform.isAndroid) return false;
    try {
      return await _channel
              .invokeMethod<bool>('openFolder', {'path': taskDir(t)}) ??
          false;
    } catch (_) {
      return false;
    }
  }

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

  /// 哔哩哔哩官方客户端缓存的默认导入目录。
  /// 官方缓存位于 Android/data/tv.danmaku.bili/download，Android 11 起其他应用无法读取，
  /// 需先用系统文件管理器或 adb 移到此处
  Future<String?> biliImportDir() async {
    if (!Platform.isAndroid) return null;
    final String? download = await _channel.invokeMethod<String>('downloadDir');
    return download == null ? null : '$download/bilibili';
  }

  /// 按官方缓存结构 <avid>/c_<cid>/entry.json 导入，并把文件移动到本应用的缓存目录；
  /// 返回新增数量。已在列表中的视频不移动，留在原处。
  /// 读写其他应用写入的非媒体文件需要「所有文件访问权限」，由调用方先申请
  Future<int> importBiliCache(String root) async {
    await _ready;
    final Directory rootDir = Directory(root);
    if (!await rootDir.exists()) return 0;
    int count = 0;
    final List<Directory> avidDirs = await rootDir
        .list()
        .where((e) => e is Directory)
        .cast<Directory>()
        .toList();
    for (final Directory avidDir in avidDirs) {
      final List<Directory> pages = await avidDir
          .list()
          .where(
              (e) => e is Directory && e.path.split('/').last.startsWith('c_'))
          .cast<Directory>()
          .toList();
      for (final Directory page in pages) {
        final ({DownloadTask task, String qualityDir})? entry =
            await _parseBiliEntry(page, multiPage: pages.length > 1);
        if (entry == null || find(entry.task.bvid, entry.task.cid) != null) {
          continue;
        }
        if (await _moveBiliEntry(page, entry.qualityDir, entry.task)) {
          tasks.add(entry.task);
          // 逐个落盘，中途被杀时已移动的视频不会从列表丢失
          await GStrorage.download.put(entry.task.id, entry.task.toJson());
          count++;
        }
      }
      await _deleteIfEmpty(avidDir);
    }
    await _deleteIfEmpty(rootDir);
    tasks.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return count;
  }

  Future<({DownloadTask task, String qualityDir})?> _parseBiliEntry(
      Directory dir,
      {required bool multiPage}) async {
    try {
      final File entryFile = File('${dir.path}/entry.json');
      if (!await entryFile.exists()) return null;
      final Map entry = jsonDecode(await entryFile.readAsString());
      // 番剧（ep 不为空）的目录结构不同，暂不支持
      if (entry['is_completed'] != true || entry['ep'] != null) return null;
      final String qualityDir = '${dir.path}/${entry['type_tag']}';
      if (!await File('$qualityDir/video.m4s').exists()) return null;
      final DownloadTask task = _taskFromEntry(entry, multiPage: multiPage);
      return (task: task, qualityDir: qualityDir);
    } catch (_) {
      return null;
    }
  }

  DownloadTask _taskFromEntry(Map entry, {required bool multiPage}) {
    final Map page = entry['page_data'];
    final String bvid = (entry['bvid'] as String?)?.isNotEmpty == true
        ? entry['bvid']
        : IdUtils.av2bv(entry['avid']);
    final int bytes = entry['total_bytes'] ?? 0;
    return DownloadTask(
      bvid: bvid,
      cid: page['cid'],
      title: entry['title'] ?? bvid,
      partTitle: multiPage ? page['part'] : null,
      page: page['page'],
      ownerName: entry['owner_name'],
      cover: entry['cover'] ?? '',
      qn: entry['video_quality'] ?? 0,
      qnDesc: entry['quality_pithy_description'] ?? '',
      duration: (entry['total_time_milli'] ?? 0) ~/ 1000,
      width: page['width'],
      height: page['height'],
      totalBytes: bytes,
      receivedBytes: bytes,
      status: DownloadStatus.completed,
      hasAudio: entry['has_dash_audio'] ?? true,
      createdAt: entry['time_create_stamp'],
    );
  }

  /// 缓存列表存在应用私有数据里，重装或清除数据后会丢失而缓存目录仍在。
  /// 从目录中的 entry.json 重建列表里缺失的任务，返回恢复数量。
  /// 重装后旧文件属于原 UID，需要「所有文件访问权限」才能读取
  Future<int> recoverFromDisk() async {
    await _ready;
    final Directory root = Directory(_rootDir);
    if (!await root.exists()) return 0;
    final Set<String> known = tasks.map((t) => t.id).toSet();
    final List<Directory> dirs = await root
        .list()
        .where((e) => e is Directory && !known.contains(e.path.split('/').last))
        .cast<Directory>()
        .toList();
    final Map<String, Map> entries = {};
    for (final Directory dir in dirs) {
      try {
        final String name = dir.path.split('/').last;
        final File entryFile = File('${dir.path}/entry.json');
        if (!await entryFile.exists() ||
            !await File('${dir.path}/video.m4s').exists()) {
          continue;
        }
        entries[name] = jsonDecode(await entryFile.readAsString());
      } catch (_) {}
    }
    final Map<String, int> pageCount = {};
    for (final String name in entries.keys) {
      final String bvid = name.split('_').first;
      pageCount[bvid] = (pageCount[bvid] ?? 0) + 1;
    }
    final Map<String, Map<String, dynamic>> recovered = {};
    entries.forEach((name, entry) {
      try {
        final DownloadTask task = _taskFromEntry(entry,
            multiPage: (pageCount[name.split('_').first] ?? 0) > 1);
        // 目录名即任务 id，对不上时按 id 找不到文件
        if (task.id != name) return;
        tasks.add(task);
        recovered[task.id] = task.toJson();
      } catch (_) {}
    });
    if (recovered.isNotEmpty) {
      await GStrorage.download.putAll(recovered);
      tasks.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    }
    return recovered.length;
  }

  /// c_<cid> 整体重命名为任务目录，再把画质子目录里的音视频提到任务目录根部。
  /// 同在共享存储内，rename 不复制数据
  Future<bool> _moveBiliEntry(
      Directory src, String qualityDir, DownloadTask task) async {
    final String target = taskDir(task);
    if (await Directory(target).exists()) return false;
    final String movedQualityDir = '$target/${qualityDir.split('/').last}';
    final List<(File, String)> moves = [
      (File('$movedQualityDir/video.m4s'), videoPath(task)),
      (File('$movedQualityDir/audio.m4s'), audioPath(task)),
    ];
    try {
      await src.rename(target);
    } catch (_) {
      return false;
    }
    try {
      for (final (File from, String to) in moves) {
        if (await from.exists()) {
          await from.rename(to);
        }
      }
      await Directory(movedQualityDir).delete(recursive: true);
      return true;
    } catch (_) {
      // 回滚，让文件留在导入目录，避免在缓存目录里留下列表不认识的残缺目录
      try {
        await Directory(movedQualityDir).create();
        for (final (File from, String to) in moves) {
          if (await File(to).exists()) {
            await File(to).rename(from.path);
          }
        }
        await Directory(target).rename(src.path);
      } catch (_) {}
      return false;
    }
  }

  Future<void> _deleteIfEmpty(Directory dir) async {
    try {
      if (await dir.exists() && await dir.list().isEmpty) {
        await dir.delete();
      }
    } catch (_) {}
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
