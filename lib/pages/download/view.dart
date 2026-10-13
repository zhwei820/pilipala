import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:get/get.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:pilipala/models/download/download_task.dart';
import 'package:pilipala/services/download_service.dart';
import 'package:pilipala/utils/utils.dart';

class DownloadPage extends StatelessWidget {
  const DownloadPage({super.key});

  @override
  Widget build(BuildContext context) {
    final DownloadService service = DownloadService.to;
    return Scaffold(
      appBar: AppBar(
        title: const Text('离线缓存'),
        actions: [
          if (Platform.isAndroid)
            IconButton(
              tooltip: '从缓存目录恢复列表',
              onPressed: () => _recoverFromDisk(service),
              icon: const Icon(Icons.restore),
            ),
          if (Platform.isAndroid)
            IconButton(
              tooltip: '导入哔哩哔哩缓存',
              onPressed: () => _importBiliCache(context, service),
              icon: const Icon(Icons.drive_folder_upload_outlined),
            ),
          const SizedBox(width: 6),
        ],
      ),
      body: FutureBuilder(
        future: service.ready,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          return Obx(() {
            final List<DownloadTask> tasks = service.tasks.toList();
            if (tasks.isEmpty) {
              return Center(
                child: Text(
                  '暂无缓存\n在视频播放页右上角「更多」中选择「离线缓存」',
                  textAlign: TextAlign.center,
                  style:
                      TextStyle(color: Theme.of(context).colorScheme.outline),
                ),
              );
            }
            final List<List<DownloadTask>> groups = _groupByVideo(tasks);
            return ListView.builder(
              itemCount: groups.length,
              padding: EdgeInsets.only(
                  bottom: MediaQuery.of(context).padding.bottom + 12),
              itemBuilder: (context, index) => groups[index].length == 1
                  ? _DownloadItem(task: groups[index].first, service: service)
                  : _GroupItem(tasks: groups[index], service: service),
            );
          });
        },
      ),
    );
  }
}

/// 同一视频的多个分P合为一组；组按最近加入的分P排序，组内按分P序号排序
List<List<DownloadTask>> _groupByVideo(List<DownloadTask> tasks) {
  final Map<String, List<DownloadTask>> groups = {};
  for (final DownloadTask t in tasks) {
    groups.putIfAbsent(t.bvid, () => []).add(t);
  }
  for (final List<DownloadTask> g in groups.values) {
    g.sort(_byPage);
  }
  return groups.values.toList();
}

int _byPage(DownloadTask a, DownloadTask b) {
  if (a.page != null && b.page != null) return a.page!.compareTo(b.page!);
  if (a.page != null) return -1;
  if (b.page != null) return 1;
  return a.createdAt.compareTo(b.createdAt);
}

String _size(int bytes) {
  if (bytes <= 0) return '0MB';
  final double mb = bytes / 1024 / 1024;
  return mb >= 1024
      ? '${(mb / 1024).toStringAsFixed(2)}GB'
      : '${mb.toStringAsFixed(1)}MB';
}

Widget _cover(BuildContext context, DownloadService service, DownloadTask t) {
  final ColorScheme colorScheme = Theme.of(context).colorScheme;
  final File cover = File(service.coverPath(t));
  return ClipRRect(
    borderRadius: BorderRadius.circular(6),
    child: SizedBox(
      width: 128,
      height: 72,
      child: cover.existsSync()
          ? Image.file(cover, fit: BoxFit.cover)
          : Container(
              color: colorScheme.onInverseSurface,
              child: Icon(Icons.movie_outlined, color: colorScheme.outline),
            ),
    ),
  );
}

class _GroupItem extends StatelessWidget {
  const _GroupItem({required this.tasks, required this.service});

  final List<DownloadTask> tasks;
  final DownloadService service;

  String get _statusText {
    final int done =
        tasks.where((t) => t.status == DownloadStatus.completed).length;
    final int size = tasks.fold(0, (sum, t) => sum + t.totalBytes);
    if (done == tasks.length) return '${tasks.length}个视频 · ${_size(size)}';
    final bool downloading =
        tasks.any((t) => t.status == DownloadStatus.downloading);
    return '${downloading ? '缓存中' : '未完成'} · 已完成 $done/${tasks.length}';
  }

  void _confirmDeleteAll(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('删除缓存'),
        content: Text('确定删除「${tasks.first.title}」的全部 ${tasks.length} 个分P吗？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text('取消',
                style: TextStyle(color: Theme.of(context).colorScheme.outline)),
          ),
          TextButton(
            onPressed: () {
              Navigator.of(context).pop();
              for (final DownloadTask t in tasks) {
                service.remove(t);
              }
            },
            child: const Text('删除'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final ColorScheme colorScheme = Theme.of(context).colorScheme;
    final DownloadTask first = tasks.first;
    return InkWell(
      onTap: () => Get.toNamed('/downloadGroup', arguments: first.bvid),
      onLongPress: () => _confirmDeleteAll(context),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 8, 6, 8),
        child: Row(
          children: [
            Stack(
              children: [
                _cover(context, service, first),
                Positioned(
                  right: 4,
                  bottom: 4,
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                    decoration: BoxDecoration(
                      color: Colors.black54,
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      '${tasks.length}P',
                      style: const TextStyle(color: Colors.white, fontSize: 11),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    first.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 14),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    [
                      if (first.ownerName != null) first.ownerName!,
                      _statusText,
                    ].join(' · '),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 12, color: colorScheme.outline),
                  ),
                ],
              ),
            ),
            Icon(Icons.chevron_right, color: colorScheme.outline),
            const SizedBox(width: 8),
          ],
        ),
      ),
    );
  }
}

/// 多P视频的分P列表
class DownloadGroupPage extends StatelessWidget {
  const DownloadGroupPage({super.key});

  @override
  Widget build(BuildContext context) {
    final DownloadService service = DownloadService.to;
    final String bvid = Get.arguments;
    bool popped = false;
    return Obx(() {
      final List<DownloadTask> parts =
          service.tasks.where((t) => t.bvid == bvid).toList()..sort(_byPage);
      if (parts.isEmpty) {
        // 全部删除后返回上一页；Obx 可能多次重建，只返回一次
        if (!popped) {
          popped = true;
          WidgetsBinding.instance.addPostFrameCallback((_) => Get.back());
        }
        return const Scaffold();
      }
      return Scaffold(
        appBar: AppBar(
          title: Text(parts.first.title,
              maxLines: 1, overflow: TextOverflow.ellipsis),
        ),
        body: ListView.builder(
          itemCount: parts.length,
          padding: EdgeInsets.only(
              bottom: MediaQuery.of(context).padding.bottom + 12),
          itemBuilder: (context, index) => _DownloadItem(
              task: parts[index], service: service, inGroup: true),
        ),
      );
    });
  }
}

Future<void> _recoverFromDisk(DownloadService service) async {
  if (!await Permission.manageExternalStorage.request().isGranted) {
    SmartDialog.showToast('未授予所有文件访问权限');
    return;
  }
  SmartDialog.showLoading(msg: '正在恢复');
  try {
    final int count = await service.recoverFromDisk();
    SmartDialog.showToast(count > 0 ? '已恢复 $count 个视频' : '没有可恢复的视频');
  } finally {
    SmartDialog.dismiss(status: SmartStatus.loading);
  }
}

Future<void> _importBiliCache(
    BuildContext context, DownloadService service) async {
  final String? dir = await service.biliImportDir();
  if (dir == null || !context.mounted) return;
  final bool? confirmed = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('导入哔哩哔哩缓存'),
      content: Text(
        '将把 $dir 中的官方客户端缓存移动到 PiliPala 缓存目录。\n\n'
        '官方缓存位于 Android/data/tv.danmaku.bili/download，系统不允许其他应用直接读取，'
        '请先用文件管理器把其中的文件夹移动到上述目录。\n\n'
        '读取需要「所有文件访问权限」。',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: Text('取消',
              style: TextStyle(color: Theme.of(context).colorScheme.outline)),
        ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(true),
          child: const Text('导入'),
        ),
      ],
    ),
  );
  if (confirmed != true) return;
  if (!await Permission.manageExternalStorage.request().isGranted) {
    SmartDialog.showToast('未授予所有文件访问权限');
    return;
  }
  SmartDialog.showLoading(msg: '正在导入');
  try {
    final int count = await service.importBiliCache(dir);
    SmartDialog.showToast(count > 0 ? '已导入 $count 个视频' : '没有可导入的新视频');
  } finally {
    SmartDialog.dismiss(status: SmartStatus.loading);
  }
}

class _DownloadItem extends StatelessWidget {
  const _DownloadItem(
      {required this.task, required this.service, this.inGroup = false});

  final DownloadTask task;
  final DownloadService service;
  // 分P列表中只显示分P信息，不重复显示封面和视频标题
  final bool inGroup;

  String get _statusText {
    switch (task.status) {
      case DownloadStatus.completed:
        return [
          task.qnDesc,
          if (task.duration > 0) Utils.timeFormat(task.duration),
          _size(task.totalBytes),
        ].join(' · ');
      case DownloadStatus.downloading:
        return '${_size(task.receivedBytes)} / ${_size(task.totalBytes)}';
      case DownloadStatus.waiting:
        return '等待中';
      case DownloadStatus.paused:
        return '已暂停 · ${(task.progress * 100).toStringAsFixed(0)}%';
      case DownloadStatus.failed:
        return '失败：${task.error ?? '未知错误'}';
    }
  }

  void _onTap() {
    switch (task.status) {
      case DownloadStatus.completed:
        Get.toNamed('/downloadPlayer', arguments: task);
        break;
      case DownloadStatus.downloading:
      case DownloadStatus.waiting:
        service.pause(task);
        break;
      case DownloadStatus.paused:
      case DownloadStatus.failed:
        service.resume(task);
        break;
    }
  }

  void _showMenu(BuildContext context) {
    showModalBottomSheet(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.folder_open_outlined),
              title: const Text('打开存储位置'),
              onTap: () async {
                Navigator.of(context).pop();
                if (!await service.openFolder(task)) {
                  _showPath();
                }
              },
            ),
            ListTile(
              leading: const Icon(Icons.copy_outlined),
              title: const Text('复制存储路径'),
              onTap: () {
                Navigator.of(context).pop();
                Clipboard.setData(ClipboardData(text: service.taskDir(task)));
                SmartDialog.showToast('已复制');
              },
            ),
            ListTile(
              leading: const Icon(Icons.delete_outline),
              title: const Text('删除缓存'),
              onTap: () {
                Navigator.of(context).pop();
                _confirmDelete(Get.context!);
              },
            ),
          ],
        ),
      ),
    );
  }

  void _showPath() {
    final String path = service.taskDir(task);
    SmartDialog.show(
      builder: (context) => AlertDialog(
        title: const Text('存储位置'),
        content: SelectableText(path),
        actions: [
          TextButton(
            onPressed: () {
              Clipboard.setData(ClipboardData(text: path));
              SmartDialog.dismiss();
              SmartDialog.showToast('已复制');
            },
            child: const Text('复制'),
          ),
        ],
      ),
    );
  }

  void _confirmDelete(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('删除缓存'),
        content: Text('确定删除「${task.title}」的缓存吗？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text('取消',
                style: TextStyle(color: Theme.of(context).colorScheme.outline)),
          ),
          TextButton(
            onPressed: () {
              Navigator.of(context).pop();
              service.remove(task);
            },
            child: const Text('删除'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final ColorScheme colorScheme = Theme.of(context).colorScheme;
    final IconData? actionIcon = switch (task.status) {
      DownloadStatus.downloading || DownloadStatus.waiting => Icons.pause,
      DownloadStatus.paused => Icons.download_outlined,
      DownloadStatus.failed => Icons.refresh,
      DownloadStatus.completed => null,
    };
    return InkWell(
      onTap: _onTap,
      onLongPress: () => _showMenu(context),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 8, 6, 8),
        child: Row(
          children: [
            if (inGroup)
              SizedBox(
                width: 44,
                child: Text(
                  'P${task.page ?? '-'}',
                  style: TextStyle(fontSize: 13, color: colorScheme.outline),
                ),
              )
            else
              _cover(context, service, task),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    inGroup ? (task.partTitle ?? task.title) : task.title,
                    maxLines: task.partTitle == null || inGroup ? 2 : 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 14),
                  ),
                  if (!inGroup && task.partTitle != null)
                    Text(
                      task.partTitle!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style:
                          TextStyle(fontSize: 12, color: colorScheme.outline),
                    ),
                  const SizedBox(height: 6),
                  if (task.status != DownloadStatus.completed) ...[
                    LinearProgressIndicator(
                      value: task.totalBytes > 0 ? task.progress : null,
                      minHeight: 2,
                    ),
                    const SizedBox(height: 4),
                  ],
                  Text(
                    _statusText,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12,
                      color: task.status == DownloadStatus.failed
                          ? colorScheme.error
                          : colorScheme.outline,
                    ),
                  ),
                ],
              ),
            ),
            if (actionIcon != null)
              IconButton(onPressed: _onTap, icon: Icon(actionIcon))
            else
              IconButton(
                onPressed: () => _confirmDelete(context),
                icon: Icon(Icons.delete_outline, color: colorScheme.outline),
              ),
          ],
        ),
      ),
    );
  }
}
