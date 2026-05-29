import 'package:flutter_local_notifications/flutter_local_notifications.dart';

/// 通知服务（FCM + 本地通知）
class NotificationService {
  static final NotificationService _instance = NotificationService._();
  factory NotificationService() => _instance;
  NotificationService._();
  
  final FlutterLocalNotificationsPlugin _plugin = FlutterLocalNotificationsPlugin();
  
  Future<void> init() async {
    const androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');
    const iosSettings = DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
    );
    const settings = InitializationSettings(android: androidSettings, iOS: iosSettings);
    
    await _plugin.initialize(
      settings,
      onDidReceiveNotificationResponse: _onTap,
    );
    
    // 创建通知渠道
    await _createChannels();
  }
  
  Future<void> _createChannels() async {
    const channels = [
      AndroidNotificationChannel(
        'reminder_channel',
        '提醒通知',
        description: '提醒到点响铃',
        importance: Importance.max,
      ),
      AndroidNotificationChannel(
        'alert_channel',
        '协同告警',
        description: '老人未确认时通知子女',
        importance: Importance.high,
      ),
    ];
    
    final androidPlugin = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    
    for (final channel in channels) {
      await androidPlugin?.createNotificationChannel(channel);
    }
  }
  
  /// 显示普通提醒通知
  Future<void> showReminderNotification({
    required int id,
    required String title,
    required String body,
  }) async {
    const androidDetails = AndroidNotificationDetails(
      'reminder_channel',
      '提醒通知',
      importance: Importance.max,
      priority: Priority.max,
      autoCancel: true,
    );
    const iosDetails = DarwinNotificationDetails();
    const details = NotificationDetails(android: androidDetails, iOS: iosDetails);
    
    await _plugin.show(id, title, body, details);
  }
  
  /// 显示协同告警通知
  Future<void> showAlertNotification({
    required int id,
    required String title,
    required String body,
  }) async {
    const androidDetails = AndroidNotificationDetails(
      'alert_channel',
      '协同告警',
      importance: Importance.high,
      priority: Priority.high,
      autoCancel: true,
    );
    const iosDetails = DarwinNotificationDetails();
    const details = NotificationDetails(android: androidDetails, iOS: iosDetails);
    
    await _plugin.show(id, title, body, details);
  }
  
  void _onTap(NotificationResponse response) {
    // 处理通知点击
  }
}
