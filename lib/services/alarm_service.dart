import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:permission_handler/permission_handler.dart';
import '../models/app_models.dart';

/// 闹钟+通知服务 — 定时轮询 + 通知 + 铃声
class AlarmService {
  static final AlarmService _instance = AlarmService._();
  factory AlarmService() => _instance;
  AlarmService._();

  final FlutterLocalNotificationsPlugin _notifications = FlutterLocalNotificationsPlugin();
  final AudioPlayer _audioPlayer = AudioPlayer();
  Timer? _checkTimer;
  List<ReminderModel> _reminders = [];
  Function(ReminderModel)? onReminderTriggered;

  bool _initialized = false;

  Future<void> init() async {
    if (_initialized) return;

    // 请求通知权限（Android 13+）
    await _requestNotificationPermission();

    const androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');
    const iosSettings = DarwinInitializationSettings();
    const settings = InitializationSettings(android: androidSettings, iOS: iosSettings);
    await _notifications.initialize(
      settings,
      onDidReceiveNotificationResponse: _onNotificationTapped,
    );

    // 创建通知渠道（高优先级+声音）
    const androidChannel = AndroidNotificationChannel(
      'reminder_channel',
      '提醒通知',
      description: '到点提醒通知',
      importance: Importance.max,
      playSound: true,
      enableVibration: true,
    );
    await _notifications.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(androidChannel);

    _initialized = true;
  }

  Future<void> _requestNotificationPermission() async {
    if (await Permission.notification.isDenied) {
      await Permission.notification.request();
    }
    // 精确闹钟权限（Android 12+）
    if (await Permission.scheduleExactAlarm.isDenied) {
      await Permission.scheduleExactAlarm.request();
    }
  }

  void _onNotificationTapped(NotificationResponse response) {
    // 通知点击回调 — 可以后续做跳转
  }

  /// 启动定时检查（前台每30秒轮询一次）
  void startChecking(List<ReminderModel> reminders) {
    _reminders = reminders;
    _checkTimer?.cancel();
    _checkTimer = Timer.periodic(const Duration(seconds: 30), (_) => _checkReminders());
    // 立即检查一次
    _checkReminders();
  }

  /// 停止定时检查
  void stopChecking() {
    _checkTimer?.cancel();
    _checkTimer = null;
  }

  /// 更新提醒列表
  void updateReminders(List<ReminderModel> reminders) {
    _reminders = reminders;
  }

  void _checkReminders() {
    final now = DateTime.now();
    for (final r in _reminders) {
      if (r.status == 'pending') {
        // 触发时间已到（1分钟内的都算到点）
        final diff = now.difference(r.triggerTime).inMinutes;
        if (diff >= 0 && diff < 2) {
          _triggerReminder(r);
        }
      }
    }
  }

  Future<void> _triggerReminder(ReminderModel reminder) async {
    // 1. 发通知
    await showReminderNotification(reminder);

    // 2. 播放铃声
    await playAlarmSound(isUrgent: reminder.isUrgent);

    // 3. 回调通知UI刷新
    onReminderTriggered?.call(reminder);
  }

  Future<void> showReminderNotification(ReminderModel reminder) async {
    const androidDetails = AndroidNotificationDetails(
      'reminder_channel', '提醒通知',
      channelDescription: '到点提醒通知',
      importance: Importance.max,
      priority: Priority.max,
      playSound: true,
      enableVibration: true,
      // 使用系统默认提醒铃声
      sound: RawResourceAndroidNotificationSound('alarm_normal'),
      // 如果没有自定义音频，用系统默认
      // 不设置sound字段就会用渠道默认声音
    );
    const details = NotificationDetails(android: androidDetails, iOS: DarwinNotificationDetails());
    await _notifications.show(
      reminder.reminderId.hashCode,
      '⏰ 念念不忘提醒',
      reminder.content,
      details,
    );
  }

  Future<void> playAlarmSound({bool isUrgent = false}) async {
    try {
      // 先尝试播放自定义音频
      await _audioPlayer.play(AssetSource('sounds/${isUrgent ? "alarm_urgent" : "alarm_normal"}.mp3'));
    } catch (e) {
      // 自定义音频不存在时，播放系统默认铃声
      try {
        // 用系统通知声代替
        await _audioPlayer.play(AssetSource('sounds/alarm_default.mp3'));
      } catch (e2) {
        // 完全没有音频文件，通知本身会带系统默认声
      }
    }
  }

  Future<void> stopAlarmSound() async {
    await _audioPlayer.stop();
  }

  Future<void> playVoice(String voiceUrl) async {
    await _audioPlayer.play(UrlSource(voiceUrl));
  }

  void dispose() {
    _checkTimer?.cancel();
    _audioPlayer.dispose();
  }
}
