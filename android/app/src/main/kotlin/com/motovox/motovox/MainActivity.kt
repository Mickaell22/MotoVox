package com.motovox.motovox

import android.content.Intent
import android.os.Build
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val channel = "com.motovox.motovox/app"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channel).setMethodCallHandler { call, result ->
            when (call.method) {
                "getApkPath" -> {
                    val apkPath = applicationInfo.sourceDir
                    result.success(apkPath)
                }
                "startCallService" -> {
                    val intent = Intent(this, CallService::class.java)
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                        startForegroundService(intent)
                    } else {
                        startService(intent)
                    }
                    result.success(null)
                }
                "stopCallService" -> {
                    stopService(Intent(this, CallService::class.java))
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
    }
}
