import 'dart:async';
import 'dart:convert';
import 'dart:ui';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 后台前台服务 v1.0.40
/// 实现APP在后台或息屏时仍能触发提醒
/// 在独立isolate中运行，通过SharedPreferences与主APP协调

// SharedPreferences key常量（与主APP保持一致）
const String _remindersKey = 'reminders';
const String _serverBindingIdKey = 'server_binding_id';

// 已触发的提醒ID集合（内存中，避免重复触发）
final Set<String> _triggeredReminderIds = {};

/// 前台服务入口函数（必须在顶层，带@pragma）
@pragma('vm:entry-point')
void backgroundServiceEntryPoint() {
  runBackgroundService();
}

/// 后台服务运行器
void runBackgroundService() {
  final service = FlutterBackgroundService();
  
  // 通知通道ID
  const String notificationChannelId = 'nnbw_background_service';
  const String reminderChannelId = 'nnbw_reminder_alarm';
  
  // 初始化通知插件
  final notifications = FlutterLocalNotificationsPlugin();
  
  // 配置通知
  void configureNotifications() async {
    const androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');
    const iosSettings = DarwinInitializationSettings();
    const settings = InitializationSettings(android: androidSettings, iOS: iosSettings);
    
    await notifications.initialize(
      settings,
      onDidReceiveNotificationResponse: (response) {
        print('[Background] 通知被点击: ${response.payload}');
      },
    );
    
    // 创建前台服务通知渠道
    const foregroundChannel = AndroidNotificationChannel(
      notificationChannelId,
      '念念不忘守护服务',
      description: '保持APP在后台正常运行，确保提醒准时触发',
      importance: Importance.low,
      playSound: false,
      enableVibration: false,
    );
    
    // 创建提醒通知渠道（高优先级，支持fullScreenIntent）
    const reminderChannel = AndroidNotificationChannel(
      reminderChannelId,
      '提醒通知',
      description: '到点提醒，锁屏时也能弹出',
      importance: Importance.max,
      playSound: true,
      enableVibration: true,
    );
    
    final androidPlugin = notifications.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    
    await androidPlugin?.createNotificationChannel(foregroundChannel);
    await androidPlugin?.createNotificationChannel(reminderChannel);
    
    // 启动前台服务通知
    await notifications.show(
      0, // 使用固定ID
      '念念不忘正在守护',
      '守护服务运行中，确保提醒准时触发',
      NotificationDetails(
        android: AndroidNotificationDetails(
          notificationChannelId,
          '念念不忘守护服务',
          channelDescription: '保持APP在后台正常运行',
          ongoing: true,
          autoCancel: false,
          importance: Importance.low,
          priority: Priority.low,
          icon: '@mipmap/ic_launcher',
          visibility: NotificationVisibility.private,
        ),
      ),
    );
  }
  
  // 显示提醒通知（带fullScreenIntent）
  Future<void> showReminderNotification(String reminderId, String content, String triggerTime) async {
    const androidDetails = AndroidNotificationDetails(
      reminderChannelId,
      '提醒通知',
      channelDescription: '到点提醒，锁屏时也能弹出',
      importance: Importance.max,
      priority: Priority.max,
      playSound: true,
      enableVibration: true,
      fullScreenIntent: true, // 关键：锁屏时全屏弹出
      category: AndroidNotificationCategory.alarm,
      visibility: NotificationVisibility.public,
      icon: '@mipmap/ic_launcher',
      sound: RawResourceAndroidNotificationSound('notification'),
      timeoutAfter: 60000, // 1分钟后自动消失
      styleInformation: BigTextStyleInformation(
        content,
        contentTitle: '⏰ 念念不忘提醒',
        summaryText: '点击查看详情',
      ),
    );
    
    const details = NotificationDetails(android: androidDetails);
    
    // 使用reminderId的hashCode作为通知ID，确保同一提醒不会重复弹通知
    final notificationId = reminderId.hashCode.abs() % 2147483647;
    
    await notifications.show(
      notificationId,
      '⏰ 念念不忘提醒',
      content,
      details,
      payload: jsonEncode({
        'reminder_id': reminderId,
        'trigger_time': triggerTime,
        'source': 'background_service',
      }),
    );
    
    print('[Background] 提醒通知已发送: $content');
  }
  
  // 检查提醒是否到期
  Future<List<Map<String, dynamic>>> _checkReminders() async {
    final prefs = await SharedPreferences.getInstance();
    final now = DateTime.now();
    final toTrigger = <Map<String, dynamic>>[];
    
    // 获取所有reminders开头的key
    final keys = prefs.getKeys().where((k) => k.startsWith(_remindersKey)).toList();
    
    for (final key in keys) {
      final jsonStr = prefs.getString(key);
      if (jsonStr == null) continue;
      
      try {
        final jsonList = jsonDecode(jsonStr) as List;
        for (final j in jsonList) {
          final reminderId = j['reminder_id']?.toString() ?? '';
          final status = j['status']?.toString() ?? '';
          
          // 只处理pending状态的提醒
          if (status != 'pending' && status != 'snoozed') continue;
          
          // 避免重复触发
          if (_triggeredReminderIds.contains(reminderId)) continue;
          
          final triggerTimeStr = j['trigger_time']?.toString();
          if (triggerTimeStr == null) continue;
          
          try {
            final triggerTime = DateTime.parse(triggerTimeStr);
            // 到期或超时5分钟内
            if (!now.isBefore(triggerTime) && now.difference(triggerTime).inMinutes <= 5) {
              toTrigger.add({
                'reminder_id': reminderId,
                'content': j['content']?.toString() ?? '提醒',
                'trigger_time': triggerTimeStr,
              });
              _triggeredReminderIds.add(reminderId);
            }
          } catch (e) {
            // 忽略解析错误
          }
        }
      } catch (e) {
        // 忽略JSON解析错误
      }
    }
    
    return toTrigger;
  }
  
  // 更新提醒状态为triggered
  Future<void> _markReminderTriggered(String reminderId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final keys = prefs.getKeys().where((k) => k.startsWith(_remindersKey)).toList();
      
      for (final key in keys) {
        final jsonStr = prefs.getString(key);
        if (jsonStr == null) continue;
        
        try {
          final jsonList = jsonDecode(jsonStr) as List;
          bool updated = false;
          final newList = jsonList.map((j) {
            if (j['reminder_id'] == reminderId) {
              j['status'] = 'triggered';
              updated = true;
            }
            return j;
          }).toList();
          
          if (updated) {
            await prefs.setString(key, jsonEncode(newList));
            print('[Background] 提醒状态已更新: $reminderId -> triggered');
            break;
          }
        } catch (e) {
          // continue
        }
      }
    } catch (e) {
      print('[Background] 更新提醒状态失败: $e');
    }
  }
  
  // 主服务逻辑
  onStart(service) async {
    print('[Background] 服务启动');
    
    // 初始化通知
    configureNotifications();
    
    // 每15秒检查一次提醒
    final timer = Timer.periodic(const Duration(seconds: 15), (timer) async {
      try {
        final reminders = await _checkReminders();
        
        if (reminders.isNotEmpty) {
          print('[Background] 检测到${reminders.length}条到期提醒');
        }
        
        for (final r in reminders) {
          final reminderId = r['reminder_id'] as String;
          final content = r['content'] as String;
          final triggerTime = r['trigger_time'] as String;
          
          // 显示全屏通知
          await showReminderNotification(reminderId, content, triggerTime);
          
          // 更新状态
          await _markReminderTriggered(reminderId);
        }
        
        // 清理超过2小时的触发记录
        _triggeredReminderIds.removeWhere((id) {
          // 这里简单处理，每小时清理一次
          return DateTime.now().minute == 0 && _triggeredReminderIds.length > 100;
        });
        
      } catch (e) {
        print('[Background] 检查提醒出错: $e');
      }
    });
    
    // 监听停止事件
    service.on('stop').listen((event) {
      print('[Background] 收到停止指令');
      timer.cancel();
      service.stopSelf();
    });
    
    // 监听更新事件（主APP通知有新提醒）
    service.on('update').listen((event) {
      print('[Background] 收到更新事件');
    });
  }
  
  // 注册服务
  service.configure(
    iosConfiguration: IosConfiguration(),
    androidConfiguration: AndroidConfiguration(
      onStart: onStart,
      isForegroundMode: true,
      autoStartOnBoot: true,
      autoStart: true,
      initialNotificationTitle: '念念不忘',
      initialNotificationContent: '守护服务启动中',
      notificationChannelId: notificationChannelId,
    ),
    android: AndroidConfiguration(
      onStart: onStart,
      isForegroundMode: true,
      autoStartOnBoot: true,
      autoStart: true,
      initialNotificationTitle: '念念不忘',
      initialNotificationContent: '守护服务启动中',
      notificationChannelId: notificationChannelId,
    ),
  );
  
  // 启动服务
  service.startService();
  print('[Background] 前台服务已启动');
}

/// 前台服务管理类
class BackgroundReminderService {
  static final BackgroundReminderService _instance = BackgroundReminderService._();
  factory BackgroundReminderService() => _instance;
  BackgroundReminderService._();
  
  final FlutterBackgroundService _service = FlutterBackgroundService();
  
  bool _isRunning = false;
  bool get isRunning => _isRunning;
  
  /// 初始化服务
  Future<void> initialize() async {
    print('[Service] BackgroundReminderService 初始化');
    // 服务配置在入口函数中完成，这里只是标记
  }
  
  /// 启动前台服务
  Future<bool> startService() async {
    try {
      final isRunning = await _service.isRunning();
      
      if (!isRunning) {
        // 触发入口函数运行
        runBackgroundService();
        await Future.delayed(const Duration(seconds: 1));
        
        final nowRunning = await _service.isRunning();
        _isRunning = nowRunning;
        
        print('[Service] 前台服务启动${nowRunning ? '成功' : '失败'}');
        return nowRunning;
      } else {
        _isRunning = true;
        print('[Service] 前台服务已在运行');
        return true;
      }
    } catch (e) {
      print('[Service] 启动前台服务出错: $e');
      return false;
    }
  }
  
  /// 停止前台服务
  Future<void> stopService() async {
    try {
      _service.invoke('stop');
      _isRunning = false;
      print('[Service] 前台服务停止指令已发送');
    } catch (e) {
      print('[Service] 停止前台服务出错: $e');
    }
  }
  
  /// 通知后台有新提醒（可选）
  void notifyUpdate() {
    _service.invoke('update');
  }
  
  /// 检查服务运行状态
  Future<bool> checkRunning() async {
    try {
      _isRunning = await _service.isRunning();
      return _isRunning;
    } catch (e) {
      print('[Service] 检查运行状态出错: $e');
      return false;
    }
  }
}
