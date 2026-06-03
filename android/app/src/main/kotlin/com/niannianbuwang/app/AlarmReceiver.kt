package com.niannianbuwang.app

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.os.PowerManager

/**
 * 闹钟触发广播接收器 v1.0.51
 * 
 * 核心改动：
 * - 使用BroadcastReceiver代替直接启动Service
 * - BroadcastReceiver在Doze模式下仍能被AlarmManager唤醒
 * - onReceive中获取WakeLock，确保设备唤醒
 * - 启动前台服务播放铃声+发全屏通知
 */
class AlarmReceiver : BroadcastReceiver() {

    companion object {
        private const val TAG = "AlarmReceiver"
        private var wakeLock: PowerManager.WakeLock? = null
    }

    override fun onReceive(context: Context, intent: Intent) {
        android.util.Log.d(TAG, "收到闹钟广播! action=${intent.action}")

        val reminderId = intent.getStringExtra("reminder_id") ?: ""
        val content = intent.getStringExtra("reminder_content") ?: "提醒时间到了"

        android.util.Log.d(TAG, "闹钟详情: id=$reminderId, content=$content")

        // 1. 获取WakeLock唤醒CPU
        acquireWakeLock(context)

        // 2. 启动前台服务（带ALARM_TRIGGER action）
        try {
            val serviceIntent = Intent(context, ReminderForegroundService::class.java).apply {
                action = ReminderForegroundService.ACTION_ALARM_TRIGGER
                putExtra("reminder_id", reminderId)
                putExtra("reminder_content", content)
            }
            context.startForegroundService(serviceIntent)
            android.util.Log.d(TAG, "已启动前台服务处理闹钟")
        } catch (e: Exception) {
            android.util.Log.e(TAG, "启动前台服务失败，尝试直接播放", e)
            // 备用方案：直接播放铃声
            try {
                ReminderForegroundService.playAlarmFromFlutter(context)
            } catch (e2: Exception) {
                android.util.Log.e(TAG, "所有触发方案失败", e2)
            }
        }
    }

    private fun acquireWakeLock(context: Context) {
        try {
            if (wakeLock == null) {
                val pm = context.getSystemService(Context.POWER_SERVICE) as PowerManager
                wakeLock = pm.newWakeLock(
                    PowerManager.PARTIAL_WAKE_LOCK or PowerManager.ACQUIRE_CAUSES_WAKEUP,
                    "nnbw:AlarmReceiver"
                )
            }
            wakeLock?.acquire(60 * 1000L) // 最多持1分钟
            android.util.Log.d(TAG, "WakeLock已获取")
        } catch (e: Exception) {
            android.util.Log.e(TAG, "获取WakeLock失败", e)
        }
    }
}
