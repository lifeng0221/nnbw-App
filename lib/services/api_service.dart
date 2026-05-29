import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;

/// 后端API服务
/// 对接Coze后端: https://650ab256-c885-44ab-a576-9db1b508b36a.dev.coze.site
class ApiService {
  // TODO: 后续替换为正式域名
  static const String baseUrl = 'https://650ab256-c885-44ab-a576-9db1b508b36a.dev.coze.site';
  
  final http.Client _client = http.Client();
  
  /// GET请求
  Future<Map<String, dynamic>> get(String path, {Map<String, String>? headers}) async {
    try {
      final response = await _client.get(
        Uri.parse('$baseUrl$path'),
        headers: {'Content-Type': 'application/json', ...?headers},
      ).timeout(const Duration(seconds: 10));
      
      return _handleResponse(response);
    } catch (e) {
      return {'success': false, 'error': e.toString()};
    }
  }
  
  /// POST请求
  Future<Map<String, dynamic>> post(String path, Map<String, dynamic> data, {Map<String, String>? headers}) async {
    try {
      final response = await _client.post(
        Uri.parse('$baseUrl$path'),
        headers: {'Content-Type': 'application/json', ...?headers},
        body: jsonEncode(data),
      ).timeout(const Duration(seconds: 10));
      
      return _handleResponse(response);
    } catch (e) {
      return {'success': false, 'error': e.toString()};
    }
  }
  
  /// 上传录音文件
  Future<Map<String, dynamic>> uploadVoice(String path, File audioFile, {Map<String, String>? headers}) async {
    try {
      final request = http.MultipartRequest('POST', Uri.parse('$baseUrl$path'));
      request.headers.addAll({...?headers});
      request.files.add(await http.MultipartFile.fromPath('voice', audioFile.path));
      
      final streamedResponse = await request.send().timeout(const Duration(seconds: 30));
      final response = await http.Response.fromStream(streamedResponse);
      
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
  
  // ============ 用户相关 ============
  
  /// 微信登录
  Future<Map<String, dynamic>> wechatLogin(String code, String role) async {
    return post('/api/auth/wechat', {
      'code': code,
      'role': role,
    });
  }
  
  /// 获取用户信息
  Future<Map<String, dynamic>> getUserInfo(String userId) async {
    return get('/api/users/$userId');
  }
  
  // ============ 绑定相关 ============
  
  /// 生成配对码（子女端）
  Future<Map<String, dynamic>> generatePairCode(String childId) async {
    return post('/api/bind/generate', {'child_id': childId});
  }
  
  /// 确认绑定（老人端）
  Future<Map<String, dynamic>> confirmBind(String parentId, String pairCode) async {
    return post('/api/bind/confirm', {
      'parent_id': parentId,
      'pair_code': pairCode,
    });
  }
  
  /// 获取绑定列表
  Future<Map<String, dynamic>> getBindings(String userId) async {
    return get('/api/bindings/$userId');
  }
  
  // ============ 提醒相关 ============
  
  /// 创建提醒
  Future<Map<String, dynamic>> createReminder({
    required String bindingId,
    required String createdBy,
    required String content,
    String? voiceUrl,
    required String triggerTime,
    String repeatType = 'once',
    String category = '生活',
    String priority = 'normal',
  }) async {
    return post('/api/reminders', {
      'binding_id': bindingId,
      'created_by': createdBy,
      'content': content,
      'voice_url': voiceUrl,
      'trigger_time': triggerTime,
      'repeat_type': repeatType,
      'category': category,
      'priority': priority,
    });
  }
  
  /// 获取提醒列表
  Future<Map<String, dynamic>> getReminders(String userId, {String? date}) async {
    final path = date != null 
        ? '/api/reminders/$userId?date=$date' 
        : '/api/reminders/$userId';
    return get(path);
  }
  
  /// 确认提醒
  Future<Map<String, dynamic>> confirmReminder(String reminderId, String userId) async {
    return post('/api/reminders/$reminderId/confirm', {'user_id': userId});
  }
  
  /// Snooze提醒
  Future<Map<String, dynamic>> snoozeReminder(String reminderId, String userId) async {
    return post('/api/reminders/$reminderId/snooze', {'user_id': userId});
  }
  
  /// 删除提醒
  Future<Map<String, dynamic>> deleteReminder(String reminderId) async {
    return post('/api/reminders/$reminderId/delete', {});
  }
  
  /// 自然语言创建提醒
  Future<Map<String, dynamic>> naturalCreateReminder({
    required String bindingId,
    required String createdBy,
    required String text,
    String? voiceUrl,
    String category = '生活',
    String priority = 'normal',
  }) async {
    return post('/api/reminders/natural', {
      'binding_id': bindingId,
      'created_by': createdBy,
      'text': text,
      'voice_url': voiceUrl,
      'category': category,
      'priority': priority,
    });
  }
  
  // ============ 语音ASR ============
  
  /// 语音转文字（通过后端调用讯飞ASR）
  Future<Map<String, dynamic>> transcribeVoice(File audioFile) async {
    return uploadVoice('/api/voice/transcribe', audioFile);
  }
}
