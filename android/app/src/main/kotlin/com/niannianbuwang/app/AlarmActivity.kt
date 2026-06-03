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

        // 5分钟超时自动关闭
        window.decorView.postDelayed({ dismissAlarm() }, 5 * 60 * 1000L)

        setContentView(layout)
        
        android.util.Log.d("AlarmActivity", "全屏闹钟已显示: $content")
    }

    private fun dismissAlarm() {
        ReminderForegroundService.stopAlarmSound()
        // 取消闹钟通知
        try {
            val manager = getSystemService(Context.NOTIFICATION_SERVICE) as android.app.NotificationManager
            val reminderId = intent.getStringExtra(EXTRA_REMINDER_ID) ?: ""
            val notificationId = 20000 + (reminderId.hashCode() and 0xFFF)
            manager.cancel(notificationId)
        } catch (e: Exception) { }
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
