package com.niannianbuwang.app

import android.app.*
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.media.AudioAttributes
import android.media.MediaPlayer
import android.media.RingtoneManager
import android.os.Build
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import android.os.PowerManager
import androidx.core.app.NotificationCompat
import androidx.core.content.ContextCompat
import org.json.JSONArray
import java.text.SimpleDateFormat
import java.util.*

/**
 * 原生前台服务 — 念念不忘提醒守护 v1.0.49
 * 
 * 核心改动（v1.0.49）：
 * - 铃声播放改用MediaPlayer + USAGE_ALARM，息屏/Doze下也能响
 * - 添加WakeLock确保CPU运行
 * - 添加AlarmManager精确调度（setExactAndAllowWhileIdle）
 * - 通知渠道不再设铃声（由MediaPlayer负责），避免Doze下被静音
 * - 通知添加"停止铃声"按钮
 * - Flutter侧可通过MethodChannel停止原生铃声
 */
class ReminderForegroundService : Service() {

    companion object {
        private const val TAG = "ReminderService"
        private const val CHANNEL_ID = "nnbw_foreground_service"
        private const val REMINDER_CHANNEL_ID = "nnbw_reminder_alarm"
        private const val NOTIFICATION_ID = 10001
        private const val REMINDER_NOTIFICATION_ID_START = 20000
        private const val PREFS_NAME = "FlutterSharedPreferences"
        private const val FLUTTER_PREFIX = "flutter."
        private const val CHECK_INTERVAL_MS = 30_000L // 30秒轮询（AlarmManager负责精确时间）
        private const val TRIGGER_WINDOW_MS = 2 * 60 * 60 * 1000L // 触发窗口2小时
        private const val ACTION_STOP_ALARM = "com.niannianbuwang.app.STOP_ALARM"
        private const val ACTION_ALARM_TRIGGER = "com.niannianbuwang.app.ALARM_TRIGGER"
        private const val EXTRA_REMINDER_ID = "reminder_id"
        private const val EXTRA_REMINDER_CONTENT = "reminder_content"

        private val triggeredIds = mutableSetOf<String>()
        private var alarmMediaPlayer: MediaPlayer? = null
        private var wakeLock: PowerManager.WakeLock? = null
        private var screenWakeLock: PowerManager.WakeLock? = null

        fun start(context: Context) {
            val intent = Intent(context, ReminderForegroundService::class.java)
            intent.action = "START"
            ContextCompat.startForegroundService(context, intent)
        }

        fun stop(context: Context) {
            val intent = Intent(context, ReminderForegroundService::class.java)
            intent.action = "STOP"
            context.startService(intent)
        }
        
        /** 停止原生闹钟铃声（供MethodChannel调用） */
        fun stopAlarmSound() {
            try {
                alarmMediaPlayer?.let {
                    if (it.isPlaying) it.stop()
                    it.release()
                }
                alarmMediaPlayer = null
            } catch (e: Exception) {
                android.util.Log.e(TAG, "停止铃声异常", e)
            }
            releaseWakeLocks()
            android.util.Log.d(TAG, "原生铃声已停止")
        }
        
        private fun releaseWakeLocks() {
            try {
                wakeLock?.let { if (it.isHeld) it.release() }
                wakeLock = null
            } catch (e: Exception) { }
            try {
                screenWakeLock?.let { if (it.isHeld) it.release() }
                screenWakeLock = null
            } catch (e: Exception) { }
        }
    }

    private val handler = Handler(Looper.getMainLooper())
    private var isRunning = false
    private val alarmManager by lazy { getSystemService(Context.ALARM_SERVICE) as AlarmManager }

    private val checkRunnable = object : Runnable {
        override fun run() {
            if (!isRunning) return
            try {
                checkReminders()
            } catch (e: Exception) {
                android.util.Log.e(TAG, "检查提醒出错", e)
            }
            handler.postDelayed(this, CHECK_INTERVAL_MS)
        }
    }

    override fun onCreate() {
        super.onCreate()
        android.util.Log.d(TAG, "服务onCreate")
        createNotificationChannels()
        
        val filter = IntentFilter(ACTION_STOP_ALARM)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            registerReceiver(stopAlarmReceiver, filter, Context.RECEIVER_NOT_EXPORTED)
        } else {
            registerReceiver(stopAlarmReceiver, filter)
        }
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        android.util.Log.d(TAG, "服务onStartCommand, action=${intent?.action}")

        // 处理AlarmManager触发的提醒
        if (intent?.action == ACTION_ALARM_TRIGGER) {
            val reminderId = intent.getStringExtra(EXTRA_REMINDER_ID) ?: ""
            val content = intent.getStringExtra(EXTRA_REMINDER_CONTENT) ?: "提醒"
            if (!triggeredIds.contains(reminderId)) {
                android.util.Log.d(TAG, "AlarmManager触发提醒: $content")
                playAlarmSound()
                showReminderNotification(reminderId, content, "normal")
                markReminderTriggered(reminderId)
                triggeredIds.add(reminderId)
            }
            return START_STICKY
        }

        if (intent?.action == "STOP") {
            stopAlarmSound()
            stopSelf()
            return START_NOT_STICKY
        }

        if (isRunning) {
            android.util.Log.d(TAG, "服务已在运行")
            return START_STICKY
        }

        startForeground(NOTIFICATION_ID, createForegroundNotification())

        isRunning = true
        handler.post(checkRunnable)

        android.util.Log.d(TAG, "前台服务已启动，开始轮询提醒")
        return START_STICKY
    }

    override fun onDestroy() {
        super.onDestroy()
        isRunning = false
        handler.removeCallbacks(checkRunnable)
        stopAlarmSound()
        try {
            unregisterReceiver(stopAlarmReceiver)
        } catch (e: Exception) { }
        android.util.Log.d(TAG, "服务已销毁")
    }

    override fun onBind(intent: Intent?): IBinder? = null

    private val stopAlarmReceiver = object : BroadcastReceiver() {
        override fun onReceive(context: Context?, intent: Intent?) {
            if (intent?.action == ACTION_STOP_ALARM) {
                android.util.Log.d(TAG, "收到停止铃声广播")
                stopAlarmSound()
            }
        }
    }

    private fun createNotificationChannels() {
        val manager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val serviceChannel = NotificationChannel(
                CHANNEL_ID,
                "守护服务",
                NotificationManager.IMPORTANCE_LOW
            ).apply {
                description = "念念不忘后台守护服务"
                setShowBadge(false)
            }
            manager.createNotificationChannel(serviceChannel)

            // 提醒闹钟通知渠道 — 不设铃声（由MediaPlayer负责），避免Doze静音
            val reminderChannel = NotificationChannel(
                REMINDER_CHANNEL_ID,
                "提醒闹钟",
                NotificationManager.IMPORTANCE_HIGH
            ).apply {
                description = "到点提醒，锁屏时也会响铃弹出"
                enableVibration(true)
                vibrationPattern = longArrayOf(0, 500, 200, 500, 200, 500)
                lockscreenVisibility = Notification.VISIBILITY_PUBLIC
                // 关键：不设铃声！由MediaPlayer+USAGE_ALARM播放，通知铃声在Doze下会被静音
                setSound(null, null)
            }
            manager.createNotificationChannel(reminderChannel)
        }
    }

    private fun createForegroundNotification(): Notification {
        val intent = packageManager.getLaunchIntentForPackage(packageName)
        val pendingIntent = PendingIntent.getActivity(
            this, 0, intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        return NotificationCompat.Builder(this, CHANNEL_ID)
            .setContentTitle("念念不忘")
            .setContentText("守护服务运行中，确保提醒准时触发")
            .setSmallIcon(android.R.drawable.ic_lock_idle_alarm)
            .setOngoing(true)
            .setContentIntent(pendingIntent)
            .setPriority(NotificationCompat.PRIORITY_LOW)
            .build()
    }

    /** 
     * 播放闹钟铃声 — v1.0.49核心改动
     * MediaPlayer + USAGE_ALARM + WakeLock，息屏/Doze下也能响
     */
    private fun playAlarmSound() {
        try {
            // 1. 停止旧铃声
            try {
                alarmMediaPlayer?.let {
                    if (it.isPlaying) it.stop()
                    it.release()
                }
                alarmMediaPlayer = null
            } catch (e: Exception) { }
            
            // 2. 获取WakeLock确保CPU运行
            val powerManager = getSystemService(Context.POWER_SERVICE) as PowerManager
            releaseWakeLocks()
            
            wakeLock = powerManager.newWakeLock(
                PowerManager.PARTIAL_WAKE_LOCK,
                "nnbw:ReminderAlarm"
            )
            wakeLock?.acquire(5 * 60 * 1000L) // 最多5分钟
            
            // 3. 点亮屏幕（FULL_WAKE_LOCK在新版已废弃，用SCREEN_BRIGHT_WAKE_LOCK兼容旧版）
            @Suppress("DEPRECATION")
            screenWakeLock = powerManager.newWakeLock(
                PowerManager.SCREEN_BRIGHT_WAKE_LOCK or PowerManager.ACQUIRE_CAUSES_WAKEUP,
                "nnbw:ReminderScreen"
            )
            screenWakeLock?.acquire(30 * 1000L) // 亮屏30秒
            
            android.util.Log.d(TAG, "WakeLock已获取(PARTIAL+SCREEN)")
            
            // 4. MediaPlayer播放系统闹钟铃声
            val alarmSound = RingtoneManager.getDefaultUri(RingtoneManager.TYPE_ALARM)
                ?: RingtoneManager.getDefaultUri(RingtoneManager.TYPE_NOTIFICATION)
                ?: RingtoneManager.getDefaultUri(RingtoneManager.TYPE_RINGTONE)
            
            alarmMediaPlayer = MediaPlayer().apply {
                setAudioAttributes(
                    AudioAttributes.Builder()
                        .setUsage(AudioAttributes.USAGE_ALARM)  // 闹钟级别，Doze下也能响
                        .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
                        .build()
                )
                setDataSource(this@ReminderForegroundService, alarmSound)
                isLooping = true  // 循环播放直到用户确认
                setVolume(1.0f, 1.0f)  // 最大音量
                prepare()
                start()
            }
            
            android.util.Log.d(TAG, "✅ 闹钟铃声已开始播放（MediaPlayer+USAGE_ALARM+循环）")
        } catch (e: Exception) {
            android.util.Log.e(TAG, "MediaPlayer播放失败，尝试Ringtone备用方案", e)
            try {
                val alarmSound = RingtoneManager.getDefaultUri(RingtoneManager.TYPE_ALARM)
                val ringtone = RingtoneManager.getRingtone(this, alarmSound)
                ringtone.audioAttributes = AudioAttributes.Builder()
                    .setUsage(AudioAttributes.USAGE_ALARM)
                    .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
                    .build()
                ringtone.play()
                android.util.Log.d(TAG, "备用Ringtone方案已启动")
            } catch (e2: Exception) {
                android.util.Log.e(TAG, "所有铃声方案都失败", e2)
            }
        }
    }

    private fun checkReminders() {
        val prefs = getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
        val now = System.currentTimeMillis()

        val allKeys = prefs.all.keys.filter { 
            it.startsWith("${FLUTTER_PREFIX}reminders") 
        }
        var triggeredCount = 0

        for (key in allKeys) {
            val jsonStr = prefs.getString(key, null) ?: continue
            try {
                val jsonArray = JSONArray(jsonStr)
                var needsSave = false

                for (i in 0 until jsonArray.length()) {
                    val obj = jsonArray.getJSONObject(i)
                    val reminderId = obj.optString("reminder_id", "")
                    val status = obj.optString("status", "")

                    if (status != "pending" && status != "snoozed") continue
                    if (triggeredIds.contains(reminderId)) continue

                    val triggerTimeStr = obj.optString("trigger_time", "")
                    if (triggerTimeStr.isEmpty()) continue

                    try {
                        val triggerTime = parseIsoTime(triggerTimeStr)
                        val diff = now - triggerTime
                        val content = obj.optString("content", "提醒")  // 提前声明，避免作用域问题

                        if (diff >= 0) {
                            if (diff <= TRIGGER_WINDOW_MS) {
                                val priority = obj.optString("priority", "normal")

                                // 核心：MediaPlayer播放铃声
                                playAlarmSound()
                                showReminderNotification(reminderId, content, priority)
                                obj.put("status", "triggered")
                                needsSave = true
                                triggeredIds.add(reminderId)
                                triggeredCount++
                                cancelAlarmForReminder(reminderId)

                                android.util.Log.d(TAG, "✅ 触发提醒(Handler轮询): $content")
                            } else {
                                if (status == "pending" || status == "snoozed") {
                                    obj.put("status", "expired")
                                    needsSave = true
                                    android.util.Log.d(TAG, "过期提醒: $content 已过${diff / 3600000}小时")
                                }
                            }
                        } else {
                            // 未来提醒 → 用AlarmManager精确调度
                            scheduleAlarmForReminder(reminderId, content, triggerTime)
                        }
                    } catch (e: Exception) {
                        // 时间解析错误
                    }
                }

                if (needsSave) {
                    prefs.edit().putString(key, jsonArray.toString()).apply()
                }
            } catch (e: Exception) {
                // JSON解析错误
            }
        }

        if (triggeredIds.size > 200) {
            triggeredIds.clear()
        }

        if (triggeredCount > 0) {
            android.util.Log.d(TAG, "本次检查触发${triggeredCount}条提醒")
        }

        updateForegroundNotification()
    }

    /** 
     * 用AlarmManager精确调度 — setExactAndAllowWhileIdle
     * 即使Doze模式也能准时触发
     */
    private fun scheduleAlarmForReminder(reminderId: String, content: String, triggerTimeMs: Long) {
        try {
            val intent = Intent(this, ReminderForegroundService::class.java).apply {
                action = ACTION_ALARM_TRIGGER
                putExtra(EXTRA_REMINDER_ID, reminderId)
                putExtra(EXTRA_REMINDER_CONTENT, content)
            }
            val pendingIntent = PendingIntent.getService(
                this,
                reminderId.hashCode() and 0x7FFFFFFF,
                intent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            )

            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                alarmManager.setExactAndAllowWhileIdle(
                    AlarmManager.RTC_WAKEUP,
                    triggerTimeMs,
                    pendingIntent
                )
            } else {
                alarmManager.setExact(
                    AlarmManager.RTC_WAKEUP,
                    triggerTimeMs,
                    pendingIntent
                )
            }
            android.util.Log.d(TAG, "已调度AlarmManager: $content @ ${Date(triggerTimeMs)}")
        } catch (e: SecurityException) {
            android.util.Log.e(TAG, "精确闹钟权限不足，降级为非精确闹钟", e)
            try {
                val intent = Intent(this, ReminderForegroundService::class.java).apply {
                    action = ACTION_ALARM_TRIGGER
                    putExtra(EXTRA_REMINDER_ID, reminderId)
                    putExtra(EXTRA_REMINDER_CONTENT, content)
                }
                val pendingIntent = PendingIntent.getService(
                    this,
                    reminderId.hashCode() and 0x7FFFFFFF,
                    intent,
                    PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
                )
                alarmManager.setAndAllowWhileIdle(
                    AlarmManager.RTC_WAKEUP,
                    triggerTimeMs,
                    pendingIntent
                )
                android.util.Log.d(TAG, "降级调度(非精确): $content")
            } catch (e2: Exception) {
                android.util.Log.e(TAG, "降级调度也失败", e2)
            }
        } catch (e: Exception) {
            android.util.Log.e(TAG, "调度AlarmManager失败", e)
        }
    }

    private fun cancelAlarmForReminder(reminderId: String) {
        try {
            val intent = Intent(this, ReminderForegroundService::class.java).apply {
                action = ACTION_ALARM_TRIGGER
            }
            val pendingIntent = PendingIntent.getService(
                this,
                reminderId.hashCode() and 0x7FFFFFFF,
                intent,
                PendingIntent.FLAG_NO_CREATE or PendingIntent.FLAG_IMMUTABLE
            )
            pendingIntent?.let {
                alarmManager.cancel(it)
            }
        } catch (e: Exception) { }
    }

    /** 标记提醒为triggered（供AlarmManager触发路径使用） */
    private fun markReminderTriggered(reminderId: String) {
        val prefs = getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
        val allKeys = prefs.all.keys.filter { it.startsWith("${FLUTTER_PREFIX}reminders") }

        for (key in allKeys) {
            val jsonStr = prefs.getString(key, null) ?: continue
            try {
                val jsonArray = JSONArray(jsonStr)
                var found = false
                for (i in 0 until jsonArray.length()) {
                    val obj = jsonArray.getJSONObject(i)
                    if (obj.optString("reminder_id") == reminderId) {
                        obj.put("status", "triggered")
                        found = true
                        break
                    }
                }
                if (found) {
                    prefs.edit().putString(key, jsonArray.toString()).apply()
                    break
                }
            } catch (e: Exception) { }
        }
    }

    /** 发送全屏提醒通知（视觉提示，铃声由MediaPlayer负责） */
    private fun showReminderNotification(reminderId: String, content: String, priority: String) {
        val manager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager

        val launchIntent = packageManager.getLaunchIntentForPackage(packageName)
        val pendingIntent = PendingIntent.getActivity(
            this, reminderId.hashCode() and 0x7FFFFFFF, launchIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
        
        // "停止铃声"按钮
        val stopIntent = Intent(ACTION_STOP_ALARM)
        val stopPendingIntent = PendingIntent.getBroadcast(
            this, 1, stopIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        val isUrgent = priority == "urgent"
        val title = if (isUrgent) "🚨 紧急提醒" else "⏰ 念念不忘提醒"

        val notification = NotificationCompat.Builder(this, REMINDER_CHANNEL_ID)
            .setContentTitle(title)
            .setContentText(content)
            .setStyle(NotificationCompat.BigTextStyle().bigText(content))
            .setSmallIcon(android.R.drawable.ic_lock_idle_alarm)
            .setContentIntent(pendingIntent)
            .setPriority(NotificationCompat.PRIORITY_MAX)
            .setCategory(NotificationCompat.CATEGORY_ALARM)
            .setAutoCancel(true)
            .setTimeoutAfter(300_000)
            .setDefaults(NotificationCompat.DEFAULT_VIBRATE)
            .setVisibility(NotificationCompat.VISIBILITY_PUBLIC)
            .setFullScreenIntent(pendingIntent, true)
            .addAction(android.R.drawable.ic_media_pause, "停止铃声", stopPendingIntent)
            .build()

        val notificationId = REMINDER_NOTIFICATION_ID_START + (reminderId.hashCode() and 0xFFF)
        manager.notify(notificationId, notification)
    }

    private fun updateForegroundNotification() {
        val manager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        val sdf = SimpleDateFormat("HH:mm:ss", Locale.getDefault())
        val timeStr = sdf.format(Date())

        val intent = packageManager.getLaunchIntentForPackage(packageName)
        val pendingIntent = PendingIntent.getActivity(
            this, 0, intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        val notification = NotificationCompat.Builder(this, CHANNEL_ID)
            .setContentTitle("念念不忘")
            .setContentText("守护中 · 最近检查 $timeStr")
            .setSmallIcon(android.R.drawable.ic_lock_idle_alarm)
            .setOngoing(true)
            .setContentIntent(pendingIntent)
            .setPriority(NotificationCompat.PRIORITY_LOW)
            .build()

        manager.notify(NOTIFICATION_ID, notification)
    }

    private fun parseIsoTime(isoStr: String): Long {
        val clean = isoStr.replace("Z", "").replace("+08:00", "").replace("+00:00", "")
        val sdf = SimpleDateFormat("yyyy-MM-dd'T'HH:mm:ss", Locale.getDefault())
        sdf.timeZone = TimeZone.getTimeZone("Asia/Shanghai")
        return sdf.parse(clean.substring(0, minOf(19, clean.length)))?.time ?: 0L
    }
}
