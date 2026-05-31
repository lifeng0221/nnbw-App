import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import '../models/app_models.dart';

/// 后端同步API服务
/// 对接Coze后端: https://650ab256-c885-44ab-a576-9db1b508b36a.dev.coze.site
/// 
/// 核心同步逻辑：
/// - 登录时：创建/获取用户 → 拉取绑定 → 拉取提醒
/// - 创建提醒：先本地保存 → 再同步到后端
/// - 状态变更：确认/延后/删除 → 本地先改 → 再同步后端
/// - 进入APP：从后端拉取最新数据覆盖本地
class ApiService {
  // TODO: 后续替换为正式域名 jizhe.me
  static const String baseUrl = 'https://650ab256-c885-44ab-a576-9db1b508b36a.dev.coze.site';
  
  final http.Client _client = http.Client();
  
  // ==================== 基础请求 ====================
  
  Future<Map<String, dynamic>> get(String path, {Map<String, String>? queryParams}) async {
    try {
      final uri = Uri.parse('$baseUrl$path').replace(queryParameters: queryParams);
      final response = await _client.get(uri, headers: {'Content-Type': 'application/json'}).timeout(const Duration(seconds: 10));
      return _handleResponse(response);
    } catch (e) {
      return {'success': false, 'error': e.toString()};
    }
  }
  
  Future<Map<String, dynamic>> post(String path, Map<String, dynamic> data) async {
    try {
      final response = await _client.post(
        Uri.parse('$baseUrl$path'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(data),
      ).timeout(const Duration(seconds: 10));
      return _handleResponse(response);
    } catch (e) {
      return {'success': false, 'error': e.toString()};
    }
  }
  
  Future<Map<String, dynamic>> put(String path, {Map<String, dynamic>? data}) async {
    try {
      final request = http.Request('PUT', Uri.parse('$baseUrl$path'));
      request.headers['Content-Type'] = 'application/json';
      if (data != null) request.body = jsonEncode(data);
      final streamed = await _client.send(request).timeout(const Duration(seconds: 10));
      final response = await http.Response.fromStream(streamed);
      return _handleResponse(response);
    } catch (e) {
      return {'success': false, 'error': e.toString()};
    }
  }
  
  Future<Map<String, dynamic>> delete(String path) async {
    try {
      final request = http.Request('DELETE', Uri.parse('$baseUrl$path'));
      request.headers['Content-Type'] = 'application/json';
      final streamed = await _client.send(request).timeout(const Duration(seconds: 10));
      final response = await http.Response.fromStream(streamed);
      return _handleResponse(response);
    } catch (e) {
      return {'success': false, 'error': e.toString()};
    }
  }
  
  Map<String, dynamic> _handleResponse(http.Response response) {
    if (response.statusCode == 200) {
      try {
        return jsonDecode(response.body);
      } catch (e) {
        return {'success': true, 'raw': response.body};
      }
    } else {
      return {
        'success': false, 
        'error': 'HTTP ${response.statusCode}',
        'body': response.body,
      };
    }
  }
  
  // ==================== 用户相关 ====================
  
  /// 创建或注册用户（设备登录）
  /// 后端 POST /users
  Future<Map<String, dynamic>> createUser({
    required String userId,
    required String role,
    String? nickname,
    String? deviceId,
  }) async {
    return post('/users', {
      'user_id': userId,
      'role': role,
      'nickname': nickname ?? (role == 'parent' ? '老人' : '子女'),
      'device_id': deviceId,
    });
  }
  
  /// 获取用户信息
  /// 后端 GET /users/{user_id}
  Future<Map<String, dynamic>> getUser(String userId) async {
    return get('/users/$userId');
  }
  
  /// 设备登录（旧版兼容）
  /// 后端 POST /auth/device_login
  Future<Map<String, dynamic>> deviceLogin(String deviceId, String role) async {
    return post('/auth/device_login', {
      'device_id': deviceId,
      'role': role,
    });
  }
  
  // ==================== 绑定相关 ====================
  
  /// 创建绑定关系
  /// 后端 POST /bindings
  Future<Map<String, dynamic>> createBinding({
    required String parentId,
    required String childId,
  }) async {
    return post('/bindings', {
      'parent_id': parentId,
      'child_id': childId,
    });
  }
  
  /// 获取绑定列表
  /// 后端 GET /bindings?parent_id=xxx 或 ?child_id=xxx
  Future<Map<String, dynamic>> getBindings({String? parentId, String? childId}) async {
    final params = <String, String>{};
    if (parentId != null) params['parent_id'] = parentId;
    if (childId != null) params['child_id'] = childId;
    return get('/bindings', queryParams: params);
  }
  
  /// 确认/更新绑定状态
  /// 后端 PUT /bindings/{binding_id}/status
  Future<Map<String, dynamic>> updateBindingStatus(int bindingId, String status) async {
    return put('/bindings/$bindingId/status', data: {'status': status});
  }
  
  /// 生成配对码（旧版）
  /// 后端 POST /bind/create_code
  Future<Map<String, dynamic>> createPairCode(String parentId) async {
    return post('/bind/create_code', {'parent_id': parentId});
  }
  
  /// 确认配对码（旧版）
  /// 后端 POST /bind/confirm
  Future<Map<String, dynamic>> confirmPairCode(String pairCode, String childId) async {
    return post('/bind/confirm', {'code': pairCode, 'child_id': childId});
  }
  
  // ==================== 提醒相关 ====================
  
  /// 创建提醒
  /// 后端 POST /reminders
  Future<Map<String, dynamic>> createReminder({
    required int bindingId,
    required String createdBy,
    required String content,
    required String triggerTime,
    String category = '生活',
    String priority = 'normal',
    String repeatType = 'once',
    String? voiceUrl,
  }) async {
    return post('/reminders', {
      'binding_id': bindingId,
      'created_by': createdBy,
      'content': content,
      'trigger_time': triggerTime,
      'category': category,
      'priority': priority,
      'repeat_type': repeatType,
      'voice_url': voiceUrl,
    });
  }
  
  /// 获取提醒列表
  /// 后端 GET /reminders?binding_id=xxx
  Future<Map<String, dynamic>> getReminders(int bindingId) async {
    return get('/reminders', queryParams: {'binding_id': bindingId.toString()});
  }
  
  /// 更新提醒状态
  /// 后端 PUT /reminders/{reminder_id}/status
  Future<Map<String, dynamic>> updateReminderStatus(int reminderId, String status) async {
    return put('/reminders/$reminderId/status', data: {'status': status});
  }
  
  /// 延后提醒（snooze）
  /// 后端 PUT /reminders/{reminder_id}/snooze
  Future<Map<String, dynamic>> snoozeReminder(int reminderId, {int minutes = 5}) async {
    return put('/reminders/$reminderId/snooze', data: {'minutes': minutes});
  }
  
  /// 删除提醒
  /// 后端 DELETE /reminders/{reminder_id}
  Future<Map<String, dynamic>> deleteReminder(int reminderId) async {
    return delete('/reminders/$reminderId');
  }
  
  // ==================== 旧版兼容API ====================
  
  /// 旧版：检查用户提醒
  Future<Map<String, dynamic>> checkReminders(String userId) async {
    return get('/reminder/check/$userId');
  }
  
  /// 旧版：即将到来的提醒
  Future<Map<String, dynamic>> getUpcomingReminders(String userId) async {
    return get('/reminder/upcoming/$userId');
  }
  
  /// 旧版：自然语言创建提醒
  Future<Map<String, dynamic>> naturalCreateReminder({
    required String bindingId,
    required String createdBy,
    required String text,
    String category = '生活',
    String priority = 'normal',
  }) async {
    return post('/reminder/parse', {
      'binding_id': bindingId,
      'created_by': createdBy,
      'text': text,
      'category': category,
      'priority': priority,
    });
  }
  
  // ==================== 高层同步逻辑 ====================
  
  /// 登录后同步：注册/获取用户 + 拉取绑定 + 拉取提醒
  /// 返回同步结果，包含用户信息、绑定列表、所有提醒
  Future<SyncResult> fullSync(String userId, String role, {String? nickname}) async {
    final result = SyncResult();
    
    // 1. 注册/获取用户
    final userResp = await createUser(userId: userId, role: role, nickname: nickname);
    if (userResp['success'] == true) {
      result.userInfo = userResp['data'];
    } else {
      // 可能已存在，尝试获取
      final getResp = await getUser(userId);
      if (getResp['success'] == true) {
        result.userInfo = getResp['data'];
      }
    }
    
    // 2. 拉取绑定
    List<BindingModel> bindings = [];
    if (role == 'parent') {
      final bindResp = await getBindings(parentId: userId);
      if (bindResp['success'] == true && bindResp['data'] is List) {
        bindings = (bindResp['data'] as List).map((j) => _parseBinding(j)).toList();
      }
    } else {
      final bindResp = await getBindings(childId: userId);
      if (bindResp['success'] == true && bindResp['data'] is List) {
        bindings = (bindResp['data'] as List).map((j) => _parseBinding(j)).toList();
      }
    }
    result.bindings = bindings;
    
    // 3. 拉取所有绑定下的提醒
    List<ReminderModel> allReminders = [];
    for (final binding in bindings) {
      final reminderResp = await getReminders(binding.bindingId);
      if (reminderResp['success'] == true && reminderResp['data'] is List) {
        allReminders.addAll(
          (reminderResp['data'] as List).map((j) => _parseReminder(j)).toList()
        );
      }
    }
    result.reminders = allReminders;
    
    return result;
  }
  
  /// 解析绑定数据
  BindingModel _parseBinding(Map<String, dynamic> json) {
    return BindingModel(
      bindingId: (json['binding_id'] ?? '').toString(),
      parentId: json['parent_id'] ?? '',
      childId: json['child_id'] ?? '',
      status: json['status'] ?? 'pending',
      createdAt: json['created_at'] != null 
          ? DateTime.parse(json['created_at']) 
          : DateTime.now(),
    );
  }
  
  /// 解析提醒数据
  ReminderModel _parseReminder(Map<String, dynamic> json) {
    return ReminderModel(
      reminderId: (json['reminder_id'] ?? '').toString(),
      bindingId: (json['binding_id'] ?? '').toString(),
      createdBy: json['created_by'] ?? '',
      content: json['content'] ?? '',
      voiceUrl: json['voice_url'],
      triggerTime: json['trigger_time'] != null 
          ? DateTime.parse(json['trigger_time']) 
          : DateTime.now(),
      repeatType: json['repeat_type'] ?? 'once',
      category: json['category'] ?? '生活',
      priority: json['priority'] ?? 'normal',
      status: json['status'] ?? 'pending',
      snoozeCount: json['snooze_count'] ?? 0,
      createdAt: json['created_at'] != null 
          ? DateTime.parse(json['created_at']) 
          : DateTime.now(),
    );
  }
}

/// 同步结果
class SyncResult {
  Map<String, dynamic>? userInfo;
  List<BindingModel> bindings = [];
  List<ReminderModel> reminders = [];
  
  bool get hasData => userInfo != null || bindings.isNotEmpty || reminders.isNotEmpty;
}
