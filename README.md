# 念念不忘 - Flutter APP

老人极简语音提醒 + 子女协同

## 快速开始

### 环境要求
- Flutter 3.29+
- Java 17
- Android SDK

### 本地运行
```bash
flutter pub get
flutter run
```

### 编译APK
```bash
flutter build apk --release
```

## 项目结构
```
lib/
├── main.dart                    # 入口
├── models/
│   └── app_models.dart          # 数据模型
├── screens/
│   ├── login_screen.dart        # 登录页（选角色+微信登录）
│   ├── parent_home_screen.dart  # 老人端首页（语音输入+提醒列表）
│   ├── child_home_screen.dart   # 子女端首页（状态+设提醒）
│   └── bind_screen.dart         # 配对绑定
├── services/
│   ├── api_service.dart         # 后端API对接
│   ├── voice_service.dart       # 语音录制+识别
│   ├── alarm_service.dart       # 系统闹钟+铃声
│   └── notification_service.dart # 通知服务
└── widgets/
    └── reminder_card.dart       # 提醒卡片组件
```

## 自动编译
推送到main分支会自动触发GitHub Actions编译APK，编译完成后在Releases中下载。

## 后端
对接Coze后端API，地址见 api_service.dart 中的 baseUrl。
