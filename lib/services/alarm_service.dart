import 'package:flutter_local_notifications/flutter_local_notifications.dart';
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
    const androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');
    const iosSettings = DarwinInitializationSettings();
    const settings = InitializationSettings(android: androidSettings, iOS: iosSettings);
    
    await _notifications.initialize(settings, onDidReceiveNotificationResponse: _onNotificationTap);
  }
  
  /// 显示提醒通知
  Future<void> showReminderNotification(ReminderModel reminder) async {
    const androidDetails = AndroidNotificationDetails(
      'reminder_channel',
      '提醒通知',
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
    try {
      await _audioPlayer.play(AssetSource('sounds/$soundFile'));
      await _audioPlayer.setReleaseMode(ReleaseMode.loop);
    } catch (e) {
      // Fallback: use system default
    }
  }
  
  /// 停止铃声
  Future<void> stopAlarmSound() async {
    await _audioPlayer.stop();
  }
  
  /// 播放原声
  Future<void> playVoice(String voiceUrl) async {
    await _audioPlayer.play(UrlSource(voiceUrl));
  }
  
  void _onNotificationTap(NotificationResponse response) {}
}
