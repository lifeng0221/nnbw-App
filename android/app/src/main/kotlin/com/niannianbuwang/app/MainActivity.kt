package com.niannianbuwang.app

import android.content.Intent
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
                    else -> result.notImplemented()
                }
            }
    }
}
