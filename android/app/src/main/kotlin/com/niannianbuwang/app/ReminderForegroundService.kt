package com.niannianbuwang.app

import android.app.*
import android.content.Context
import android.content.Intent
import android.media.AudioAttributes
import android.media.RingtoneManager
import android.os.Build
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import androidx.core.app.NotificationCompat
import androidx.core.content.ContextCompat
import org.json.JSONArray
import java.text.SimpleDateFormat
import java.util.*

/**
 * 原生前台服务 — 念念不忘提醒守护
 * 
 * 核心职责：APP在后台/息屏时仍能触发提醒响铃
 * 
 * 架构：
 * - 原生Kotlin Service，不依赖flutter_background_service包
 * - 通过SharedPreferences读取提醒数据（与Flutter侧共享）
 * - Handler定时轮询，到点发全屏通知+系统闹钟铃声
 * - MethodChannel供Flutter侧启动/停止服务
 */
class ReminderForegroundService : Service() {

    companion object {
        private const val TAG = "ReminderService"
        private const val CHANNEL_ID = "nnbw_foreground_service"
        private const val REMINDER_CHANNEL_ID = "nnbw_reminder_alarm"
        private const val NOTIFICATION_ID = 10001
        private const val REMINDER_NOTIFICATION_ID_START = 20000
        private const val PREFS_NAME = "FlutterSharedPreferences"
        private const val FLUTTER_PREFIX = "flutter." // Flutter shared_preferences自动添加的前缀
        private const val CHECK_INTERVAL_MS = 15_000L // 15秒检查一次
        private const val TRIGGER_WINDOW_MS = 2 * 60 * 60 * 1000L // v1.0.48: 触发窗口2小时（和Flutter侧一致）

        // 已触发的提醒ID集合（避免重复触发）
        private val triggeredIds = mutableSetOf<String>()

        /** 启动前台服务 */
        fun start(context: Context) {
            val intent = Intent(context, ReminderForegroundService::class.java)
            intent.action = "START"
            ContextCompat.startForegroundService(context, intent)
        }

        /** 停止前台服务 */
        fun stop(context: Context) {
            val intent = Intent(context, ReminderForegroundService::class.java)
            intent.action = "STOP"
            context.startService(intent)
        }
    }

    private val handler = Handler(Looper.getMainLooper())
    private var isRunning = false

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
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        android.util.Log.d(TAG, "服务onStartCommand, action=${intent?.action}")

        if (intent?.action == "STOP") {
            stopSelf()
            return START_NOT_STICKY
        }

        if (isRunning) {
            android.util.Log.d(TAG, "服务已在运行")
            return START_STICKY
        }

        // 启动前台服务（必须5秒内调用，否则ANR）
        startForeground(NOTIFICATION_ID, createForegroundNotification())

        isRunning = true
        handler.post(checkRunnable)

        android.util.Log.d(TAG, "前台服务已启动，开始轮询提醒")
        return START_STICKY // 被杀后自动重启
    }

    override fun onDestroy() {
        super.onDestroy()
        isRunning = false
        handler.removeCallbacks(checkRunnable)
        android.util.Log.d(TAG, "服务已销毁")
    }

    override fun onBind(intent: Intent?): IBinder? = null

    /** 创建前台服务通知渠道和提醒闹钟通知渠道 */
    private fun createNotificationChannels() {
        val manager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager

        // 1. 前台服务通知渠道（低优先级，仅显示"运行中"）
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

            // 2. 提醒闹钟通知渠道（最高优先级，支持全屏+响铃+振动）
            val reminderChannel = NotificationChannel(
                REMINDER_CHANNEL_ID,
                "提醒闹钟",
                NotificationManager.IMPORTANCE_HIGH
            ).apply {
                description = "到点提醒，锁屏时也会响铃弹出"
                enableVibration(true)
                vibrationPattern = longArrayOf(0, 500, 200, 500, 200, 500)
                lockscreenVisibility = Notification.VISIBILITY_PUBLIC
                // 使用系统默认闹钟铃声
                val alarmSound = RingtoneManager.getDefaultUri(RingtoneManager.TYPE_ALARM)
                    ?: RingtoneManager.getDefaultUri(RingtoneManager.TYPE_NOTIFICATION)
                setSound(alarmSound, AudioAttributes.Builder()
                    .setUsage(AudioAttributes.USAGE_ALARM)
                    .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
                    .build())
                // 允许全屏Intent（锁屏弹出）
                // Android 14+ 需要USE_EXACT_ALARM或FOREGROUND_SERVICE_SPECIAL_USE权限
            }
            manager.createNotificationChannel(reminderChannel)
        }
    }

    /** 创建前台服务通知（持续显示"守护中"） */
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

    /** 检查SharedPreferences中的提醒数据 */
    private fun checkReminders() {
        val prefs = getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
        val now = System.currentTimeMillis()
        val calendar = Calendar.getInstance()

        // Flutter shared_preferences会在key前加"flutter."前缀
        // 所以Flutter存的"reminders_xxx"在SP中实际是"flutter.reminders_xxx"
        val allKeys = prefs.all.keys.filter { 
            it.startsWith("${FLUTTER_PREFIX}reminders") 
        }
        var triggeredCount = 0

        for (key in allKeys) {
            // Flutter SP中String值直接用getString读取
            val jsonStr = prefs.getString(key, null) ?: continue
            try {
                val jsonArray = JSONArray(jsonStr)
                var needsSave = false

                for (i in 0 until jsonArray.length()) {
                    val obj = jsonArray.getJSONObject(i)
                    val reminderId = obj.optString("reminder_id", "")
                    val status = obj.optString("status", "")

                    // 只处理pending状态
                    if (status != "pending" && status != "snoozed") continue
                    // 避免重复触发
                    if (triggeredIds.contains(reminderId)) continue

                    val triggerTimeStr = obj.optString("trigger_time", "")
                    if (triggerTimeStr.isEmpty()) continue

                    try {
                        val triggerTime = parseIsoTime(triggerTimeStr)
                        val diff = now - triggerTime

                        if (diff >= 0) {
                            val content = obj.optString("content", "提醒")
                            if (diff <= TRIGGER_WINDOW_MS) {
                                // 到期且在2小时触发窗口内 → 触发响铃
                                val priority = obj.optString("priority", "normal")

                                // 发送全屏通知+响铃
                                showReminderNotification(reminderId, content, priority)
                                
                                // 更新状态为triggered
                                obj.put("status", "triggered")
                                needsSave = true
                                triggeredIds.add(reminderId)
                                triggeredCount++

                                android.util.Log.d(TAG, "触发提醒: $content")
                            } else {
                                // v1.0.48: 超过2小时的过期提醒标记为expired
                                if (status == "pending" || status == "snoozed") {
                                    obj.put("status", "expired")
                                    needsSave = true
                                    android.util.Log.d(TAG, "过期提醒: $content 已过${diff / 3600000}小时")
                                }
                            }
                        }
                    } catch (e: Exception) {
                        // 时间解析错误，跳过
                    }
                }

                // 保存更新后的状态
                if (needsSave) {
                    prefs.edit().putString(key, jsonArray.toString()).apply()
                }
            } catch (e: Exception) {
                // JSON解析错误，跳过
            }
        }

        // 清理超过2小时的触发记录
        if (triggeredIds.size > 200) {
            triggeredIds.clear()
        }

        if (triggeredCount > 0) {
            android.util.Log.d(TAG, "本次检查触发${triggeredCount}条提醒")
        }

        // 更新前台通知显示最后检查时间
        updateForegroundNotification()
    }

    /** 发送全屏提醒通知（带闹钟铃声+振动） */
    private fun showReminderNotification(reminderId: String, content: String, priority: String) {
        val manager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager

        val intent = packageManager.getLaunchIntentForPackage(packageName)
        val pendingIntent = PendingIntent.getActivity(
            this, reminderId.hashCode() and 0x7FFFFFFF, intent,
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
            .setTimeoutAfter(120_000) // 2分钟后自动消失
            .setDefaults(NotificationCompat.DEFAULT_ALL)
            .setSound(RingtoneManager.getDefaultUri(RingtoneManager.TYPE_ALARM))
            .setVibrate(longArrayOf(0, 500, 200, 500, 200, 500))
            .setVisibility(NotificationCompat.VISIBILITY_PUBLIC)
            // 全屏Intent：锁屏时也能弹出
            .setFullScreenIntent(pendingIntent, true)
            .build()

        // 使用不同的notificationId避免覆盖
        val notificationId = REMINDER_NOTIFICATION_ID_START + (reminderId.hashCode() and 0xFFF)
        manager.notify(notificationId, notification)
    }

    /** 更新前台服务通知，显示最后检查时间 */
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

    /** 解析ISO 8601时间字符串为毫秒时间戳 */
    private fun parseIsoTime(isoStr: String): Long {
        // 处理Flutter的toIso8601String格式：2026-06-03T14:30:00.000
        val clean = isoStr.replace("Z", "").replace("+08:00", "").replace("+00:00", "")
        val sdf = SimpleDateFormat("yyyy-MM-dd'T'HH:mm:ss", Locale.getDefault())
        sdf.timeZone = TimeZone.getTimeZone("Asia/Shanghai")
        return sdf.parse(clean.substring(0, minOf(19, clean.length)))?.time ?: 0L
    }
}
