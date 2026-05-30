#!/usr/bin/env python3
import subprocess
import os

os.chdir('/app/data/所有对话/主对话/flutter_project')

# Configure git
subprocess.run(['git', 'config', '--global', 'user.email', 'ci@example.com'], check=True)
subprocess.run(['git', 'config', '--global', 'user.name', 'CI'], check=True)

# Add all changes
subprocess.run(['git', 'add', '-A'], check=True)

# Commit
result = subprocess.run(['git', 'commit', '-m', '''v1.0.17: 7个bug修复

Bug 1: 汉堡菜单改用GlobalKey<ScaffoldState>打开
Bug 2: 确认弹窗大号时间显示selectedTime而非defaultTime
Bug 3: 确认按钮通过handleConfirm闭包传递最新selectedTime
Bug 4: snoozeReminder状态保持pending，triggerTime延后5分钟
Bug 5: 时间选择器改用Slider滑动选择，老人友好大字显示
Bug 6: 轮询立即检查过期提醒，triggerTime<=now时触发
Bug 7: 前台每10秒刷新提醒列表'''], capture_output=True, text=True)
print("Commit result:", result.stdout, result.stderr)

# Push
result = subprocess.run(['git', 'push', 'https://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@github.com/lifeng0221/nnbw-App.git', 'main'], capture_output=True, text=True)
print("Push result:", result.stdout, result.stderr)
