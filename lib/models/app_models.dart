/// 数据模型定义

class UserModel {
  final String userId;
  final String? wechatOpenid;
  final String role; // 'parent' or 'child'
  final String? nickname;
  final String? phone;
  final DateTime createdAt;
  
  UserModel({
    required this.userId,
    this.wechatOpenid,
    required this.role,
    this.nickname,
    this.phone,
    required this.createdAt,
  });
  
  factory UserModel.fromJson(Map<String, dynamic> json) {
    return UserModel(
      userId: json['user_id'] ?? '',
      wechatOpenid: json['wechat_openid'],
      role: json['role'] ?? 'parent',
      nickname: json['nickname'],
      phone: json['phone'],
      createdAt: DateTime.parse(json['created_at'] ?? DateTime.now().toIso8601String()),
    );
  }
}

class BindingModel {
  final String bindingId;
  final String parentId;
  final String childId;
  final String status; // 'active', 'inactive'
  final DateTime createdAt;
  
  BindingModel({
    required this.bindingId,
    required this.parentId,
    required this.childId,
    required this.status,
    required this.createdAt,
  });
  
  factory BindingModel.fromJson(Map<String, dynamic> json) {
    return BindingModel(
      bindingId: json['binding_id'] ?? '',
      parentId: json['parent_id'] ?? '',
      childId: json['child_id'] ?? '',
      status: json['status'] ?? 'inactive',
      createdAt: DateTime.parse(json['created_at'] ?? DateTime.now().toIso8601String()),
    );
  }
}

class ReminderModel {
  final String reminderId;
  final String bindingId;
  final String createdBy; // user_id
  final String content;
  final String? voiceUrl;
  final DateTime triggerTime;
  final String repeatType; // 'once', 'daily', 'weekly', 'custom'
  final Map<String, dynamic>? repeatConfig;
  final String category; // '吃药', '运动', '生活', '医疗', '其他'
  final String priority; // 'normal', 'important', 'urgent'
  final String status; // 'pending', 'triggered', 'confirmed', 'snoozed', 'skipped', 'expired'
  final DateTime? confirmedAt;
  final int snoozeCount;
  final int snoozeMax;
  final DateTime createdAt;
  
  ReminderModel({
    required this.reminderId,
    required this.bindingId,
    required this.createdBy,
    required this.content,
    this.voiceUrl,
    required this.triggerTime,
    this.repeatType = 'once',
    this.repeatConfig,
    this.category = '生活',
    this.priority = 'normal',
    this.status = 'pending',
    this.confirmedAt,
    this.snoozeCount = 0,
    this.snoozeMax = 2,
    required this.createdAt,
  });
  
  factory ReminderModel.fromJson(Map<String, dynamic> json) {
    return ReminderModel(
      reminderId: json['reminder_id'] ?? '',
      bindingId: json['binding_id'] ?? '',
      createdBy: json['created_by'] ?? '',
      content: json['content'] ?? '',
      voiceUrl: json['voice_url'],
      triggerTime: DateTime.parse(json['trigger_time'] ?? DateTime.now().toIso8601String()),
      repeatType: json['repeat_type'] ?? 'once',
      repeatConfig: json['repeat_config'],
      category: json['category'] ?? '生活',
      priority: json['priority'] ?? 'normal',
      status: json['status'] ?? 'pending',
      confirmedAt: json['confirmed_at'] != null 
          ? DateTime.parse(json['confirmed_at']) 
          : null,
      snoozeCount: json['snooze_count'] ?? 0,
      snoozeMax: json['snooze_max'] ?? 2,
      createdAt: DateTime.parse(json['created_at'] ?? DateTime.now().toIso8601String()),
    );
  }
  
  Map<String, dynamic> toJson() {
    return {
      'reminder_id': reminderId,
      'binding_id': bindingId,
      'created_by': createdBy,
      'content': content,
      'voice_url': voiceUrl,
      'trigger_time': triggerTime.toIso8601String(),
      'repeat_type': repeatType,
      'repeat_config': repeatConfig,
      'category': category,
      'priority': priority,
      'status': status,
      'confirmed_at': confirmedAt?.toIso8601String(),
      'snooze_count': snoozeCount,
      'snooze_max': snoozeMax,
      'created_at': createdAt.toIso8601String(),
    };
  }
  
  /// 是否可以再次snooze
  bool get canSnooze => snoozeCount < snoozeMax;
  
  /// 是否为紧急提醒
  bool get isUrgent => priority == 'urgent';
  
  /// 是否为重要提醒
  bool get isImportant => priority == 'important' || priority == 'urgent';
  
  /// 格式化触发时间
  String get formattedTime {
    final hour = triggerTime.hour.toString().padLeft(2, '0');
    final minute = triggerTime.minute.toString().padLeft(2, '0');
    return '$hour:$minute';
  }
  
  /// 优先级显示名
  String get priorityLabel {
    switch (priority) {
      case 'urgent': return '紧急';
      case 'important': return '重要';
      default: return '普通';
    }
  }
  
  /// 状态显示名
  String get statusLabel {
    switch (status) {
      case 'pending': return '待响';
      case 'triggered': return '已响铃';
      case 'confirmed': return '已完成';
      case 'snoozed': return '稍后提醒';
      case 'skipped': return '已跳过';
      case 'expired': return '已过期';
      default: return status;
    }
  }
}

/// 通知记录
class NotificationModel {
  final String notificationId;
  final String reminderId;
  final String targetUserId;
  final String type; // 'in_app', 'fcm', 'sms'
  final String status; // 'sent', 'delivered', 'failed'
  final DateTime sentAt;
  
  NotificationModel({
    required this.notificationId,
    required this.reminderId,
    required this.targetUserId,
    required this.type,
    required this.status,
    required this.sentAt,
  });
  
  factory NotificationModel.fromJson(Map<String, dynamic> json) {
    return NotificationModel(
      notificationId: json['notification_id'] ?? '',
      reminderId: json['reminder_id'] ?? '',
      targetUserId: json['target_user_id'] ?? '',
      type: json['type'] ?? 'in_app',
      status: json['status'] ?? 'sent',
      sentAt: DateTime.parse(json['sent_at'] ?? DateTime.now().toIso8601String()),
    );
  }
}
