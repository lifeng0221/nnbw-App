import 'dart:async';
import 'dart:convert';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 后台前台服务 v1.0.40
/// 实现APP在后台或息屏时仍能触发提醒
/// 
/// 架构说明：
/// - configure() 在主isolate中调用（由BackgroundReminderService.initialize()触发）
/// - onStart() 是入口函数，在后台isolate中运行
/// - 后台isolate通过SharedPreferences与主APP共享提醒数据

// SharedPreferences key常量（与主APP保持一致）
const String _remindersKey = 'reminders';
const String _serverBindingIdKey = 'server_binding_id';

// 后台isolate中的已触发提醒ID集合
final Set<String> _triggeredReminderIds = {};

/// 后台服务入口函数（必须在顶层，带@pragma）
/// 这个函数运行在独立的isolate中
@pragma('vm:entry-point')
void onStart(ServiceInstance service) async {
  print('[Background] 后台服务启动');

  // 初始化通知插件（后台isolate中需要独立初始化）
  final notifications = FlutterLocalNotificationsPlugin();
  
  const androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');
  const iosSettings = DarwinInitializationSettings();
  const settings = InitializationSettings(android: androidSettings, iOS: iosSettings);
  
  await notifications.initialize(
    settings,
    onDidReceiveNotificationResponse: (response) {
      print('[Background] 通知被点击: ${response.payload}');
    },
  );

  // 创建提醒通知渠道（高优先级，支持fullScreenIntent）
  const reminderChannel = AndroidNotificationChannel(
    'nnbw_reminder_alarm',
    '提醒闹钟',
    description: '到点提醒，锁屏时也会响铃弹出',
    importance: Importance.max,
    playSound: true,
    enableVibration: true,
  );

  final androidPlugin = notifications.resolvePlatformSpecificImplementation<
      AndroidFlutterLocalNotificationsPlugin>();

  await androidPlugin?.createNotificationChannel(reminderChannel);

  print('[Background] 通知初始化完成');

  // 每15秒检查一次提醒
  Timer.periodic(const Duration(seconds: 15), (timer) async {
    try {
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
              // 到期且不超过30分钟（避免重启后大量历史提醒同时触发）
              final diff = now.difference(triggerTime);
              if (!now.isBefore(triggerTime) && diff.inMinutes <= 30) {
                toTrigger.add({
                  'reminder_id': reminderId,
                  'content': j['content']?.toString() ?? '提醒',
                  'trigger_time': triggerTimeStr,
                  'key': key,
                });
                _triggeredReminderIds.add(reminderId);
              }
            } catch (e) {
              // 忽略时间解析错误
            }
          }
        } catch (e) {
          // 忽略JSON解析错误
        }
      }

      if (toTrigger.isNotEmpty) {
        print('[Background] 检测到${toTrigger.length}条到期提醒');
      }

      // 触发提醒
      for (final r in toTrigger) {
        final reminderId = r['reminder_id'] as String;
        final content = r['content'] as String;
        final triggerTime = r['trigger_time'] as String;

        // 1. 显示全屏通知（带响铃）
        try {
          final androidDetails = AndroidNotificationDetails(
            'nnbw_reminder_alarm',
            '提醒闹钟',
            channelDescription: '到点提醒，锁屏时也会响铃弹出',
            importance: Importance.max,
            priority: Priority.max,
            playSound: true,
            enableVibration: true,
            fullScreenIntent: true,
            category: AndroidNotificationCategory.alarm,
            visibility: NotificationVisibility.public,
            icon: '@mipmap/ic_launcher',
            timeoutAfter: 120000, // 2分钟后自动消失
          );

          final details = NotificationDetails(android: androidDetails);

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
        } catch (e) {
          print('[Background] 通知发送失败: $e');
        }

        // 2. 更新SharedPreferences中的状态为triggered
        try {
          final prefs2 = await SharedPreferences.getInstance();
          final key = r['key'] as String;
          final jsonStr = prefs2.getString(key);
          if (jsonStr != null) {
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
              await prefs2.setString(key, jsonEncode(newList));
              print('[Background] 状态已更新: $reminderId -> triggered');
            }
          }
        } catch (e) {
          print('[Background] 更新状态失败: $e');
        }
      }

      // 清理超过2小时的触发记录
      if (_triggeredReminderIds.length > 200) {
        _triggeredReminderIds.clear();
        print('[Background] 清理触发记录');
      }

    } catch (e) {
      print('[Background] 检查提醒出错: $e');
    }
  });

  // 监听停止事件
  service.on('stop').listen((event) {
    print('[Background] 收到停止指令');
    service.stopSelf();
  });

  // 监听更新事件
  service.on('update').listen((event) {
    print('[Background] 收到更新事件');
  });
}

/// 前台服务管理类
class BackgroundReminderService {
  static final BackgroundReminderService _instance = BackgroundReminderService._();
  factory BackgroundReminderService() => _instance;
  BackgroundReminderService._();

  final FlutterBackgroundService _service = FlutterBackgroundService();

  bool _isRunning = false;
  bool get isRunning => _isRunning;
  bool _configured = false;

  /// 初始化并配置服务（在主isolate中调用，幂等——多次调用安全）
  Future<void> initialize() async {
    if (_configured) {
      print('[Service] 已配置，跳过');
      return;
    }
    print('[Service] BackgroundReminderService 配置');

    try {
      await _service.configure(
      androidConfiguration: AndroidConfiguration(
        onStart: onStart,
        isForegroundMode: true,
        autoStartOnBoot: true,
        autoStart: true,
        initialNotificationTitle: '念念不忘',
        initialNotificationContent: '守护服务运行中，确保提醒准时触发',
        notificationChannelId: 'nnbw_background_service',
      ),
      iosConfiguration: IosConfiguration(
        autoStart: true,
        onForeground: onStart,
        onBackground: onIosBackground,
      ),
    );

    _configured = true;
    print('[Service] 服务配置完成');
    } catch (e) {
      print('[Service] 服务配置异常: $e');
      // 不抛出，让主流程继续
    }
  }

  /// iOS后台处理
  @pragma('vm:entry-point')
  static Future<bool> onIosBackground(ServiceInstance service) async {
    return true;
  }

  /// 启动前台服务
  Future<bool> startService() async {
    try {
      final running = await _service.isRunning();

      if (!running) {
        await _service.startService();
        await Future.delayed(const Duration(seconds: 1));

        _isRunning = await _service.isRunning();
        print('[Service] 前台服务启动${_isRunning ? '成功' : '失败'}');
        return _isRunning;
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

  /// 通知后台有新提醒
  void notifyUpdate() {
    try {
      _service.invoke('update');
    } catch (e) {
      // ignore
    }
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
