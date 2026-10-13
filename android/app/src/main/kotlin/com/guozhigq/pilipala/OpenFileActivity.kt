package com.guozhigq.pilipala

import android.app.Activity
import android.content.Intent
import android.os.Bundle

// 文件管理器的「打开方式」会把目标 Activity 启动在它自己的任务栈里，
// 直接用 MainActivity 接收会多出一个共享播放器引擎的实例；这里转交给应用自身的任务栈
class OpenFileActivity : Activity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        startActivity(
            Intent(this, MainActivity::class.java)
                .setAction(Intent.ACTION_VIEW)
                .setDataAndType(intent.data, intent.type)
                .addFlags(
                    Intent.FLAG_ACTIVITY_NEW_TASK or
                        Intent.FLAG_ACTIVITY_SINGLE_TOP or
                        Intent.FLAG_GRANT_READ_URI_PERMISSION
                )
        )
        finish()
    }
}
