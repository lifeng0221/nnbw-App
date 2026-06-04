package com.niannianbuwang.app

import android.content.Intent
import android.os.Build
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {

    companion object {
        private const val CHANNEL = "com.niannianbuwang.app/reminder_service"
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "startService" -> {
                        try {
                            ReminderForegroundService.start(this)
                            result.success(true)
                        } catch (e: Exception) {
                            result.error("START_FAILED", e.message, null)
                        }
                    }
                    "stopService" -> {
                        try {
                            ReminderForegroundService.stop(this)
                            result.success(true)
                        } catch (e: Exception) {
                            result.error("STOP_FAILED", e.message, null)
                        }
                    }
                    "playAlarm" -> {
                        try {
                            val content = call.argument<String>("content") ?: "提醒时间到了"
                            val intent = Intent(this, ReminderForegroundService::class.java).apply {
                                action = "PLAY_ALARM"
                                putExtra("reminder_content", content)
                            }
                            startService(intent)
                            result.success(true)
                        } catch (e: Exception) {
                            result.error("PLAY_ALARM_FAILED", e.message, null)
                        }
                    }
                    "stopAlarm" -> {
                        try {
                            ReminderForegroundService.stopAlarmSound()
                            result.success(true)
                        } catch (e: Exception) {
                            result.error("STOP_ALARM_FAILED", e.message, null)
                        }
                    }
                    "isServiceRunning" -> {
                        result.success(true)
                    }
                    // v1.0.51: Flutter通知Kotlin立即调度所有未来闹钟
                    "scheduleAlarms" -> {
                        try {
                            val intent = Intent(this, ReminderForegroundService::class.java).apply {
                                action = "com.niannianbuwang.app.SCHEDULE_ALL"
                            }
                            startService(intent)
                            android.util.Log.d("MainActivity", "已请求调度全部闹钟")
                            result.success(true)
                        } catch (e: Exception) {
                            android.util.Log.e("MainActivity", "调度闹钟失败", e)
                            result.error("SCHEDULE_FAILED", e.message, null)
                        }
                    }
                    // v1.0.55: 打开电池设置页面
                    "openBatterySettings" -> {
                        try {
                            val intentString = call.argument<String>("intent")
                            if (intentString != null) {
                                val intent = Intent().apply {
                                    setClassName("com.android.settings", intentString)
                                    addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                                }
                                try {
                                    startActivity(intent)
                                    result.success(true)
                                } catch (e: Exception) {
                                    // Intent失败，尝试package方式
                                    val packageName = call.argument<String>("package")
                                    if (packageName != null) {
                                        val pkgIntent = Intent().apply {
                                            action = android.provider.Settings.ACTION_APPLICATION_DETAILS_SETTINGS
                                            data = android.net.Uri.parse("package:$packageName")
                                            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                                        }
                                        startActivity(pkgIntent)
                                        result.success(true)
                                    } else {
                                        result.error("OPEN_FAILED", "无法打开电池设置", null)
                                    }
                                }
                            } else {
                                result.error("INVALID_ARGUMENT", "缺少intent参数", null)
                            }
                        } catch (e: Exception) {
                            android.util.Log.e("MainActivity", "打开电池设置失败", e)
                            result.error("OPEN_FAILED", e.message, null)
                        }
                    }
                    else -> result.notImplemented()
                }
            }
    }
}
