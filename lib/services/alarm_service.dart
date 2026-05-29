import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:android_alarm_manager_plus/android_alarm_manager_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:audioplayers/audioplayers.dart';
import '../models/app_models.dart';

/// 闹钟+通知服务
class AlarmService {
  static final AlarmService _instance = AlarmService._();
  factory AlarmService() => _instance;
  AlarmService._();
  
  final FlutterLocalNotificationsPlugin _notifications = FlutterLocalNotificationsPlugin();
  final AudioPlayer _audioPlayer = AudioPlayer();
  
  Future<void> init() async {
    // 初始化闹钟管理器
    await AndroidAlarmManager.initialize();
    
    // 初始化本地通知
    const androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');
    const iosSettings = DarwinInitializationSettings();
    const settings = InitializationSettings(android: androidSettings, iOS: iosSettings);
    
    await _notifications.initialize(
      settings,
      onDidReceiveNotificationResponse: _onNotificationTap,
    );
  }
  
  /// 注册提醒闹钟
  Future<void> scheduleReminder(ReminderModel reminder) async {
    final id = reminder.reminderId.hashCode;
    final triggerTime = reminder.triggerTime;
    
    // 如果时间已过，不注册
    if (triggerTime.isBefore(DateTime.now())) return;
    
    await AndroidAlarmManager.oneShotAt(
      triggerTime,
      id,
      _alarmCallback,
      alarmInfo: AndroidAlarmInfo(
        '念念不忘提醒',
        '到了该${reminder.content}的时间了',
      ),
      exact: true,
      wakeup: true,
      allowWhileIdle: true,
      rescheduleOnReboot: true,
    );
  }
  
  /// 注册重复提醒闹钟
  Future<void> scheduleRepeatingReminder(ReminderModel reminder) async {
    final id = reminder.reminderId.hashCode;
    
    if (reminder.repeatType == 'daily') {
      // 每天重复
      await AndroidAlarmManager.periodic(
        const Duration(hours: 24),
        id,
        _alarmCallback,
        startAt: reminder.triggerTime,
        exact: true,
        wakeup: true,
        allowWhileIdle: true,
        rescheduleOnReboot: true,
      );
    }
  }
  
  /// 取消闹钟
  Future<void> cancelAlarm(String reminderId) async {
    final id = reminderId.hashCode;
    await AndroidAlarmManager.cancel(id);
  }
  
  /// 闹钟触发回调（顶层函数）
  @pragma('vm:entry-point')
  static void _alarmCallback() {
    // 这里会触发全屏通知
    // 实际逻辑在 NotificationService 中处理
  }
  
  /// 显示全屏提醒通知
  Future<void> showFullScreenReminder(ReminderModel reminder) async {
    const androidDetails = AndroidNotificationDetails(
      'reminder_channel',
      '提醒通知',
      channelDescription: '提醒到点响铃',
      importance: Importance.max,
      priority: Priority.max,
      fullScreenIntent: true,
      autoCancel: false,
      ongoing: true,
    );
    
    const iosDetails = DarwinNotificationDetails();
    const details = NotificationDetails(android: androidDetails, iOS: iosDetails);
    
    await _notifications.show(
      reminder.reminderId.hashCode,
      '念念不忘',
      reminder.content,
      details,
    );
  }
  
  /// 播放铃声
  Future<void> playAlarmSound({bool isUrgent = false}) async {
    final soundFile = isUrgent ? 'alarm_urgent.mp3' : 'alarm_normal.mp3';
    await _audioPlayer.play(AssetSource('sounds/$soundFile'));
    await _audioPlayer.setReleaseMode(ReleaseMode.loop);
  }
  
  /// 停止铃声
  Future<void> stopAlarmSound() async {
    await _audioPlayer.stop();
  }
  
  /// 播放原声
  Future<void> playVoice(String voiceUrl) async {
    await _audioPlayer.play(UrlSource(voiceUrl));
  }
  
  void _onNotificationTap(NotificationResponse response) {
    // 点击通知后打开APP对应页面
    // TODO: 实现导航到提醒详情
  }
}
