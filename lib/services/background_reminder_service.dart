import 'dart:async';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

/// 原生前台服务管理 v1.0.45
/// 
/// 核心改动：彻底抛弃flutter_background_service包
/// 改用原生Kotlin Foreground Service（ReminderForegroundService.kt）
/// 通过MethodChannel与原生服务通信
/// 
/// 架构：
/// - Flutter侧：通过MethodChannel启动/停止原生前台服务
/// - Kotlin侧：ReminderForegroundService读取SharedPreferences轮询提醒
/// - Kotlin侧：到点时直接通过NotificationManager发全屏通知+闹钟铃声
/// - 不再需要Flutter侧在后台isolate中轮询

class BackgroundReminderService {
  static final BackgroundReminderService _instance = BackgroundReminderService._();
  factory BackgroundReminderService() => _instance;
  BackgroundReminderService._() {
    // v1.0.62: 注册 MethodCallHandler 接收 Kotlin→Flutter 的反向调用
    _channel.setMethodCallHandler(_handleMethodCall);
  }

  static const MethodChannel _channel = MethodChannel('com.niannianbuwang.app/reminder_service');

  bool _isRunning = false;
  bool get isRunning => _isRunning;

  /// v1.0.62: AlarmActivity "知道了"按钮触发时的回调
  /// 业务逻辑在 main.dart 注入（执行 status→confirmed + 同步后端 + UI刷新）
  static Future<void> Function(String reminderId)? onConfirmReminder;

  /// v1.0.62: 处理 Kotlin→Flutter 的 MethodChannel 调用
  static Future<dynamic> _handleMethodCall(MethodCall call) async {
    print('[Service] 收到Kotlin调用: ${call.method} ${call.arguments}');
    switch (call.method) {
      case 'confirmReminder':
        final reminderId = call.arguments as String?;
        if (reminderId != null && reminderId.isNotEmpty && onConfirmReminder != null) {
          try {
            await onConfirmReminder!(reminderId);
            print('[Service] confirmReminder 处理完成: $reminderId');
          } catch (e) {
            print('[Service] confirmReminder 处理异常: $e');
          }
        } else {
          print('[Service] confirmReminder 跳过: reminderId=$reminderId callback=${onConfirmReminder != null}');
        }
        return true;
      default:
        return null;
    }
  }

  /// 启动原生前台服务
  Future<bool> startService() async {
    try {
      final result = await _channel.invokeMethod<bool>('startService');
      _isRunning = result ?? false;
      print('[Service] 原生前台服务启动: $_isRunning');
      return _isRunning;
    } on PlatformException catch (e) {
      print('[Service] 启动原生前台服务失败: ${e.message}');
      _isRunning = false;
      return false;
    } catch (e) {
      print('[Service] 启动原生前台服务异常: $e');
      _isRunning = false;
      return false;
    }
  }

  /// 停止原生前台服务
  Future<void> stopService() async {
    try {
      await _channel.invokeMethod<bool>('stopService');
      _isRunning = false;
      print('[Service] 原生前台服务已停止');
    } on PlatformException catch (e) {
      print('[Service] 停止原生前台服务失败: ${e.message}');
    } catch (e) {
      print('[Service] 停止原生前台服务异常: $e');
    }
  }

  /// 检查服务是否运行中
  Future<bool> checkRunning() async {
    try {
      final result = await _channel.invokeMethod<bool>('isServiceRunning');
      _isRunning = result ?? false;
      return _isRunning;
    } on PlatformException catch (e) {
      print('[Service] 检查运行状态失败: ${e.message}');
      return false;
    } catch (e) {
      print('[Service] 检查运行状态异常: $e');
      return false;
    }
  }

  /// 通知服务有新提醒（预留接口，当前原生服务自动轮询SharedPreferences）
  void notifyUpdate() {
    // 原生服务每15秒自动轮询SharedPreferences，无需额外通知
    // 预留接口，后续可用于即时唤醒
  }
}
