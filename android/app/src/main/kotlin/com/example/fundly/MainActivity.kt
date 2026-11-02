package com.example.fundly

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    // وقت التثبيت الأول وآخر تحديث: لتمييز «حذف ثم تثبيت» عن «تحديث».
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "fundly/install")
            .setMethodCallHandler { call, result ->
                if (call.method == "installTimes") {
                    try {
                        @Suppress("DEPRECATION")
                        val info = packageManager.getPackageInfo(packageName, 0)
                        result.success(
                            mapOf(
                                "first" to info.firstInstallTime,
                                "last" to info.lastUpdateTime
                            )
                        )
                    } catch (e: Exception) {
                        result.error("unavailable", e.message, null)
                    }
                } else {
                    result.notImplemented()
                }
            }
    }
}
