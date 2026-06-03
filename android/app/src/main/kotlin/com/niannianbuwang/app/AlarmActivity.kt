package com.niannianbuwang.app

import android.app.Activity
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

class AlarmActivity : Activity() {

    companion object {
        const val EXTRA_CONTENT = "reminder_content"
        const val EXTRA_REMINDER_ID = "reminder_id"
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

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
        window.addFlags(
            WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON or
            WindowManager.LayoutParams.FLAG_FULLSCREEN
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

        window.decorView.postDelayed({ dismissAlarm() }, 5 * 60 * 1000L)

        setContentView(layout)
    }

    private fun dismissAlarm() {
        ReminderForegroundService.stopAlarmSound()
        finish()
    }

    override fun onBackPressed() {
        // 必须按"知道了"
    }

    private fun dp(value: Int): Int {
        return TypedValue.applyDimension(
            TypedValue.COMPLEX_UNIT_DIP, value.toFloat(), resources.displayMetrics
        ).toInt()
    }
}
