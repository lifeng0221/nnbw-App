import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:permission_handler/permission_handler.dart';
import '../models/app_models.dart';
import 'local_storage_service.dart';

/// Bug 4 & 6 修复: 闹钟+通知服务 — 定时轮询 + 通知 + 铃声
/// Bug 4: snooze后triggerTime更新，状态改回pending
/// Bug 6: 立即检查过期提醒，轮询逻辑改进
class AlarmService {
  static final AlarmService _instance = AlarmService._();
  factory AlarmService() => _instance;
  AlarmService._();

  final FlutterLocalNotificationsPlugin _notifications = FlutterLocalNotificationsPlugin();
  final AudioPlayer _audioPlayer = AudioPlayer();
  final LocalStorageService _storage = LocalStorageService();
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

  /// Bug 6 修复: 启动定时检查
  /// 前台每30秒轮询一次
  /// 不再立即检查——避免加载时就触发过期提醒显示"已响铃"
  void startChecking(List<ReminderModel> reminders) {
    _reminders = reminders;
    _checkTimer?.cancel();
    _checkTimer = Timer.periodic(const Duration(seconds: 30), (_) => _checkReminders());
    // 不再立即调用_checkReminders()
    // 只检查未来到期的提醒，过去已过期的由用户手动处理
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

  /// 轮询检查逻辑
  /// 只触发当前轮询周期内到期的提醒（triggerTime在过去30秒到未来之间）
  /// 避免触发很久以前就应该响的旧提醒
  void _checkReminders() {
    final now = DateTime.now();
    final toTrigger = <ReminderModel>[];

    for (final r in _reminders) {
      // 只处理pending和snoozed状态
      if (r.status == 'pending' || r.status == 'snoozed') {
        // 只触发：triggerTime在过去60秒到未来之间
        // 避免触发旧数据（之前因时间解析bug创建的过期提醒）
        final diff = now.difference(r.triggerTime);
        if (diff.inSeconds >= 0 && diff.inSeconds <= 60) {
          toTrigger.add(r);
        }
      }
    }

    // 批量触发
    for (final r in toTrigger) {
      _triggerReminder(r);
    }
  }

  /// 触发提醒
  Future<void> _triggerReminder(ReminderModel reminder) async {
    // Bug 6 修复: 1. 先更新状态为triggered
    await _storage.updateReminderStatus(reminder.reminderId, 'triggered');

    // 2. 发通知
    await showReminderNotification(reminder);

    // 3. 播放铃声
    await playAlarmSound(isUrgent: reminder.isUrgent);

    // 4. 回调通知UI刷新
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

  /// Bug 6 修复: 播放铃声，改进错误处理
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
