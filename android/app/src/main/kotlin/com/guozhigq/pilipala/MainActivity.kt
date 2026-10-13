package com.guozhigq.pilipala

// import io.flutter.embedding.android.FlutterActivity
import android.content.Intent
import android.net.Uri
import android.os.Environment
import android.provider.DocumentsContract
import com.ryanheise.audioservice.AudioServiceFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity: AudioServiceFragmentActivity() {
    private var fileChannel: MethodChannel? = null
    // 冷启动时 Flutter 尚未注册监听，先暂存，由 Dart 主动取走
    private var pendingFile: Map<String, String?>? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        pendingFile = resolveOpenedFile(intent)
        fileChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "pilipala/file")
        fileChannel!!.setMethodCallHandler { call, result ->
            when (call.method) {
                "downloadDir" -> result.success(
                    Environment.getExternalStoragePublicDirectory(
                        Environment.DIRECTORY_DOWNLOADS
                    ).absolutePath
                )
                "openFolder" -> result.success(openFolder(call.argument<String>("path")!!))
                "takeOpenedFile" -> {
                    result.success(pendingFile)
                    pendingFile = null
                }
                else -> result.notImplemented()
            }
        }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        val file = resolveOpenedFile(intent) ?: return
        fileChannel?.invokeMethod("fileOpened", file)
    }

    // 文件管理器「打开方式」传入的视频文件，返回 {uri, path}；path 无法推断时为 null
    private fun resolveOpenedFile(intent: Intent?): Map<String, String?>? {
        if (intent?.action != Intent.ACTION_VIEW) return null
        val uri = intent.data ?: return null
        if (uri.scheme != "file" && uri.scheme != "content") return null
        return mapOf("uri" to uri.toString(), "path" to pathOf(uri))
    }

    private fun pathOf(uri: Uri): String? {
        val root = Environment.getExternalStorageDirectory().absolutePath
        if (uri.scheme == "file") return uri.path
        // 系统「文件」应用：document id 形如 primary:Download/xxx
        if (uri.authority == "com.android.externalstorage.documents") {
            val docId = DocumentsContract.getDocumentId(uri)
            if (docId.startsWith("primary:")) return "$root/${docId.removePrefix("primary:")}"
        }
        // 各家文件管理器的 FileProvider 通常把绝对路径拼在 uri path 里
        val path = Uri.decode(uri.path ?: return null)
        val index = path.indexOf(root)
        return if (index >= 0) path.substring(index) else null
    }

    // 通过系统「文件」应用打开共享存储中的目录；无可用应用时返回 false
    private fun openFolder(path: String): Boolean {
        val root = Environment.getExternalStorageDirectory().absolutePath
        if (!path.startsWith(root)) return false
        val relative = path.removePrefix(root).trimStart('/')
        val uri = DocumentsContract.buildDocumentUri(
            "com.android.externalstorage.documents", "primary:$relative"
        )
        val intent = Intent(Intent.ACTION_VIEW)
            .setDataAndType(uri, DocumentsContract.Document.MIME_TYPE_DIR)
            .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        return try {
            startActivity(intent)
            true
        } catch (e: Exception) {
            false
        }
    }
}
