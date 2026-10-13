import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:get/get.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:pilipala/models/download/download_task.dart';
import 'package:pilipala/services/download_service.dart';

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
            return ListView.builder(
              itemCount: tasks.length,
              padding: EdgeInsets.only(
                  bottom: MediaQuery.of(context).padding.bottom + 12),
              itemBuilder: (context, index) =>
                  _DownloadItem(task: tasks[index], service: service),
            );
          });
        },
      ),
    );
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
        '将读取 $dir 中的官方客户端缓存，文件保留在原处。\n\n'
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
  const _DownloadItem({required this.task, required this.service});

  final DownloadTask task;
  final DownloadService service;

  static String _size(int bytes) {
    if (bytes <= 0) return '0MB';
    final double mb = bytes / 1024 / 1024;
    return mb >= 1024
        ? '${(mb / 1024).toStringAsFixed(2)}GB'
        : '${mb.toStringAsFixed(1)}MB';
  }

  String get _statusText {
    switch (task.status) {
      case DownloadStatus.completed:
        return '${task.qnDesc} · ${_size(task.totalBytes)}';
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
    final File cover = File(service.coverPath(task));
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
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: SizedBox(
                width: 128,
                height: 72,
                child: cover.existsSync()
                    ? Image.file(cover, fit: BoxFit.cover)
                    : Container(
                        color: colorScheme.onInverseSurface,
                        child: Icon(Icons.movie_outlined,
                            color: colorScheme.outline),
                      ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    task.title,
                    maxLines: task.partTitle == null ? 2 : 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 14),
                  ),
                  if (task.partTitle != null)
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
