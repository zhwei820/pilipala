enum DownloadStatus { waiting, downloading, paused, completed, failed }

class DownloadTask {
  DownloadTask({
    required this.bvid,
    required this.cid,
    required this.title,
    this.partTitle,
    required this.cover,
    required this.qn,
    required this.qnDesc,
    this.duration = 0,
    this.width,
    this.height,
    this.totalBytes = 0,
    this.receivedBytes = 0,
    this.status = DownloadStatus.waiting,
    this.error,
    this.hasAudio = true,
    int? createdAt,
  }) : createdAt = createdAt ?? DateTime.now().millisecondsSinceEpoch;

  final String bvid;
  final int cid;
  final String title;
  // 多P视频的分P标题，单P为null
  final String? partTitle;
  final String cover;
  final int qn;
  final String qnDesc;
  final int duration;
  int? width;
  int? height;
  int totalBytes;
  int receivedBytes;
  DownloadStatus status;
  String? error;
  // durl 单文件流没有独立音轨
  bool hasAudio;
  final int createdAt;

  String get id => '${bvid}_$cid';

  double get progress =>
      totalBytes > 0 ? (receivedBytes / totalBytes).clamp(0.0, 1.0) : 0;

  Map<String, dynamic> toJson() => {
        'bvid': bvid,
        'cid': cid,
        'title': title,
        'partTitle': partTitle,
        'cover': cover,
        'qn': qn,
        'qnDesc': qnDesc,
        'duration': duration,
        'width': width,
        'height': height,
        'totalBytes': totalBytes,
        'receivedBytes': receivedBytes,
        'status': status.name,
        'error': error,
        'hasAudio': hasAudio,
        'createdAt': createdAt,
      };

  factory DownloadTask.fromJson(Map json) => DownloadTask(
        bvid: json['bvid'],
        cid: json['cid'],
        title: json['title'],
        partTitle: json['partTitle'],
        cover: json['cover'] ?? '',
        qn: json['qn'],
        qnDesc: json['qnDesc'] ?? '',
        duration: json['duration'] ?? 0,
        width: json['width'],
        height: json['height'],
        totalBytes: json['totalBytes'] ?? 0,
        receivedBytes: json['receivedBytes'] ?? 0,
        status: DownloadStatus.values.firstWhere(
          (e) => e.name == json['status'],
          orElse: () => DownloadStatus.paused,
        ),
        error: json['error'],
        hasAudio: json['hasAudio'] ?? true,
        createdAt: json['createdAt'],
      );
}
