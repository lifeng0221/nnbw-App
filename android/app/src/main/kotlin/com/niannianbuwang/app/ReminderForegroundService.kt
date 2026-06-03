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
 * 原生前台服务 — 念念不忘提醒守护 v1.0.51
 * 
 * v1.0.51 核心改动：
 * - 使用AlarmReceiver(BroadcastReceiver)代替直接PendingIntent.getService()
 *   BroadcastReceiver在Doze模式下仍能被AlarmManager唤醒
 * - 使用setAlarmClock()替代setExactAndAllowWhileIdle()，闹钟优先级最高
 * - 新增scheduleAllFutureAlarms()：服务启动时立即调度所有未来提醒
 * - 新增SCHEDULE_ALL action：Flutter可通过MethodChannel触发立即调度
 * - 去掉checkReminders中的直接launchAlarmActivity()（Android 10+后台禁止启动Activity）
 *   改为完全依靠通知的fullScreenIntent机制显示AlarmActivity
 * - Handler轮询降为60s间隔（仅作备用），主要依赖AlarmManager
 * - ACTION_ALARM_TRIGGER处理中添加startForeground()防止崩溃
 */
class ReminderForegroundService : Service() {

    companion object {
        private const val TAG = "ReminderService"
        private const val CHANNEL_ID = "nnbw_foreground_service"
        private const val REMINDER_CHANNEL_ID = "nnbw_reminder_alarm_v2"
        private const val NOTIFICATION_ID = 10001
        private const val REMINDER_NOTIFICATION_ID_START = 20000
        private const val PREFS_NAME = "FlutterSharedPreferences"
        private const val FLUTTER_PREFIX = "flutter."
        private const val CHECK_INTERVAL_MS = 60_000L // v1.0.51: 60秒（降为备用）
        private const val TRIGGER_WINDOW_MS = 2 * 60 * 60 * 1000L
        const val ACTION_STOP_ALARM = "com.niannianbuwang.app.STOP_ALARM"
        const val ACTION_ALARM_TRIGGER = "com.niannianbuwang.app.ALARM_TRIGGER"
        private const val ACTION_SCHEDULE_ALL = "com.niannianbuwang.app.SCHEDULE_ALL"
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
        
        fun playAlarmFromFlutter(context: Context) {
            android.util.Log.d(TAG, "收到Flutter请求，启动原生闹钟铃声")
            try {
                val intent = Intent(context, ReminderForegroundService::class.java)
                intent.action = "PLAY_ALARM"
                context.startService(intent)
            } catch (e: Exception) {
                android.util.Log.e(TAG, "启动闹钟铃声失败", e)
            }
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

        // Flutter触发播放铃声
        if (intent?.action == "PLAY_ALARM") {
            android.util.Log.d(TAG, "收到Flutter播放铃声请求")
            val content = intent.getStringExtra(EXTRA_REMINDER_CONTENT) ?: "提醒时间到了"
            // v1.0.51: 先发通知(fullScreenIntent)，再播放铃声
            val reminderId = "flutter_${System.currentTimeMillis()}"
            showReminderNotification(reminderId, content, "normal")
            playAlarmSound()
            if (!isRunning) {
                startForeground(NOTIFICATION_ID, createForegroundNotification())
                isRunning = true
                handler.post(checkRunnable)
            }
            return START_STICKY
        }

        // AlarmManager/AlarmReceiver触发
        if (intent?.action == ACTION_ALARM_TRIGGER) {
            val reminderId = intent.getStringExtra(EXTRA_REMINDER_ID) ?: ""
            val content = intent.getStringExtra(EXTRA_REMINDER_CONTENT) ?: "提醒"
            // v1.0.51: 必须调startForeground防止崩溃
            if (!isRunning) {
                startForeground(NOTIFICATION_ID, createForegroundNotification())
                isRunning = true
                handler.post(checkRunnable)
            }
            if (!triggeredIds.contains(reminderId)) {
                android.util.Log.d(TAG, "AlarmReceiver触发提醒: $content")
                // 先发通知(带fullScreenIntent)，再播放铃声
                showReminderNotification(reminderId, content, "normal")
                playAlarmSound()
                markReminderTriggered(reminderId)
                triggeredIds.add(reminderId)
            }
            return START_STICKY
        }

        // Flutter请求立即调度所有闹钟
        if (intent?.action == ACTION_SCHEDULE_ALL) {
            android.util.Log.d(TAG, "收到调度全部闹钟请求")
            scheduleAllFutureAlarms()
            if (!isRunning) {
                startForeground(NOTIFICATION_ID, createForegroundNotification())
                isRunning = true
                handler.post(checkRunnable)
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

            val reminderChannel = NotificationChannel(
                REMINDER_CHANNEL_ID,
                "提醒闹钟",
                NotificationManager.IMPORTANCE_HIGH
            ).apply {
                description = "提醒到点响铃通知"
                enableVibration(true)
                setSound(null, null)
                lockscreenVisibility = Notification.VISIBILITY_PUBLIC
                setShowBadge(true)
                // v1.0.51: 允许锁屏全屏弹出
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                    importance = NotificationManager.IMPORTANCE_HIGH
                }
            }
            manager.createNotificationChannel(reminderChannel)
            
            // 删除旧渠道（如果有nnbw_reminder_alarm）
            manager.deleteNotificationChannel("nnbw_reminder_alarm")
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
            .setContentText("守护中")
            .setSmallIcon(android.R.drawable.ic_lock_idle_alarm)
            .setOngoing(true)
            .setContentIntent(pendingIntent)
            .setPriority(NotificationCompat.PRIORITY_LOW)
            .build()
    }

    /**
     * v1.0.51: 立即调度所有未来提醒的AlarmManager闹钟
     * 扫描SharedPreferences中所有pending/confirmed/snoozed状态的提醒
     * 为每个未来提醒调度精确闹钟（通过AlarmReceiver）
     */
    fun scheduleAllFutureAlarms() {
        val prefs = getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
        val now = System.currentTimeMillis()
        var scheduledCount = 0

        val allKeys = prefs.all.keys.filter { 
            it.startsWith("${FLUTTER_PREFIX}reminders") 
        }

        for (key in allKeys) {
            val jsonStr = prefs.getString(key, null) ?: continue
            try {
                val jsonArray = JSONArray(jsonStr)
                for (i in 0 until jsonArray.length()) {
                    val obj = jsonArray.getJSONObject(i)
                    val status = obj.optString("status", "")
                    if (status != "pending" && status != "confirmed" && status != "snoozed") continue
                    
                    val reminderId = obj.optString("reminder_id", "")
                    if (reminderId.isEmpty()) continue
                    if (triggeredIds.contains(reminderId)) continue

                    val triggerTimeStr = obj.optString("trigger_time", "")
                    if (triggerTimeStr.isEmpty()) continue

                    try {
                        val triggerTime = parseIsoTime(triggerTimeStr)
                        val diff = triggerTime - now
                        
                        if (diff > 0) {
                            // 未来提醒 → 调度AlarmManager
                            val content = obj.optString("content", "提醒")
                            scheduleAlarmForReminder(reminderId, content, triggerTime)
                            scheduledCount++
                            android.util.Log.d(TAG, "调度闹钟: $content @ ${Date(triggerTime)} (${diff/1000}秒后)")
                        } else if (diff > -60000) {
                            // 刚刚到期（1分钟内）→ 立即触发
                            val content = obj.optString("content", "提醒")
                            val priority = obj.optString("priority", "normal")
                            android.util.Log.d(TAG, "立即触发: $content (刚到期${-diff/1000}秒)")
                            showReminderNotification(reminderId, content, priority)
                            playAlarmSound()
                            obj.put("status", "triggered")
                            triggeredIds.add(reminderId)
                            prefs.edit().putString(key, jsonArray.toString()).apply()
                        }
                    } catch (e: Exception) {
                        android.util.Log.e(TAG, "调度闹钟时间解析错误", e)
                    }
                }
            } catch (e: Exception) {
                android.util.Log.e(TAG, "调度闹钟JSON解析错误", e)
            }
        }
        
        android.util.Log.d(TAG, "scheduleAllFutureAlarms完成: 调度${scheduledCount}个闹钟")
    }

    private fun playAlarmSound() {
        acquireWakeLocks()
        
        try {
            // 先停止之前的铃声
            alarmMediaPlayer?.let {
                if (it.isPlaying) it.stop()
                it.release()
            }
            alarmMediaPlayer = null
        } catch (e: Exception) { }

        try {
            val alarmUri = RingtoneManager.getDefaultUri(RingtoneManager.TYPE_ALARM)
                ?: RingtoneManager.getDefaultUri(RingtoneManager.TYPE_NOTIFICATION)
                ?: RingtoneManager.getDefaultUri(RingtoneManager.TYPE_RINGTONE)

            alarmMediaPlayer = MediaPlayer().apply {
                setAudioAttributes(
                    AudioAttributes.Builder()
                        .setUsage(AudioAttributes.USAGE_ALARM)
                        .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
                        .build()
                )
                setDataSource(this@ReminderForegroundService, alarmUri)
                isLooping = true
                setOnPreparedListener { it.start() }
                prepareAsync()
            }
            android.util.Log.d(TAG, "MediaPlayer闹钟铃声播放中(USAGE_ALARM)")
            return
        } catch (e: Exception) {
            android.util.Log.e(TAG, "MediaPlayer播放失败", e)
        }

        // 备用方案：Ringtone
        try {
            val alarmUri = RingtoneManager.getDefaultUri(RingtoneManager.TYPE_ALARM)
            val ringtone = RingtoneManager.getRingtone(this, alarmUri)
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

    private fun acquireWakeLocks() {
        try {
            if (wakeLock == null || !wakeLock!!.isHeld) {
                val pm = getSystemService(Context.POWER_SERVICE) as PowerManager
                wakeLock = pm.newWakeLock(
                    PowerManager.PARTIAL_WAKE_LOCK,
                    "nnbw:ReminderAlarm"
                ).apply {
                    acquire(5 * 60 * 1000L)
                }
            }
        } catch (e: Exception) { }

        try {
            if (screenWakeLock == null || !screenWakeLock!!.isHeld) {
                val pm = getSystemService(Context.POWER_SERVICE) as PowerManager
                screenWakeLock = pm.newWakeLock(
                    PowerManager.SCREEN_BRIGHT_WAKE_LOCK or PowerManager.ACQUIRE_CAUSES_WAKEUP,
                    "nnbw:ReminderScreen"
                ).apply {
                    acquire(30 * 1000L)
                }
            }
        } catch (e: Exception) { }
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

                    if (status != "pending" && status != "confirmed" && status != "snoozed") continue
                    if (triggeredIds.contains(reminderId)) continue

                    val triggerTimeStr = obj.optString("trigger_time", "")
                    if (triggerTimeStr.isEmpty()) continue

                    try {
                        val triggerTime = parseIsoTime(triggerTimeStr)
                        val diff = now - triggerTime
                        val content = obj.optString("content", "提醒")

                        if (diff >= 0) {
                            if (diff <= TRIGGER_WINDOW_MS) {
                                val priority = obj.optString("priority", "normal")
                                // v1.0.51: 先发通知(fullScreenIntent)，再播放铃声
                                // 不再直接调launchAlarmActivity()，Android 10+后台启动Activity被禁
                                showReminderNotification(reminderId, content, priority)
                                playAlarmSound()
                                obj.put("status", "triggered")
                                needsSave = true
                                triggeredIds.add(reminderId)
                                triggeredCount++
                                cancelAlarmForReminder(reminderId)

                                android.util.Log.d(TAG, "触发提醒(Handler轮询): $content (原status=$status)")
                            } else {
                                if (status == "pending" || status == "confirmed" || status == "snoozed") {
                                    obj.put("status", "expired")
                                    needsSave = true
                                    android.util.Log.d(TAG, "过期提醒: $content 已过${diff / 3600000}小时")
                                }
                            }
                        } else {
                            // 未来提醒 → 确保AlarmManager已调度
                            scheduleAlarmForReminder(reminderId, content, triggerTime)
                        }
                    } catch (e: Exception) {
                        android.util.Log.e(TAG, "时间解析错误", e)
                    }
                }

                if (needsSave) {
                    prefs.edit().putString(key, jsonArray.toString()).apply()
                }
            } catch (e: Exception) {
                android.util.Log.e(TAG, "JSON解析错误", e)
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
     * v1.0.51: 使用AlarmReceiver(BroadcastReceiver) + setAlarmClock()
     * setAlarmClock是闹钟专用API，优先级最高，Doze模式下也能唤醒
     */
    private fun scheduleAlarmForReminder(reminderId: String, content: String, triggerTimeMs: Long) {
        try {
            // 目标：AlarmReceiver
            val alarmIntent = Intent(this, AlarmReceiver::class.java).apply {
                putExtra(EXTRA_REMINDER_ID, reminderId)
                putExtra(EXTRA_REMINDER_CONTENT, content)
            }
            val pendingIntent = PendingIntent.getBroadcast(
                this,
                reminderId.hashCode() and 0x7FFFFFFF,
                alarmIntent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            )

            // 点击闹钟图标时的Intent（跳转到APP）
            val showIntent = Intent(this, MainActivity::class.java).apply {
                flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
            }
            val showPendingIntent = PendingIntent.getActivity(
                this,
                (reminderId.hashCode() and 0x7FFFFFFF) + 10000,
                showIntent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            )

            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.LOLLIPOP) {
                // v1.0.51: 使用setAlarmClock — 闹钟最高优先级API
                val alarmClockInfo = AlarmManager.AlarmClockInfo(triggerTimeMs, showPendingIntent)
                alarmManager.setAlarmClock(alarmClockInfo, pendingIntent)
                android.util.Log.d(TAG, "调度AlarmClock: $content @ ${Date(triggerTimeMs)}")
            } else {
                alarmManager.setExact(
                    AlarmManager.RTC_WAKEUP,
                    triggerTimeMs,
                    pendingIntent
                )
            }
        } catch (e: SecurityException) {
            android.util.Log.e(TAG, "闹钟权限不足，降级setExactAndAllowWhileIdle", e)
            try {
                val alarmIntent = Intent(this, AlarmReceiver::class.java).apply {
                    putExtra(EXTRA_REMINDER_ID, reminderId)
                    putExtra(EXTRA_REMINDER_CONTENT, content)
                }
                val pendingIntent = PendingIntent.getBroadcast(
                    this,
                    reminderId.hashCode() and 0x7FFFFFFF,
                    alarmIntent,
                    PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
                )
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                    alarmManager.setExactAndAllowWhileIdle(
                        AlarmManager.RTC_WAKEUP,
                        triggerTimeMs,
                        pendingIntent
                    )
                } else {
                    alarmManager.setExact(AlarmManager.RTC_WAKEUP, triggerTimeMs, pendingIntent)
                }
                android.util.Log.d(TAG, "降级调度: $content @ ${Date(triggerTimeMs)}")
            } catch (e2: Exception) {
                android.util.Log.e(TAG, "降级调度也失败", e2)
            }
        } catch (e: Exception) {
            android.util.Log.e(TAG, "调度AlarmManager失败", e)
        }
    }

    private fun cancelAlarmForReminder(reminderId: String) {
        try {
            val intent = Intent(this, AlarmReceiver::class.java)
            val pendingIntent = PendingIntent.getBroadcast(
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

    private fun showReminderNotification(reminderId: String, content: String, priority: String) {
        val manager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager

        // fullScreenIntent：锁屏时全屏弹出AlarmActivity
        val alarmIntent = Intent(this, AlarmActivity::class.java).apply {
            putExtra(AlarmActivity.EXTRA_REMINDER_ID, reminderId)
            putExtra(AlarmActivity.EXTRA_CONTENT, content)
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP or Intent.FLAG_ACTIVITY_CLEAR_TASK
        }
        val fullScreenPendingIntent = PendingIntent.getActivity(
            this, reminderId.hashCode() and 0x7FFFFFFF, alarmIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        val contentPendingIntent = PendingIntent.getActivity(
            this, (reminderId.hashCode() and 0x7FFFFFFF) + 1, alarmIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
        
        val stopIntent = Intent(ACTION_STOP_ALARM)
        val stopPendingIntent = PendingIntent.getBroadcast(
            this, 2, stopIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        val isUrgent = priority == "urgent"
        val title = if (isUrgent) "🚨 紧急提醒" else "⏰ 念念不忘提醒"

        val notification = NotificationCompat.Builder(this, REMINDER_CHANNEL_ID)
            .setContentTitle(title)
            .setContentText(content)
            .setStyle(NotificationCompat.BigTextStyle().bigText(content))
            .setSmallIcon(android.R.drawable.ic_lock_idle_alarm)
            .setContentIntent(contentPendingIntent)
            .setPriority(NotificationCompat.PRIORITY_MAX)
            .setCategory(NotificationCompat.CATEGORY_ALARM)
            .setAutoCancel(false) // v1.0.51: 不自动消失，用户必须手动点击
            .setDefaults(NotificationCompat.DEFAULT_VIBRATE)
            .setVisibility(NotificationCompat.VISIBILITY_PUBLIC)
            .setFullScreenIntent(fullScreenPendingIntent, true) // 核心：锁屏全屏弹出
            .addAction(android.R.drawable.ic_media_pause, "停止铃声", stopPendingIntent)
            .build()

        val notificationId = REMINDER_NOTIFICATION_ID_START + (reminderId.hashCode() and 0xFFF)
        manager.notify(notificationId, notification)
        android.util.Log.d(TAG, "已发送全屏通知: $content (id=$notificationId)")
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
