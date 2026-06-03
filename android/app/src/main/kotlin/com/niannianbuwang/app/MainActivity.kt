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
                    "stopAlarm" -> {
                        // v1.0.49: 停止原生MediaPlayer铃声
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
