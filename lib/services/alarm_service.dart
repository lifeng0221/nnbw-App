import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:permission_handler/permission_handler.dart';
import '../models/app_models.dart';
import 'local_storage_service.dart';

/// 闹钟+通知服务 v1.0.27
/// 核心改动：
/// - 修复：初始化必须在Flutter引擎就绪后（不在main()中）
/// - 修复：print替代debugPrint确保release模式可见
/// - 新增：诊断信息（isRunning, monitoredCount, lastCheckTime等）
/// - 新增：UI回调 onDiagnosticUpdate 供首页显示闹钟状态
/// - 修复：Timer确保在startChecking时启动，不依赖外部调用顺序
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
  
  // 🔧 v1.0.27 诊断信息
  bool _initialized = false;
  bool get isInitialized => _initialized;
  bool get isRunning => _checkTimer != null && _checkTimer!.isActive;
  int get monitoredCount => _reminders.length;
  int get pendingCount => _reminders.where((r) => r.status == 'pending' || r.status == 'snoozed').length;
  DateTime? lastCheckTime;
  String? lastCheckResult; // 诊断文字
  int triggerCount = 0; // 已触发次数
  Function? onDiagnosticUpdate; // UI刷新回调

  Future<void> init() async {
    if (_initialized) {
      print('🟢 AlarmService已初始化，跳过');
      return;
    }

    print('🟢 AlarmService开始初始化...');

    // 请求通知权限（Android 13+）
    await _requestNotificationPermission();

    const androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');
    const iosSettings = DarwinInitializationSettings();
    const settings = InitializationSettings(android: androidSettings, iOS: iosSettings);
    final initResult = await _notifications.initialize(
      settings,
      onDidReceiveNotificationResponse: _onNotificationTapped,
    );
    print('🟢 通知初始化结果: $initResult');

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
    print('🟢 AlarmService初始化完成');
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

  void _onNotificationTapped(NotificationResponse response) {
    // 通知点击回调
  }

  /// 启动定时检查 — 每次loadReminders都调用，更新提醒列表
  void startChecking(List<ReminderModel> reminders) {
    _reminders = List.from(reminders); // 浅拷贝，避免外部修改
    print('🟢 AlarmService: 更新提醒列表，共${reminders.length}条，pending=${reminders.where((r) => r.status == "pending").length}条');
    
    // 🔧 v1.0.27: 总是确保timer在运行
    if (_checkTimer == null || !_checkTimer!.isActive) {
      _checkTimer?.cancel();
      _checkTimer = Timer.periodic(const Duration(seconds: 10), (_) => _checkReminders());
      print('🟢 AlarmService: 启动10秒轮询');
    }
    // 立即检查一次
    _checkReminders();
    
    _notifyDiagnostic();
  }

  /// 停止定时检查
  void stopChecking() {
    _checkTimer?.cancel();
    _checkTimer = null;
    _notifyDiagnostic();
  }

  /// 更新提醒列表（不重启timer）
  void updateReminders(List<ReminderModel> reminders) {
    _reminders = List.from(reminders);
    _notifyDiagnostic();
  }

  /// 清除已触发ID（snooze后需要重新触发）
  void clearTriggeredId(String reminderId) {
    _triggeredIds.remove(reminderId);
    print('🟢 AlarmService: 清除触发ID $reminderId（允许重新触发）');
  }

  /// 通知UI刷新诊断信息
  void _notifyDiagnostic() {
    onDiagnosticUpdate?.call();
  }

  /// 获取诊断文字
  String get diagnosticText {
    if (!_initialized) return '闹钟未初始化';
    if (!isRunning) return '闹钟未启动';
    final p = pendingCount;
    final t = triggerCount;
    final last = lastCheckTime != null 
        ? '${lastCheckTime!.hour}:${lastCheckTime!.minute.toString().padLeft(2,"0")}:${lastCheckTime!.second.toString().padLeft(2,"0")}'
        : '无';
    return '监听${monitoredCount}条 | 待响$p | 已触发$t | 上次检查$last';
  }

  /// 轮询检查逻辑
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
      
      // triggerTime已到（当前时间 >= 提醒时间）
      if (!now.isBefore(r.triggerTime)) {
        pastDueCount++;
        toTrigger.add(r);
        _triggeredIds.add(r.reminderId);
      }
    }
    
    // 🔧 v1.0.27: 总是更新诊断信息
    lastCheckResult = '总${_reminders.length}条, $pendingCount条待响, $alreadyTriggeredCount条已触发过, $pastDueCount条到期, ${toTrigger.length}条即将触发';
    if (pendingCount > 0) {
      print('🟢 轮询[$now]: $lastCheckResult');
      for (final r in toTrigger) {
        print('🟢   → 将触发: "${r.content}" triggerTime=${r.triggerTime} now=$now diff=${now.difference(r.triggerTime).inMinutes}分钟');
      }
      // 打印所有pending提醒的详情
      for (final r in _reminders) {
        if (r.status == 'pending' || r.status == 'snoozed') {
          final diff = now.difference(r.triggerTime);
          print('🟢   → 待响: "${r.content}" trigger=${r.triggerTime} diff=${diff.inMinutes}分钟 ${diff.isNegative ? "未到" : "已过"} triggeredId=${_triggeredIds.contains(r.reminderId)}');
        }
      }
    } else if (_reminders.isEmpty) {
      print('🟡 轮询[$now]: 提醒列表为空！没有数据传给AlarmService');
    } else {
      // 有提醒但没有pending的
      final statuses = _reminders.map((r) => r.status).toSet().toList();
      print('🟢 轮询[$now]: ${_reminders.length}条提醒, 状态分布=$statuses, 无待响');
    }

    // 批量触发
    for (final r in toTrigger) {
      _triggerReminderSafely(r);
    }
    
    // 清理过旧的已触发ID（超过2小时的）
    _triggeredIds.removeWhere((id) {
      final r = _reminders.where((r) => r.reminderId == id).firstOrNull;
      return r == null || now.difference(r.triggerTime).inHours >= 2;
    });
    
    _notifyDiagnostic();
  }

  /// 安全触发提醒（不抛异常，失败时移除triggeredId允许重试）
  Future<void> _triggerReminderSafely(ReminderModel reminder) async {
    try {
      await _triggerReminder(reminder);
    } catch (e, stackTrace) {
      print('🔴 触发提醒失败，移除triggeredId允许重试: ${reminder.content}, 错误: $e');
      print('🔴 堆栈: $stackTrace');
      _triggeredIds.remove(reminder.reminderId);
    }
  }

  /// 触发提醒
  Future<void> _triggerReminder(ReminderModel reminder) async {
    print('=== 🔔 触发提醒: "${reminder.content}" (${reminder.triggerTime}) ===');
    triggerCount++;
    
    // 1. 先更新状态为triggered
    try {
      final updated = await _storage.updateReminderStatus(reminder.reminderId, 'triggered');
      print('🟢 状态更新结果: $updated, reminderId=${reminder.reminderId}');
    } catch (e) {
      print('🔴 状态更新失败: $e');
    }

    // 2. 发通知
    try {
      await showReminderNotification(reminder);
    } catch (e) {
      print('🔴 通知发送失败（不影响状态）: $e');
    }

    // 3. 播放铃声
    try {
      await playAlarmSound(isUrgent: reminder.isUrgent);
    } catch (e) {
      print('🔴 铃声播放失败（不影响状态）: $e');
    }

    // 4. 回调通知UI刷新
    onReminderTriggered?.call(reminder);
    _notifyDiagnostic();
    print('🟢 提醒触发完成: ${reminder.content}');
  }

  Future<void> showReminderNotification(ReminderModel reminder) async {
    const androidDetails = AndroidNotificationDetails(
      'reminder_channel', '提醒通知',
      channelDescription: '到点提醒通知',
      importance: Importance.max,
      priority: Priority.max,
      playSound: true,
      enableVibration: true,
    );
    const details = NotificationDetails(android: androidDetails, iOS: DarwinNotificationDetails());
    try {
      await _notifications.show(
        reminder.reminderId.hashCode,
        '⏰ 念念不忘提醒',
        reminder.content,
        details,
      );
      print('🟢 通知已发送: ${reminder.content}');
    } catch (e) {
      print('🔴 通知发送失败: $e');
    }
  }

  /// 播放铃声
  Future<void> playAlarmSound({bool isUrgent = false}) async {
    print('🟢 播放铃声: isUrgent=$isUrgent, initialized=$_initialized');
    try {
      await _audioPlayer.stop();
      await _audioPlayer.play(AssetSource('sounds/${isUrgent ? "alarm_urgent" : "alarm_normal"}.mp3'));
      print('🟢 铃声播放成功');
    } catch (e) {
      print('🔴 播放铃声失败: $e');
      try {
        await _audioPlayer.stop();
        await _audioPlayer.play(AssetSource('sounds/alarm_normal.mp3'));
        print('🟢 备用铃声播放成功');
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
