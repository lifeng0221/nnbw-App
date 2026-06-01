import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:permission_handler/permission_handler.dart';
import '../models/app_models.dart';
import 'local_storage_service.dart';

/// 闹钟+通知服务
/// 核心逻辑：
/// - 每次加载提醒列表时更新轮询数据
/// - 每10秒轮询一次，检查pending/snoozed且到期的提醒
/// - 触发时：更新状态→发通知→响铃→回调UI刷新
/// - 用Set记录已触发的reminderId，避免重复触发
class AlarmService {
  static final AlarmService _instance = AlarmService._();
  factory AlarmService() => _instance;
  AlarmService._();

  final FlutterLocalNotificationsPlugin _notifications = FlutterLocalNotificationsPlugin();
  final AudioPlayer _audioPlayer = AudioPlayer();
  final LocalStorageService _storage = LocalStorageService();
  Timer? _checkTimer;
  List<ReminderModel> _reminders = [];
  final Set<String> _triggeredIds = {}; // 本轮已触发的ID，防重复
  Function(ReminderModel)? onReminderTriggered;

  bool _initialized = false;

  Future<void> init() async {
    if (_initialized) {
      debugPrint('🟢 AlarmService已初始化，跳过');
      return;
    }

    debugPrint('🟢 AlarmService开始初始化...');

    // 请求通知权限（Android 13+）
    await _requestNotificationPermission();

    const androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');
    const iosSettings = DarwinInitializationSettings();
    const settings = InitializationSettings(android: androidSettings, iOS: iosSettings);
    final initResult = await _notifications.initialize(
      settings,
      onDidReceiveNotificationResponse: _onNotificationTapped,
    );
    debugPrint('🟢 通知初始化结果: $initResult');

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
    debugPrint('🟢 AlarmService初始化完成');
  }

  Future<void> _requestNotificationPermission() async {
    if (await Permission.notification.isDenied) {
      await Permission.notification.request();
    }
    if (await Permission.scheduleExactAlarm.isDenied) {
      await Permission.scheduleExactAlarm.request();
    }
  }

  void _onNotificationTapped(NotificationResponse response) {
    // 通知点击回调
  }

  /// 启动定时检查 — 每次loadReminders都调用，更新提醒列表
  void startChecking(List<ReminderModel> reminders) {
    _reminders = reminders;
    debugPrint('🟢 AlarmService: 更新提醒列表，共${reminders.length}条');
    // 只在第一次启动timer，后续只更新数据
    if (_checkTimer == null || !_checkTimer!.isActive) {
      _checkTimer?.cancel();
      _checkTimer = Timer.periodic(const Duration(seconds: 10), (_) => _checkReminders());
      debugPrint('🟢 AlarmService: 启动10秒轮询');
      // 立即检查一次
      _checkReminders();
    }
  }

  /// 停止定时检查
  void stopChecking() {
    _checkTimer?.cancel();
    _checkTimer = null;
  }

  /// 更新提醒列表（不重启timer）
  void updateReminders(List<ReminderModel> reminders) {
    _reminders = reminders;
  }

  /// 轮询检查逻辑
  /// 触发条件：pending/snoozed 且 triggerTime <= now 且 未在本轮触发过
  void _checkReminders() {
    final now = DateTime.now();
    final toTrigger = <ReminderModel>[];
    
    int pendingCount = 0;
    int alreadyTriggeredCount = 0;
    
    for (final r in _reminders) {
      if (r.status != 'pending' && r.status != 'snoozed') continue;
      pendingCount++;
      if (_triggeredIds.contains(r.reminderId)) { alreadyTriggeredCount++; continue; }
      
      // triggerTime已到（当前时间 >= 提醒时间）
      if (!now.isBefore(r.triggerTime)) {
        toTrigger.add(r);
        _triggeredIds.add(r.reminderId);
      }
    }
    
    if (pendingCount > 0) {
      debugPrint('🟢 轮询: ${_reminders.length}条提醒, $pendingCount条待响, $alreadyTriggeredCount条已触发, ${toTrigger.length}条即将触发');
    }

    // 批量触发
    for (final r in toTrigger) {
      _triggerReminder(r);
    }
    
    // 清理过旧的已触发ID（超过1小时的）
    _triggeredIds.removeWhere((id) {
      final r = _reminders.where((r) => r.reminderId == id).firstOrNull;
      return r == null || now.difference(r.triggerTime).inHours >= 1;
    });
  }

  /// 触发提醒
  Future<void> _triggerReminder(ReminderModel reminder) async {
    debugPrint('=== 触发提醒: ${reminder.content} (${reminder.triggerTime}) ===');
    
    // 1. 先更新状态为triggered
    await _storage.updateReminderStatus(reminder.reminderId, 'triggered');

    // 2. 发通知
    await showReminderNotification(reminder);

    // 3. 播放铃声
    await playAlarmSound(isUrgent: reminder.isUrgent);

    // 4. 回调通知UI刷新
    onReminderTriggered?.call(reminder);
  }

  Future<void> showReminderNotification(ReminderModel reminder) async {
    // 使用默认通知声音（避免RawResource路径问题）
    const androidDetails = AndroidNotificationDetails(
      'reminder_channel', '提醒通知',
      channelDescription: '到点提醒通知',
      importance: Importance.max,
      priority: Priority.max,
      playSound: true,
      enableVibration: true,
      // 不指定自定义sound，用渠道默认声音
    );
    const details = NotificationDetails(android: androidDetails, iOS: DarwinNotificationDetails());
    try {
      await _notifications.show(
        reminder.reminderId.hashCode,
        '⏰ 念念不忘提醒',
        reminder.content,
        details,
      );
      debugPrint('🟢 通知已发送: ${reminder.content}');
    } catch (e) {
      debugPrint('🔴 通知发送失败: $e');
    }
  }

  /// 播放铃声
  Future<void> playAlarmSound({bool isUrgent = false}) async {
    debugPrint('🟢 播放铃声: isUrgent=$isUrgent, initialized=$_initialized');
    try {
      // 先确保audioplayer状态正常
      await _audioPlayer.stop();
      await _audioPlayer.play(AssetSource('sounds/${isUrgent ? "alarm_urgent" : "alarm_normal"}.mp3'));
      debugPrint('🟢 铃声播放成功');
    } catch (e) {
      debugPrint('🔴 播放铃声失败: $e');
      // 尝试播放系统默认声音
      try {
        await _audioPlayer.stop();
        await _audioPlayer.play(AssetSource('sounds/alarm_normal.mp3'));
        debugPrint('🟢 备用铃声播放成功');
      } catch (e2) {
        debugPrint('🔴 备用铃声也失败: $e2');
        // 最后尝试播放系统通知声
        try {
          await _audioPlayer.play(UrlSource('https://assets.mixkit.co/sfx/preview/286/286-preview.mp3'));
        } catch (e3) {
          debugPrint('🔴 所有铃声方案都失败: $e3');
        }
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
