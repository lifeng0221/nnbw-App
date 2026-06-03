package com.niannianbuwang.app

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent

/**
 * 开机自启广播接收器 v1.0.51
 * 
 * 设备重启后重新调度AlarmManager闹钟
 */
class BootReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action == Intent.ACTION_BOOT_COMPLETED || 
            intent.action == "android.intent.action.LOCKED_BOOT_COMPLETED") {
            android.util.Log.d("BootReceiver", "设备启动完成，重新启动闹钟服务")
            try {
                ReminderForegroundService.start(context)
            } catch (e: Exception) {
                android.util.Log.e("BootReceiver", "启动服务失败", e)
            }
        }
    }
}
