import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:audioplayers/audioplayers.dart';
import '../models/app_models.dart';

/// 闹钟+通知服务（简化版，先跑通编译）
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
    await _notifications.initialize(settings);
  }
  
  Future<void> showReminderNotification(ReminderModel reminder) async {
    const androidDetails = AndroidNotificationDetails(
      'reminder_channel', '提醒通知',
      importance: Importance.max, priority: Priority.max,
    );
    const details = NotificationDetails(android: androidDetails, iOS: DarwinNotificationDetails());
    await _notifications.show(reminder.reminderId.hashCode, '念念不忘', reminder.content, details);
  }
  
  Future<void> playAlarmSound({bool isUrgent = false}) async {
    try {
      await _audioPlayer.play(AssetSource('sounds/${isUrgent ? "alarm_urgent" : "alarm_normal"}.mp3'));
    } catch (e) {}
  }
  
  Future<void> stopAlarmSound() async => await _audioPlayer.stop();
  Future<void> playVoice(String voiceUrl) async => await _audioPlayer.play(UrlSource(voiceUrl));
}
