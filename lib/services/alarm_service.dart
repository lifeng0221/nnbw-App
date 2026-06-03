import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:permission_handler/permission_handler.dart';
import '../models/app_models.dart';
import 'local_storage_service.dart';

/// 闹钟+通知服务 v1.0.28
/// 核心改动：
/// - init()用try-catch包裹，任何异常都不阻塞后续逻辑
/// - 通知/铃声功能降级：init失败后轮询仍正常工作，只是不发通知/不响铃
/// - _initialized改为表示"轮询可用"，不依赖通知插件
/// - 诊断信息更完整
class AlarmService {
  static final AlarmService _instance = AlarmService._();
  factory AlarmService() => _instance;
  AlarmService._();

  final FlutterLocalNotificationsPlugin _notifications = FlutterLocalNotificationsPlugin();
  final AudioPlayer _audioPlayer = AudioPlayer();
  final LocalStorageService _storage = LocalStorageService();
  Timer? _checkTimer;
  List<ReminderModel> _reminders = [];
  final Set<String> _triggeredIds = {};
  Function(ReminderModel)? onReminderTriggered;
  
  // 诊断
  bool _initialized = false;
  bool _notificationReady = false; // 通知插件是否就绪
  bool get isInitialized => _initialized;
  bool get notificationReady => _notificationReady;
  bool get isRunning => _checkTimer != null && _checkTimer!.isActive;
  int get monitoredCount => _reminders.length;
  int get pendingCount => _reminders.where((r) => r.status == 'pending' || r.status == 'snoozed').length;
  DateTime? lastCheckTime;
  String? lastCheckResult;
  int triggerCount = 0;
  String? initError; // 初始化错误信息
  Function? onDiagnosticUpdate;

  Future<void> init() async {
    if (_initialized) {
      print('🟢 AlarmService已初始化，跳过');
      return;
    }

    print('🟢 AlarmService开始初始化...');
    
    // 🔧 v1.0.28: 先标记initialized，确保轮询始终可用
    // 通知/铃声是增强功能，失败不影响核心触发逻辑
    _initialized = true;
    
    // 请求权限（不阻塞）
    try {
      await _requestNotificationPermission();
    } catch (e) {
      print('🔴 权限请求异常（不影响轮询）: $e');
      initError = '权限异常: $e';
    }

    // 初始化通知插件
    try {
      const androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');
      const iosSettings = DarwinInitializationSettings();
      const settings = InitializationSettings(android: androidSettings, iOS: iosSettings);
      final initResult = await _notifications.initialize(
        settings,
        onDidReceiveNotificationResponse: _onNotificationTapped,
      );
      print('🟢 通知初始化结果: $initResult');

      // 创建通知渠道
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
      
      _notificationReady = true;
      print('🟢 AlarmService初始化完成（通知就绪）');
    } catch (e) {
      print('🔴 通知初始化失败（不影响轮询）: $e');
      _notificationReady = false;
      initError = '通知初始化失败: $e';
      // 关键：不抛异常，轮询仍然工作
    }
    
    _notifyDiagnostic();
  }

  Future<void> _requestNotificationPermission() async {
    try {
      if (await Permission.notification.isDenied) {
        await Permission.notification.request();
      }
      if (await Permission.scheduleExactAlarm.isDenied) {
        await Permission.scheduleExactAlarm.request();
      }
    } catch (e) {
      print('🔴 权限请求异常: $e');
    }
  }

  void _onNotificationTapped(NotificationResponse response) {}

  void startChecking(List<ReminderModel> reminders) {
    _reminders = List.from(reminders);
    print('🟢 AlarmService: 更新提醒列表，共${reminders.length}条，pending=${reminders.where((r) => r.status == "pending").length}条');
    
    if (_checkTimer == null || !_checkTimer!.isActive) {
      _checkTimer?.cancel();
      _checkTimer = Timer.periodic(const Duration(seconds: 10), (_) => _checkReminders());
      print('🟢 AlarmService: 启动10秒轮询');
    }
    _checkReminders();
    _notifyDiagnostic();
  }

  void stopChecking() {
    _checkTimer?.cancel();
    _checkTimer = null;
    _notifyDiagnostic();
  }

  void updateReminders(List<ReminderModel> reminders) {
    _reminders = List.from(reminders);
    _notifyDiagnostic();
  }

  void clearTriggeredId(String reminderId) {
    _triggeredIds.remove(reminderId);
    print('🟢 AlarmService: 清除触发ID $reminderId');
  }

  void _notifyDiagnostic() {
    onDiagnosticUpdate?.call();
  }

  String get diagnosticText {
    if (!_initialized) return '闹钟未初始化';
    if (!isRunning) return '闹钟未启动';
    if (!_notificationReady) return '⚠️轮询正常(通知未就绪) | 监听$monitoredCount条 | 待响$pendingCount';
    final p = pendingCount;
    final t = triggerCount;
    final last = lastCheckTime != null 
        ? '${lastCheckTime!.hour}:${lastCheckTime!.minute.toString().padLeft(2,"0")}:${lastCheckTime!.second.toString().padLeft(2,"0")}'
        : '无';
    return '✅监听$monitoredCount条 | 待响$p | 已触发$t | $last';
  }

  void _checkReminders() {
    final now = DateTime.now();
    lastCheckTime = now;
    final toTrigger = <ReminderModel>[];
    
    int pendingCount = 0;
    int alreadyTriggeredCount = 0;
    int pastDueCount = 0;
    
    for (final r in _reminders) {
      if (r.status != 'pending' && r.status != 'snoozed') continue;
      pendingCount++;
      if (_triggeredIds.contains(r.reminderId)) { alreadyTriggeredCount++; continue; }
      
      if (!now.isBefore(r.triggerTime)) {
        pastDueCount++;
        toTrigger.add(r);
        _triggeredIds.add(r.reminderId);
      }
    }
    
    lastCheckResult = '总${_reminders.length}条, $pendingCount条待响, $alreadyTriggeredCount条已触发过, $pastDueCount条到期, ${toTrigger.length}条即将触发';
    if (pendingCount > 0 || _reminders.isEmpty) {
      print('🟢 轮询[$now]: $lastCheckResult');
      for (final r in toTrigger) {
        final diff = now.difference(r.triggerTime);
        print('🟢   → 触发: "${r.content}" trigger=${r.triggerTime} diff=${diff.inMinutes}分钟');
      }
      for (final r in _reminders) {
        if (r.status == 'pending' || r.status == 'snoozed') {
          final diff = now.difference(r.triggerTime);
          print('🟢   → 待响: "${r.content}" trigger=${r.triggerTime} ${diff.isNegative ? "还${-diff.inMinutes}分钟" : "已过${diff.inMinutes}分钟"}');
        }
      }
    } else if (_reminders.isEmpty) {
      print('🟡 轮询: 提醒列表为空！');
    }

    for (final r in toTrigger) {
      _triggerReminderSafely(r);
    }
    
    _triggeredIds.removeWhere((id) {
      final r = _reminders.where((r) => r.reminderId == id).firstOrNull;
      return r == null || now.difference(r.triggerTime).inHours >= 2;
    });
    
    _notifyDiagnostic();
  }

  Future<void> _triggerReminderSafely(ReminderModel reminder) async {
    try {
      await _triggerReminder(reminder);
    } catch (e, stackTrace) {
      print('🔴 触发提醒失败: ${reminder.content}, 错误: $e');
      _triggeredIds.remove(reminder.reminderId);
    }
  }

  Future<void> _triggerReminder(ReminderModel reminder) async {
    print('=== 🔔 触发提醒: "${reminder.content}" (${reminder.triggerTime}) ===');
    triggerCount++;
    
    // 1. 更新状态
    try {
      await _storage.updateReminderStatus(reminder.reminderId, 'triggered');
      print('🟢 状态已更新为triggered');
    } catch (e) {
      print('🔴 状态更新失败: $e');
    }

    // 2. 发通知（降级：失败不阻塞）
    if (_notificationReady) {
      try {
        await showReminderNotification(reminder);
      } catch (e) {
        print('🔴 通知发送失败（不影响状态）: $e');
      }
    } else {
      print('🟡 通知插件未就绪，跳过通知');
    }

    // 3. 播放铃声（降级：失败不阻塞）
    try {
      await playAlarmSound(isUrgent: reminder.isUrgent);
    } catch (e) {
      print('🔴 铃声播放失败（不影响状态）: $e');
    }

    // 4. 回调UI刷新
    onReminderTriggered?.call(reminder);
    _notifyDiagnostic();
    print('🟢 提醒触发完成: ${reminder.content}');
  }

  Future<void> showReminderNotification(ReminderModel reminder) async {
    if (!_notificationReady) return;
    
    // v1.0.40: 增强通知配置，支持全屏Intent
    final androidDetails = AndroidNotificationDetails(
      'reminder_channel', '提醒通知',
      channelDescription: '到点提醒通知',
      importance: Importance.max,
      priority: Priority.max,
      playSound: true,
      enableVibration: true,
      // v1.0.40: 锁屏全屏弹出
      fullScreenIntent: true,
      category: AndroidNotificationCategory.alarm,
      visibility: NotificationVisibility.public,
      // v1.0.40: 超时自动消失
      timeoutAfter: 60000, // 1分钟
      styleInformation: BigTextStyleInformation(
        reminder.content,
        contentTitle: '⏰ 念念不忘提醒',
        summaryText: '点击查看详情',
      ),
    );
    final details = NotificationDetails(android: androidDetails, iOS: DarwinNotificationDetails());
    try {
      // v1.0.40: 使用不同的通知ID范围，避免与后台服务冲突
      final notificationId = reminder.reminderId.hashCode.abs() % 100000;
      await _notifications.show(
        notificationId,
        '⏰ 念念不忘提醒',
        reminder.content,
        details,
      );
      print('🟢 通知已发送: ${reminder.content}');
    } catch (e) {
      print('🔴 通知发送失败: $e');
    }
  }

  Future<void> playAlarmSound({bool isUrgent = false}) async {
    print('🟢 播放铃声: isUrgent=$isUrgent');
    try {
      await _audioPlayer.stop();
      await _audioPlayer.play(AssetSource('sounds/${isUrgent ? "alarm_urgent" : "alarm_normal"}.mp3'));
      print('🟢 铃声播放成功');
    } catch (e) {
      print('🔴 播放铃声失败: $e');
      try {
        await _audioPlayer.stop();
        await _audioPlayer.play(AssetSource('sounds/alarm_normal.mp3'));
      } catch (e2) {
        print('🔴 备用铃声也失败: $e2');
        try {
          await _audioPlayer.play(UrlSource('https://assets.mixkit.co/sfx/preview/286/286-preview.mp3'));
        } catch (e3) {
          print('🔴 所有铃声方案都失败: $e3');
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
