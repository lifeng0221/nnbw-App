import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/app_models.dart';

/// 本地数据存储服务
/// 使用SharedPreferences存储提醒和绑定数据
class LocalStorageService {
  static const String _remindersKey = 'reminders';
  static const String _bindingsKey = 'bindings';
  static const String _pairCodesKey = 'pair_codes';
  
  SharedPreferences? _prefs;
  
  Future<SharedPreferences> get _preferences async {
    _prefs ??= await SharedPreferences.getInstance();
    return _prefs!;
  }
  
  // ==================== 提醒相关 ====================
  
  /// 保存提醒到本地
  Future<bool> saveReminder(ReminderModel reminder) async {
    final prefs = await _preferences;
    final reminders = await getReminders(reminder.bindingId);
    
    // 检查是否已存在，存在则更新
    final existingIndex = reminders.indexWhere((r) => r.reminderId == reminder.reminderId);
    if (existingIndex >= 0) {
      reminders[existingIndex] = reminder;
    } else {
      reminders.add(reminder);
    }
    
    final jsonList = reminders.map((r) => r.toJson()).toList();
    return prefs.setString('${_remindersKey}_${reminder.bindingId}', jsonEncode(jsonList));
  }
  
  /// 获取指定绑定ID的所有提醒
  Future<List<ReminderModel>> getReminders(String bindingId) async {
    final prefs = await _preferences;
    final jsonStr = prefs.getString('${_remindersKey}_$bindingId');
    if (jsonStr == null) return [];
    
    try {
      final jsonList = jsonDecode(jsonStr) as List;
      return jsonList.map((j) => ReminderModel.fromJson(j)).toList();
    } catch (e) {
      return [];
    }
  }
  
  /// 获取用户所有提醒（遍历所有binding）
  Future<List<ReminderModel>> getAllRemindersForUser(String userId) async {
    final prefs = await _preferences;
    final bindings = await getBindings(userId);
    
    List<ReminderModel> allReminders = [];
    for (final binding in bindings) {
      final bindingId = binding.bindingId;
      final jsonStr = prefs.getString('${_remindersKey}_$bindingId');
      if (jsonStr != null) {
        try {
          final jsonList = jsonDecode(jsonStr) as List;
          final reminders = jsonList.map((j) => ReminderModel.fromJson(j)).toList();
          // 过滤出当前用户相关的提醒
          allReminders.addAll(reminders.where((r) => 
            r.createdBy == userId || binding.parentId == userId || binding.childId == userId
          ));
        } catch (e) {
          // ignore
        }
      }
    }
    
    return allReminders;
  }
  
  /// 更新提醒状态
  Future<bool> updateReminderStatus(String reminderId, String newStatus, {DateTime? confirmedAt}) async {
    final prefs = await _preferences;
    final keys = prefs.getKeys().where((k) => k.startsWith(_remindersKey));
    
    for (final key in keys) {
      final jsonStr = prefs.getString(key);
      if (jsonStr != null) {
        try {
          final jsonList = jsonDecode(jsonStr) as List;
          bool updated = false;
          final newList = jsonList.map((j) {
            if (j['reminder_id'] == reminderId) {
              updated = true;
              j['status'] = newStatus;
              if (confirmedAt != null) {
                j['confirmed_at'] = confirmedAt.toIso8601String();
              }
            }
            return j;
          }).toList();
          
          if (updated) {
            await prefs.setString(key, jsonEncode(newList));
            return true;
          }
        } catch (e) {
          // continue
        }
      }
    }
    return false;
  }
  
  /// 确认提醒
  Future<bool> confirmReminder(String reminderId) async {
    return updateReminderStatus(reminderId, 'confirmed', confirmedAt: DateTime.now());
  }
  
  /// Snooze提醒（延后5分钟）
  Future<bool> snoozeReminder(String reminderId) async {
    final prefs = await _preferences;
    final keys = prefs.getKeys().where((k) => k.startsWith(_remindersKey));
    
    for (final key in keys) {
      final jsonStr = prefs.getString(key);
      if (jsonStr != null) {
        try {
          final jsonList = jsonDecode(jsonStr) as List;
          bool updated = false;
          final newList = jsonList.map((j) {
            if (j['reminder_id'] == reminderId) {
              updated = true;
              j['status'] = 'snoozed';
              j['snooze_count'] = (j['snooze_count'] ?? 0) + 1;
              // 延后5分钟
              final triggerTime = DateTime.parse(j['trigger_time']);
              j['trigger_time'] = triggerTime.add(const Duration(minutes: 5)).toIso8601String();
            }
            return j;
          }).toList();
          
          if (updated) {
            await prefs.setString(key, jsonEncode(newList));
            return true;
          }
        } catch (e) {
          // continue
        }
      }
    }
    return false;
  }
  
  /// 删除提醒
  Future<bool> deleteReminder(String reminderId) async {
    final prefs = await _preferences;
    final keys = prefs.getKeys().where((k) => k.startsWith(_remindersKey));
    
    for (final key in keys) {
      final jsonStr = prefs.getString(key);
      if (jsonStr != null) {
        try {
          final jsonList = jsonDecode(jsonStr) as List;
          final originalLength = jsonList.length;
          jsonList.removeWhere((j) => j['reminder_id'] == reminderId);
          
          if (jsonList.length < originalLength) {
            await prefs.setString(key, jsonEncode(jsonList));
            return true;
          }
        } catch (e) {
          // continue
        }
      }
    }
    return false;
  }
  
  /// 根据ID获取单个提醒
  Future<ReminderModel?> getReminderById(String reminderId) async {
    final prefs = await _preferences;
    final keys = prefs.getKeys().where((k) => k.startsWith(_remindersKey));
    
    for (final key in keys) {
      final jsonStr = prefs.getString(key);
      if (jsonStr != null) {
        try {
          final jsonList = jsonDecode(jsonStr) as List;
          for (final j in jsonList) {
            if (j['reminder_id'] == reminderId) {
              return ReminderModel.fromJson(j);
            }
          }
        } catch (e) {
          // continue
        }
      }
    }
    return null;
  }
  
  // ==================== 绑定相关 ====================
  
  /// 保存绑定关系
  Future<bool> saveBinding(BindingModel binding) async {
    final prefs = await _preferences;
    final bindings = await getBindings(binding.parentId);
    
    // 检查是否已存在
    final existingIndex = bindings.indexWhere((b) => b.bindingId == binding.bindingId);
    if (existingIndex >= 0) {
      bindings[existingIndex] = binding;
    } else {
      bindings.add(binding);
    }
    
    final jsonList = bindings.map((b) {
      return {
        'binding_id': b.bindingId,
        'parent_id': b.parentId,
        'child_id': b.childId,
        'status': b.status,
        'created_at': b.createdAt.toIso8601String(),
      };
    }).toList();
    
    return prefs.setString('${_bindingsKey}_${binding.parentId}', jsonEncode(jsonList));
  }
  
  /// 获取用户的所有绑定关系
  Future<List<BindingModel>> getBindings(String userId) async {
    final prefs = await _preferences;
    
    List<BindingModel> bindings = [];
    
    // 尝试作为parent获取
    final parentJson = prefs.getString('${_bindingsKey}_$userId');
    if (parentJson != null) {
      try {
        final jsonList = jsonDecode(parentJson) as List;
        bindings.addAll(jsonList.map((j) => BindingModel.fromJson(j)));
      } catch (e) {
        // ignore
      }
    }
    
    // 尝试作为child获取（需要遍历）
    final allKeys = prefs.getKeys().where((k) => k.startsWith(_bindingsKey));
    for (final key in allKeys) {
      if (key == '${_bindingsKey}_$userId') continue;
      
      final jsonStr = prefs.getString(key);
      if (jsonStr != null) {
        try {
          final jsonList = jsonDecode(jsonStr) as List;
          for (final j in jsonList) {
            if (j['child_id'] == userId) {
              bindings.add(BindingModel.fromJson(j));
            }
          }
        } catch (e) {
          // ignore
        }
      }
    }
    
    return bindings;
  }
  
  /// 删除绑定关系
  Future<bool> deleteBinding(String bindingId) async {
    final prefs = await _preferences;
    final allKeys = prefs.getKeys().where((k) => k.startsWith(_bindingsKey));
    
    for (final key in allKeys) {
      final jsonStr = prefs.getString(key);
      if (jsonStr != null) {
        try {
          final jsonList = jsonDecode(jsonStr) as List;
          final originalLength = jsonList.length;
          jsonList.removeWhere((j) => j['binding_id'] == bindingId);
          
          if (jsonList.length < originalLength) {
            await prefs.setString(key, jsonEncode(jsonList));
            return true;
          }
        } catch (e) {
          // continue
        }
      }
    }
    return false;
  }
  
  // ==================== 配对码相关 ====================
  
  /// 保存配对码（mock实现）
  Future<String> savePairCode(String childId) async {
    final prefs = await _preferences;
    
    // 生成6位随机数
    final code = DateTime.now().millisecondsSinceEpoch % 1000000;
    final pairCode = code.toString().padLeft(6, '0');
    
    final pairCodesJson = prefs.getString(_pairCodesKey);
    Map<String, dynamic> pairCodes = {};
    if (pairCodesJson != null) {
      try {
        pairCodes = jsonDecode(pairCodesJson);
      } catch (e) {
        // ignore
      }
    }
    
    pairCodes[pairCode] = {
      'child_id': childId,
      'created_at': DateTime.now().toIso8601String(),
      'used': false,
    };
    
    await prefs.setString(_pairCodesKey, jsonEncode(pairCodes));
    return pairCode;
  }
  
  /// 验证并使用配对码
  Future<BindingModel?> verifyPairCode(String pairCode, String parentId) async {
    final prefs = await _preferences;
    
    final pairCodesJson = prefs.getString(_pairCodesKey);
    if (pairCodesJson == null) return null;
    
    try {
      final pairCodes = jsonDecode(pairCodesJson);
      if (!pairCodes.containsKey(pairCode)) return null;
      
      final codeData = pairCodes[pairCode];
      if (codeData['used'] == true) return null;
      
      // 标记为已使用
      codeData['used'] = true;
      await prefs.setString(_pairCodesKey, jsonEncode(pairCodes));
      
      // 创建绑定关系
      final binding = BindingModel(
        bindingId: 'binding_${DateTime.now().millisecondsSinceEpoch}',
        parentId: parentId,
        childId: codeData['child_id'],
        status: 'active',
        createdAt: DateTime.now(),
      );
      
      await saveBinding(binding);
      return binding;
    } catch (e) {
      return null;
    }
  }
  
  // ==================== 清理 ====================
  
  /// 清除所有数据
  Future<void> clearAll() async {
    final prefs = await _preferences;
    await prefs.clear();
  }
}
