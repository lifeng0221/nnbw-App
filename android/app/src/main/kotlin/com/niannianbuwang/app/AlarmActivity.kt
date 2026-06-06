package com.niannianbuwang.app

import android.app.Activity
import android.app.KeyguardManager
import android.content.Context
import android.os.Build
import android.os.Bundle
import android.view.Gravity
import android.view.WindowManager
import android.widget.Button
import android.widget.LinearLayout
import android.widget.Space
import android.widget.TextView
import android.graphics.Color
import android.graphics.Typeface
import android.util.TypedValue

/**
 * 全屏闹钟Activity v1.0.51
 * 
 * v1.0.51改动：
 * - 更激进的锁屏显示：使用KeyguardManager解除锁屏
 * - 添加dismissAfterStop标志，停止铃声后自动关闭
 * - 保持屏幕常亮直到用户按"知道了"
 */
class AlarmActivity : Activity() {

    companion object {
        const val EXTRA_CONTENT = "reminder_content"
        const val EXTRA_REMINDER_ID = "reminder_id"

        // v1.0.63: native queue 兜底
        // Flutter 端 shared_preferences 插件自动加 "flutter." 前缀
        // Kotlin 端写"裸"key（不带前缀），Flutter 端 getStringList('pending_confirms') 即可读到
        // 实际 Android SharedPreferences 里的 key 是 "flutter.pending_confirms"
        const val NATIVE_QUEUE_PREFS = "FlutterSharedPreferences"
        const val NATIVE_QUEUE_KEY = "pending_confirms"
    }

    /**
     * v1.0.63 native queue 兜底：AlarmActivity 写一个 StringSet
     * Flutter 端下次 _loadData 时读取并消化（删掉已处理的 reminderId）
     * 解决"MainActivity.methodChannel 为 null 时 invokeMethod 静默失败"问题
     */
    private fun writePendingConfirm(reminderId: String) {
        try {
            val prefs = getSharedPreferences(NATIVE_QUEUE_PREFS, Context.MODE_PRIVATE)
            val current = prefs.getStringSet(NATIVE_QUEUE_KEY, mutableSetOf()) ?: mutableSetOf()
            val newSet = HashSet(current).apply { add(reminderId) }
            prefs.edit().putStringSet(NATIVE_QUEUE_KEY, newSet).apply()
            android.util.Log.d("AlarmActivity", "native queue 已写入: $reminderId, 当前queue大小=${newSet.size}")
        } catch (e: Exception) {
            android.util.Log.e("AlarmActivity", "native queue 写入失败", e)
        }
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        // 锁屏上显示 + 点亮屏幕
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O_MR1) {
            setShowWhenLocked(true)
            setTurnScreenOn(true)
        } else {
            @Suppress("DEPRECATION")
            window.addFlags(
                WindowManager.LayoutParams.FLAG_SHOW_WHEN_LOCKED or
                WindowManager.LayoutParams.FLAG_TURN_SCREEN_ON or
                WindowManager.LayoutParams.FLAG_DISMISS_KEYGUARD
            )
        }
        
        // 解除锁屏（v1.0.51新增）
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val keyguardManager = getSystemService(Context.KEYGUARD_SERVICE) as KeyguardManager
            keyguardManager.requestDismissKeyguard(this, object : KeyguardManager.KeyguardDismissCallback() {
                override fun onDismissSucceeded() {
                    android.util.Log.d("AlarmActivity", "锁屏已解除")
                }
                override fun onDismissCancelled() {
                    android.util.Log.d("AlarmActivity", "锁屏解除取消")
                }
                override fun onDismissError() {
                    android.util.Log.d("AlarmActivity", "锁屏解除失败")
                }
            })
        } else {
            @Suppress("DEPRECATION")
            window.addFlags(WindowManager.LayoutParams.FLAG_DISMISS_KEYGUARD)
        }
        
        window.addFlags(
            WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON or
            WindowManager.LayoutParams.FLAG_FULLSCREEN or
            WindowManager.LayoutParams.FLAG_LAYOUT_IN_SCREEN
        )

        val content = intent.getStringExtra(EXTRA_CONTENT) ?: "提醒时间到了"

        val layout = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            setBackgroundColor(Color.parseColor("#1A1A2E"))
            setPadding(dp(32), dp(64), dp(32), dp(32))
            gravity = Gravity.CENTER
        }

        val titleView = TextView(this).apply {
            text = "⏰ 念念不忘"
            setTextColor(Color.parseColor("#FFD700"))
            setTextSize(TypedValue.COMPLEX_UNIT_SP, 32f)
            typeface = Typeface.DEFAULT_BOLD
            gravity = Gravity.CENTER
        }
        layout.addView(titleView)

        layout.addView(Space(this), LinearLayout.LayoutParams(
            LinearLayout.LayoutParams.MATCH_PARENT, dp(32)
        ))

        val contentView = TextView(this).apply {
            text = content
            setTextColor(Color.WHITE)
            setTextSize(TypedValue.COMPLEX_UNIT_SP, 28f)
            gravity = Gravity.CENTER
            setPadding(dp(16), dp(16), dp(16), dp(16))
        }
        layout.addView(contentView)

        layout.addView(Space(this), LinearLayout.LayoutParams(
            LinearLayout.LayoutParams.MATCH_PARENT, dp(48)
        ))

        val dismissBtn = Button(this).apply {
            text = "知 道 了"
            setTextColor(Color.WHITE)
            setTextSize(TypedValue.COMPLEX_UNIT_SP, 24f)
            typeface = Typeface.DEFAULT_BOLD
            setBackgroundColor(Color.parseColor("#E94560"))
            setPadding(dp(24), dp(16), dp(24), dp(16))
            minWidth = dp(200)
            minHeight = dp(80)
            setOnClickListener { dismissAlarm() }
        }
        val btnParams = LinearLayout.LayoutParams(
            LinearLayout.LayoutParams.WRAP_CONTENT,
            LinearLayout.LayoutParams.WRAP_CONTENT
        ).apply { gravity = Gravity.CENTER }
        layout.addView(dismissBtn, btnParams)

        // 5分钟超时自动关闭（v1.0.63改为静默关闭，不走确认流程）
        // 原因：v1.0.62把"超时"和"主动按按钮"都走confirmReminder导致老人没按也被记成已确认
        // 静默关闭：只停铃+取消通知+切断追响，保留triggered状态，等子女端继续关注
        window.decorView.postDelayed({ silentDismiss() }, 5 * 60 * 1000L)

        setContentView(layout)
        
        android.util.Log.d("AlarmActivity", "全屏闹钟已显示: $content")
    }

    /**
     * v1.0.63 静默关闭：5分钟超时或系统关闭时调用
     * 不调confirmReminder——保持triggered状态，老人没按按钮就不算确认
     * 保留"子女端看到🔔已响铃待老人确认"状态，等下次响铃或snooze超时
     */
    private fun silentDismiss() {
        ReminderForegroundService.stopAlarmSound()
        val reminderId = intent.getStringExtra(EXTRA_REMINDER_ID) ?: ""
        // 取消通知——v1.0.64 改为 cancelAll()（与 stopAlarmReceiver 一致）
        // 修复 Bug 6：通知栏残留导致主界面"知道了"按钮看似失效
        try {
            val manager = getSystemService(Context.NOTIFICATION_SERVICE) as android.app.NotificationManager
            manager.cancelAll()
        } catch (e: Exception) { }
        // 切断追响——v1.0.62的Bug 4核心修复保留
        if (reminderId.isNotEmpty()) {
            try {
                ReminderForegroundService.cancelFollowupAlarms(this, reminderId)
                android.util.Log.d("AlarmActivity", "静默关闭：已切断reminder=$reminderId 追响，状态保持triggered")
            } catch (e: Exception) {
                android.util.Log.e("AlarmActivity", "静默关闭-取消追响失败", e)
            }
        }
        android.util.Log.d("AlarmActivity", "静默关闭（5分钟超时）: $reminderId，**未**调confirmReminder")
        finish()
    }

    private fun dismissAlarm() {
        // 1) 先停铃声
        ReminderForegroundService.stopAlarmSound()

        val reminderId = intent.getStringExtra(EXTRA_REMINDER_ID) ?: ""

        // 2) 取消闹钟通知
        try {
            val manager = getSystemService(Context.NOTIFICATION_SERVICE) as android.app.NotificationManager
            val notificationId = 20000 + (reminderId.hashCode() and 0xFFF)
            manager.cancel(notificationId)
        } catch (e: Exception) { }

        // 3) v1.0.62: 切断该提醒的所有追响闹钟（5/15/30/60/120分钟那一串）
        if (reminderId.isNotEmpty()) {
            try {
                ReminderForegroundService.cancelFollowupAlarms(this, reminderId)
                android.util.Log.d("AlarmActivity", "已切断reminder=$reminderId 的所有追响闹钟")
            } catch (e: Exception) {
                android.util.Log.e("AlarmActivity", "取消追响闹钟失败", e)
            }

            // 4) v1.0.62: 优先通过 MethodChannel 通知 Flutter 端走 _confirmReminder 流程
            //    (status→confirmed + 同步后端 + UI刷新)
            val ch = MainActivity.methodChannel
            if (ch != null) {
                try {
                    ch.invokeMethod("confirmReminder", reminderId)
                    android.util.Log.d("AlarmActivity", "已通知Flutter端确认: $reminderId")
                } catch (e: Exception) {
                    android.util.Log.e("AlarmActivity", "通知Flutter确认异常，写入native queue兜底", e)
                    writePendingConfirm(reminderId)
                }
            } else {
                // v1.0.63: methodChannel为null（MainActivity未创建/已被销毁）时，写native queue兜底
                // Flutter端下次_loadData时消化这个queue
                android.util.Log.w("AlarmActivity", "methodChannel为null，写入native queue兜底: $reminderId")
                writePendingConfirm(reminderId)
            }
        }

        finish()
    }

    override fun onBackPressed() {
        // 必须按"知道了"
    }

    override fun onDestroy() {
        super.onDestroy()
        // 确保铃声停止
        ReminderForegroundService.stopAlarmSound()
    }

    private fun dp(value: Int): Int {
        return TypedValue.applyDimension(
            TypedValue.COMPLEX_UNIT_DIP, value.toFloat(), resources.displayMetrics
        ).toInt()
    }
}
