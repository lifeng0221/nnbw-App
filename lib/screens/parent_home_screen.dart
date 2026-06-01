import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';
import 'package:audioplayers/audioplayers.dart';
import '../main.dart';
import '../models/app_models.dart';
import '../services/api_service.dart';
import '../services/local_storage_service.dart';
import '../services/voice_service.dart';
import '../services/alarm_service.dart';
import '../widgets/simple_time_picker.dart';
import 'bind_screen.dart';
import 'login_screen.dart';

/// 暖炉风配色
class AppColors {
  static const Color background = Color(0xFFFFF8F0);
  static const Color primary = Color(0xFFFF8C42);
  static const Color confirm = Color(0xFF4CAF50);
  static const Color snooze = Color(0xFFFFB74D);
  static const Color textDark = Color(0xFF3E2723);
  static const Color textSecondary = Color(0xFF8D6E63);
  static const Color cardBg = Color(0xFFFFFFFF);
  static const Color urgent = Color(0xFFE53935);
  static const Color important = Color(0xFFFF9800);
}

/// 老人端首页 — 暖炉风 + 语音 + 删除 + 定时响铃 + 导航
class ParentHomeScreen extends StatefulWidget {
  const ParentHomeScreen({super.key});
  @override
  State<ParentHomeScreen> createState() => _ParentHomeScreenState();
}

class _ParentHomeScreenState extends State<ParentHomeScreen> with TickerProviderStateMixin {
  final VoiceService _voiceService = VoiceService();
  final LocalStorageService _storage = LocalStorageService();
  final AlarmService _alarmService = AlarmService();
  final ApiService _apiService = ApiService();
  final TextEditingController _textController = TextEditingController();
  final AudioPlayer _audioPlayer = AudioPlayer();
  final Uuid _uuid = const Uuid();
  
  // 同步状态
  bool _isSyncing = false;
  int? _serverBindingId; // 后端binding_id（整数）

  // Bug 1 修复: 使用GlobalKey控制Scaffold
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();

  List<ReminderModel> _todayReminders = [];
  bool _isLoading = true;
  bool _isRecording = false;
  String _recognizedText = '';
  String? _recognizedVoiceUrl;
  String _partialText = '';

  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;
  Timer? _recordingTimer;
  Timer? _refreshTimer;
  Timer? _serverSyncTimer; // 定期从服务器同步
  int _recordingSeconds = 0;
  bool _alarmInitialized = false; // 标记alarm是否初始化完成

  @override
  void initState() {
    super.initState();
    _initAnimations();
    // 🔧 v1.0.27: 先初始化服务，完成后再启动定时器
    // 之前的bug：initServices是异步但initState不等它，refreshTimer可能先触发
    _initServices();
  }

  void _initAnimations() {
    _pulseController = AnimationController(duration: const Duration(milliseconds: 1200), vsync: this);
    _pulseAnimation = Tween<double>(begin: 1.0, end: 1.4).animate(CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut));
  }

  /// 初始化所有服务 — v1.0.29: 本地优先架构
  /// 启动顺序：恢复binding_id → 加载本地提醒+启动闹钟 → 同步服务器
  /// 确保即使服务器挂了，本地提醒也能正常响铃
  Future<void> _initServices() async {
    // Step 1: 语音服务（失败不阻塞）
    try {
      await _voiceService.init();
    } catch (e) {
      print('🔴 语音服务初始化失败（不影响核心功能）: $e');
    }
    
    // Step 2: 闹钟服务（失败不阻塞，内部已降级）
    try {
      await _alarmService.init();
    } catch (e) {
      print('🔴 闹钟服务初始化异常（已降级处理）: $e');
    }
    _alarmInitialized = true;
    
    // Step 3: 闹钟回调
    _alarmService.onDiagnosticUpdate = () {
      if (mounted) setState(() {});
    };
    _alarmService.onReminderTriggered = (reminder) {
      _loadReminders();
    };
    
    print('🟢 长辈端: 服务初始化完成，闹钟诊断=${_alarmService.diagnosticText}');
    
    // Step 4: v1.0.29 核心——先从SharedPreferences恢复serverBindingId
    // 这是GPT/Google指出的70%根因：App重启后binding_id丢失导致同步全部失效
    final appState = context.read<AppState>();
    if (appState.userId != null) {
      try {
        final savedBindingId = await _storage.getServerBindingId(appState.userId!);
        if (savedBindingId != null) {
          _serverBindingId = savedBindingId;
          print('🟢 长辈端: 从本地恢复serverBindingId=$_serverBindingId');
        } else {
          print('🟡 长辈端: 本地无保存的serverBindingId');
        }
      } catch (e) {
        print('🔴 恢复serverBindingId失败: $e');
      }
    }
    
    // Step 5: 加载本地提醒+启动闹钟（不依赖服务器）
    try {
      await _loadReminders();
      print('🟢 长辈端: 本地提醒加载完成，${_todayReminders.length}条');
    } catch (e) {
      print('🔴 加载本地提醒失败: $e');
    }
    
    // Step 6: 服务器同步（后台刷新，失败不影响本地功能）
    try {
      await _syncFromServer().timeout(const Duration(seconds: 15));
    } catch (e) {
      print('🔴 服务器同步失败（本地提醒仍可用）: $e');
    }
    
    // Step 7: 启动定时器
    _refreshTimer = Timer.periodic(const Duration(seconds: 10), (_) => _loadReminders());
    _serverSyncTimer = Timer.periodic(const Duration(seconds: 60), (_) => _syncFromServer());
  }

  /// 从后端同步数据到本地（每60秒调用一次 + 首次启动）
  Future<void> _syncFromServer() async {
    final appState = context.read<AppState>();
    if (appState.userId == null) {
      setState(() => _isLoading = false);
      return;
    }

    setState(() => _isSyncing = true);
    
    try {
      print('🟢 长辈端: 开始从服务器同步... userId=${appState.userId}');
      
      // 1. 注册/获取用户
      final userResp = await _apiService.createUser(
        userId: appState.userId!,
        role: 'parent',
        nickname: appState.nickname,
      );
      print('🟢 长辈端: 用户注册/获取结果: ${userResp['success']}');
      
      // 2. 拉取绑定关系
      final bindResp = await _apiService.getBindings(parentId: appState.userId!);
      print('🟢 长辈端: 绑定查询结果: success=${bindResp['success']}, data=${bindResp['data']}');
      if (bindResp['success'] == true && bindResp['data'] is List) {
        final bindings = bindResp['data'] as List;
        for (final j in bindings) {
          final binding = BindingModel(
            bindingId: (j['binding_id'] ?? '').toString(),
            parentId: j['parent_id'] ?? '',
            childId: j['child_id'] ?? '',
            status: j['status'] ?? 'pending',
            createdAt: j['created_at'] != null ? DateTime.parse(j['created_at']) : DateTime.now(),
          );
          await _storage.saveBinding(binding);
          // 🔧 v1.0.27: 正确获取serverBindingId
          // 只取active状态的绑定，取binding_id（整数）
          if (binding.status == 'active' || binding.status == 'pending') {
            final bid = j['binding_id'];
            if (bid is int) {
              _serverBindingId = bid;
              // 🔧 v1.0.29: 立即持久化到SharedPreferences
              await _storage.saveServerBindingId(appState.userId!, bid);
              print('🟢 长辈端: 设置并持久化serverBindingId=$_serverBindingId (status=${binding.status})');
            } else if (bid != null) {
              final parsed = int.tryParse(bid.toString());
              if (parsed != null) {
                _serverBindingId = parsed;
                // 🔧 v1.0.29: 立即持久化到SharedPreferences
                await _storage.saveServerBindingId(appState.userId!, parsed);
                print('🟢 长辈端: 设置并持久化serverBindingId=$_serverBindingId (status=${binding.status})');
              }
            }
          }
        }
      }
      
      // 3. 拉取所有绑定下的提醒
      if (_serverBindingId != null) {
        final reminderResp = await _apiService.getReminders(_serverBindingId!);
        print('🟢 长辈端: 提醒查询结果: success=${reminderResp['success']}, data=${reminderResp['data']}');
        if (reminderResp['success'] == true && reminderResp['data'] is List) {
          final serverReminders = reminderResp['data'] as List;
          for (final j in serverReminders) {
            final serverId = (j['reminder_id'] ?? '').toString();
            final localReminder = await _storage.getReminderById(serverId);
            if (localReminder == null) {
              // 新提醒：从服务器来的，保存到本地
              final reminder = ReminderModel(
                reminderId: serverId,
                bindingId: (j['binding_id'] ?? '').toString(),
                createdBy: j['created_by'] ?? '',
                content: j['content'] ?? '',
                voiceUrl: j['voice_url'],
                triggerTime: j['trigger_time'] != null ? DateTime.parse(j['trigger_time']) : DateTime.now(),
                repeatType: j['repeat_type'] ?? 'once',
                category: j['category'] ?? '生活',
                priority: j['priority'] ?? 'normal',
                status: j['status'] ?? 'pending',
                snoozeCount: j['snooze_count'] ?? 0,
                createdAt: j['created_at'] != null ? DateTime.parse(j['created_at']) : DateTime.now(),
              );
              await _storage.saveReminder(reminder);
              print('🟢 长辈端: 从服务器同步新提醒: ${reminder.content} (${reminder.formattedTime})');
            } else if (localReminder.status == 'pending' && j['status'] != 'pending') {
              await _storage.updateReminderStatus(serverId, j['status']?.toString() ?? 'pending');
              print('🟢 长辈端: 从服务器同步状态更新: $serverId -> ${j['status']}');
            }
          }
        }
      } else {
        print('🟡 长辈端: 没有serverBindingId，无法从服务器同步提醒（尚未绑定子女）');
      }
    } catch (e) {
      print('🔴 长辈端同步失败: $e');
    }
    
    setState(() => _isSyncing = false);
    await _loadReminders();
  }

  Future<void> _loadReminders() async {
    final appState = context.read<AppState>();
    if (appState.userId == null) {
      setState(() => _isLoading = false);
      return;
    }

    var bindings = await _storage.getBindings(appState.userId!);
    if (bindings.isEmpty) {
      final testBinding = BindingModel(bindingId: 'test_binding', parentId: appState.userId!, childId: 'child_test', status: 'active', createdAt: DateTime.now());
      await _storage.saveBinding(testBinding);
      bindings = [testBinding];
    }

    // 收集所有绑定下的提醒（去重）
    List<ReminderModel> allReminders = [];
    final seenIds = <String>{};
    for (final binding in bindings) {
      final reminders = await _storage.getReminders(binding.bindingId);
      for (final r in reminders) {
        if (!seenIds.contains(r.reminderId)) {
          allReminders.add(r);
          seenIds.add(r.reminderId);
        }
      }
    }
    // 兜底：也检查test_binding下的提醒（防止bindingId不匹配导致遗漏）
    final testReminders = await _storage.getReminders('test_binding');
    for (final r in testReminders) {
      if (!seenIds.contains(r.reminderId)) {
        allReminders.add(r);
        seenIds.add(r.reminderId);
      }
    }

    // 显示所有提醒（不限于今天），避免刚创建的提醒因时间过了被过滤掉看不到
    allReminders.sort((a, b) => a.triggerTime.compareTo(b.triggerTime));
    
    print('🔵 加载提醒: ${bindings.length}个绑定, ${allReminders.length}条提醒');

    setState(() { _todayReminders = allReminders; _isLoading = false; });

    // 启动/更新闹钟轮询（传入所有提醒）
    _alarmService.startChecking(allReminders);
  }

  Future<void> _startRecording() async {
    final started = await _voiceService.startListening(
      onPartialResult: (text) => setState(() => _partialText = text),
      onResult: (text) => setState(() { _recognizedText = text; _partialText = ''; }),
    );
    if (started) {
      setState(() { _isRecording = true; _recordingSeconds = 0; });
      _pulseController.repeat(reverse: true);
      _recordingTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
        setState(() => _recordingSeconds++);
        if (_recordingSeconds >= 60) _stopRecording();
      });
    }
  }

  Future<void> _stopRecording() async {
    _recordingTimer?.cancel();
    _pulseController.stop();
    _pulseController.reset();
    final text = await _voiceService.stopListening();
    setState(() { _isRecording = false; if (text.isNotEmpty) _recognizedText = text; _partialText = ''; });
    _showConfirmDialog();
  }

  /// 中文数字转阿拉伯数字
  static int _chineseNumToInt(String s) {
    const map = {'零':0,'一':1,'二':2,'两':2,'三':3,'四':4,'五':5,'六':6,'七':7,'八':8,'九':9,'十':10};
    s = s.trim();
    if (s.isEmpty) return -1;
    // 纯阿拉伯数字
    final n = int.tryParse(s);
    if (n != null) return n;
    // 单字：零~十
    if (map.containsKey(s)) return map[s]!;
    // 十几：十二=12, 十五=15
    if (s.startsWith('十') && s.length > 1) return 10 + (map[s[1]] ?? 0);
    // 几十：二十=20, 三十=30
    if (s.endsWith('十') && s.length > 1) return (map[s[0]] ?? 0) * 10;
    // 几十几：二十三=23
    if (s.contains('十')) {
      final parts = s.split('十');
      final tens = parts[0].isEmpty ? 1 : (map[parts[0]] ?? 0);
      final ones = parts.length > 1 && parts[1].isNotEmpty ? (map[parts[1]] ?? 0) : 0;
      return tens * 10 + ones;
    }
    return -1;
  }

  /// 从文字中智能提取时间（中文自然语言解析）
  /// 支持：12点/十点/九点半、下午3点、半小时后、过一会、一会儿 等
  TimeOfDay? _parseTimeFromText(String text) {
    final now = DateTime.now();
    
    // 先把中文数字替换为阿拉伯数字（保留原文本位置）
    String normalized = text;
    // 语音识别经常输出 "11.30" 或 "11:30" 格式的时间，转成 "11点30分"
    normalized = normalized.replaceAllMapped(
      RegExp(r'(\d{1,2})[.:：](\d{2})'),
      (m) => '${m.group(1)}点${m.group(2)}分',
    );
    
    // ★ 在中文数字归一化之前，先处理"差X分Y点"模式 ★
    // "差十分两点" -> 1:50  /  "差5分钟3点" -> 2:55  /  "差十分两点半" -> 2:20
    // "差一刻两点" -> 1:45  /  "差一刻钟3点" -> 2:45
    final diffKemuMatch = RegExp(r'差\s*一刻(?:钟)?\s*([零一二两三四五六七八九十百\d]+)\s*点半?').firstMatch(normalized);
    if (diffKemuMatch != null) {
      final hVal = _chineseNumToInt(diffKemuMatch.group(1)!);
      final isHalf = normalized.substring(diffKemuMatch.start, diffKemuMatch.end).contains('点半');
      if (hVal > 0) {
        int totalMin = hVal * 60 + (isHalf ? 30 : 0) - 15; // 一刻=15分钟
        if (totalMin < 0) totalMin += 24 * 60;
        print('🔵 时间解析: "$text" -> 差一刻Y点 h=$hVal half=$isHalf -> ${totalMin ~/ 60 % 24}:${totalMin % 60}');
        return TimeOfDay(hour: totalMin ~/ 60 % 24, minute: totalMin % 60);
      }
    }
    final diffMatch = RegExp(r'差\s*([零一二两三四五六七八九十百\d]+)\s*分(?:钟)?\s*([零一二两三四五六七八九十百\d]+)\s*点半?').firstMatch(normalized);
    if (diffMatch != null) {
      final mVal = _chineseNumToInt(diffMatch.group(1)!);
      final hVal = _chineseNumToInt(diffMatch.group(2)!);
      final isHalf = normalized.substring(diffMatch.start, diffMatch.end).contains('点半');
      if (mVal > 0 && hVal > 0) {
        int totalMin = hVal * 60 + (isHalf ? 30 : 0) - mVal;
        if (totalMin < 0) totalMin += 24 * 60;
        print('🔵 时间解析: "$text" -> 差X分Y点 h=$hVal m=$mVal half=$isHalf -> ${totalMin ~/ 60 % 24}:${totalMin % 60}');
        return TimeOfDay(hour: totalMin ~/ 60 % 24, minute: totalMin % 60);
      }
    }
    
    // 替换 "二十三" "十五" "十" "三" 等出现在"点"前的中文数字
    normalized = normalized.replaceAllMapped(
      RegExp(r'([零一二两三四五六七八九十百]+)\s*点'),
      (m) {
        final num = _chineseNumToInt(m.group(1)!);
        return num >= 0 ? '$num点' : m.group(0)!;
      },
    );
    normalized = normalized.replaceAllMapped(
      RegExp(r'([零一二两三四五六七八九十百]+)\s*点半'),
      (m) {
        final num = _chineseNumToInt(m.group(1)!);
        return num >= 0 ? '$num点半' : m.group(0)!;
      },
    );
    normalized = normalized.replaceAllMapped(
      RegExp(r'([零一二两三四五六七八九十百]+)\s*点\s*([零一二两三四五六七八九十百]+)\s*分?'),
      (m) {
        final h = _chineseNumToInt(m.group(1)!);
        final min = _chineseNumToInt(m.group(2)!);
        return (h >= 0 && min >= 0) ? '$h点$min分' : m.group(0)!;
      },
    );
    // 中文分钟数：半小时后、两小时后、十分钟后
    normalized = normalized.replaceAllMapped(
      RegExp(r'([零一二两三四五六七八九十百]+)\s*分钟\s*后'),
      (m) {
        final num = _chineseNumToInt(m.group(1)!);
        return num >= 0 ? '$num分钟后' : m.group(0)!;
      },
    );
    normalized = normalized.replaceAllMapped(
      RegExp(r'([零一二两三四五六七八九十百]+)\s*小时\s*后'),
      (m) {
        final num = _chineseNumToInt(m.group(1)!);
        return num >= 0 ? '$num小时后' : m.group(0)!;
      },
    );
    
    // 1. "X分钟后" / "X分钟后提醒"
    final minMatch = RegExp(r'(\d+)\s*分钟\s*后').firstMatch(normalized);
    if (minMatch != null) {
      final mins = int.tryParse(minMatch.group(1) ?? '') ?? 0;
      if (mins > 0 && mins <= 1440) {
        final target = now.add(Duration(minutes: mins));
        return TimeOfDay(hour: target.hour, minute: target.minute);
      }
    }
    
    // 2. "X小时后"
    final hourMatch = RegExp(r'(\d+)\s*小时\s*后').firstMatch(normalized);
    if (hourMatch != null) {
      final hrs = int.tryParse(hourMatch.group(1) ?? '') ?? 0;
      if (hrs > 0 && hrs <= 24) {
        final target = now.add(Duration(hours: hrs));
        return TimeOfDay(hour: target.hour, minute: target.minute);
      }
    }
    
    // 3. 口语化时间表达
    if (normalized.contains('半小时后') || normalized.contains('半个钟头后') || normalized.contains('半个钟后')) {
      final target = now.add(const Duration(minutes: 30));
      return TimeOfDay(hour: target.hour, minute: target.minute);
    }
    if (normalized.contains('一刻钟后') || normalized.contains('一刻后')) {
      final target = now.add(const Duration(minutes: 15));
      return TimeOfDay(hour: target.hour, minute: target.minute);
    }
    if (normalized.contains('一小时后') || normalized.contains('一个钟头后') || normalized.contains('一个钟后') || normalized.contains('一个小时候')) {
      final target = now.add(const Duration(hours: 1));
      return TimeOfDay(hour: target.hour, minute: target.minute);
    }
    // "过一会"/"一会儿"/"一会"/"等会"/"等一下"/"稍后" → 10分钟后
    if (RegExp(r'过一?(?:会|会儿)|一?会儿|等一?(?:会|下)|稍后|待会').hasMatch(normalized)) {
      final target = now.add(const Duration(minutes: 10));
      return TimeOfDay(hour: target.hour, minute: target.minute);
    }
    // "马上"/"立刻"/"赶紧" → 3分钟后
    if (RegExp(r'马上|立刻|赶紧|即刻|现在就').hasMatch(normalized)) {
      final target = now.add(const Duration(minutes: 3));
      return TimeOfDay(hour: target.hour, minute: target.minute);
    }
    
    // 4. 明确的时间点："X点/X点半/X点XX分"
    bool isAfternoon = false, isMorning = false, isEvening = false;
    if (normalized.contains('下午') || normalized.contains('午后') || normalized.contains('pm')) isAfternoon = true;
    if (normalized.contains('上午') || normalized.contains('早上') || normalized.contains('早晨') || normalized.contains('am')) isMorning = true;
    if (normalized.contains('晚上') || normalized.contains('傍晚') || normalized.contains('夜里') || normalized.contains('夜晚')) isEvening = true;
    
    // "X点半"
    final halfMatch = RegExp(r'(\d+)\s*点半').firstMatch(normalized);
    if (halfMatch != null) {
      var h = int.tryParse(halfMatch.group(1) ?? '') ?? 0;
      if (isAfternoon || isEvening) { if (h < 12) h += 12; }
      else if (isMorning && h == 12) h = 0;
      print('🔵 时间解析: "$text" -> normalized="$normalized" -> 半点匹配 h=$h:30');
      return TimeOfDay(hour: h, minute: 30);
    }
    
    // "X点一刻" = X:15  /  "X点三刻" = X:45
    final kemuMatch = RegExp(r'(\d+)\s*点\s*(一|三)\s*刻').firstMatch(normalized);
    if (kemuMatch != null) {
      var h = int.tryParse(kemuMatch.group(1) ?? '') ?? 0;
      final kemu = kemuMatch.group(2) == '一' ? 15 : 45;
      if (isAfternoon || isEvening) { if (h < 12) h += 12; }
      else if (isMorning && h == 12) h = 0;
      print('🔵 时间解析: "$text" -> X点一刻/三刻匹配 h=$h:m=$kemu');
      return TimeOfDay(hour: h, minute: kemu);
    }
    
    // "X点XX分" / "X点XX"
    final hourMinMatch = RegExp(r'(\d+)\s*点\s*(\d+)\s*分?').firstMatch(normalized);
    if (hourMinMatch != null) {
      var h = int.tryParse(hourMinMatch.group(1) ?? '') ?? 0;
      final m = int.tryParse(hourMinMatch.group(2) ?? '') ?? 0;
      if (isAfternoon || isEvening) { if (h < 12) h += 12; }
      else if (isMorning && h == 12) h = 0;
      print('🔵 时间解析: "$text" -> normalized="$normalized" -> 点分匹配 h=$h:m=$m');
      return TimeOfDay(hour: h, minute: m);
    }
    
    // "X点" — 不带分/半的纯小时
    // 不用lookbehind，用(^|\D)代替，更兼容
    final simpleHourMatch = RegExp(r'(^|\D)(\d{1,2})\s*点(?!\s*[半分\d])').firstMatch(normalized);
    if (simpleHourMatch != null) {
      var h = int.tryParse(simpleHourMatch.group(2) ?? '') ?? -1;
      if (h >= 0 && h <= 24) {
        if (isAfternoon || isEvening) { if (h < 12) h += 12; }
        else if (isMorning && h == 12) h = 0;
        print('🔵 时间解析: "$text" -> normalized="$normalized" -> X点匹配 h=$h');
        return TimeOfDay(hour: h, minute: 0);
      }
    }
    
    print('🔵 时间解析: "$text" -> normalized="$normalized" -> 未识别');
    return null;
  }

  /// 确认弹窗 — 自动提取时间 + selectedTime用State变量
  TimeOfDay? _dialogSelectedTime;
  
  void _showConfirmDialog({String? prefilledText}) {
    final initialText = prefilledText ?? _recognizedText;
    _textController.text = initialText;
    // 初始就尝试解析时间（和子女端一样）
    _dialogSelectedTime = _parseTimeFromText(initialText);
    print('🔵 弹窗打开: text="$initialText", parsed=$_dialogSelectedTime');

    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            // 每次build都重新从当前输入框文本解析时间
            final currentText = _textController.text;
            final parsedTime = _parseTimeFromText(currentText);
            final defaultTime = parsedTime ?? TimeOfDay.fromDateTime(DateTime.now().add(const Duration(minutes: 5)));
            // 关键：优先用_dialogSelectedTime（用户手动改的），其次用当前解析结果，最后兜底
            final displayTime = _dialogSelectedTime ?? parsedTime ?? defaultTime;

            void handleConfirm() {
              Navigator.pop(dialogContext);
              final finalTime = _dialogSelectedTime ?? parsedTime ?? defaultTime;
              print('🔵 确认: dialogSelected=$_dialogSelectedTime, parsed=$parsedTime, final=$finalTime');
              _createReminder(_textController.text, finalTime);
            }

            // 文字变化时重新解析（和子女端一样，直接设置时间）
            void onTextChanged(String val) {
              final parsed = _parseTimeFromText(val);
              print('🔵 文字变化: "$val" -> parsed=$parsed');
              if (parsed != null) {
                setDialogState(() => _dialogSelectedTime = parsed);
              }
            }

            return AlertDialog(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
              contentPadding: const EdgeInsets.all(20),
              title: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(color: AppColors.primary.withOpacity(0.1), borderRadius: BorderRadius.circular(12)),
                    child: const Icon(Icons.edit_note, color: AppColors.primary, size: 28),
                  ),
                  const SizedBox(width: 12),
                  const Text('添加提醒', style: TextStyle(fontSize: 24, color: AppColors.textDark, fontWeight: FontWeight.bold)),
                  const Spacer(),
                  // 解析状态标签
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: parsedTime != null ? Colors.green.withOpacity(0.1) : Colors.red.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(parsedTime != null ? '✓${parsedTime.hour}:${parsedTime.minute.toString().padLeft(2, '0')}' : '✗未识别',
                      style: TextStyle(fontSize: 13, color: parsedTime != null ? Colors.green : Colors.red, fontWeight: FontWeight.bold)),
                  ),
                  const SizedBox(width: 4),
                  IconButton(onPressed: () => Navigator.pop(context), icon: const Icon(Icons.close, size: 28, color: AppColors.textSecondary)),
                ],
              ),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // 提醒内容
                    TextField(
                      controller: _textController,
                      style: const TextStyle(fontSize: 22, color: AppColors.textDark),
                      maxLines: 3,
                      autofocus: true,
                      onChanged: onTextChanged,
                      decoration: InputDecoration(
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: AppColors.primary)),
                        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: AppColors.primary, width: 2)),
                        hintText: '输入提醒内容...',
                        hintStyle: const TextStyle(color: AppColors.textSecondary),
                        contentPadding: const EdgeInsets.all(16),
                      ),
                    ),

                    if (initialText.isNotEmpty && prefilledText == null && _recognizedText.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Row(children: [
                          Icon(Icons.mic, color: AppColors.primary, size: 16),
                          const SizedBox(width: 4),
                          Text('语音识别内容，可修改', style: TextStyle(color: AppColors.primary, fontSize: 13)),
                        ]),
                      ),

                    const SizedBox(height: 16),

                    // 时间设定
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: AppColors.primary.withOpacity(0.06),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: AppColors.primary, width: 2),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(children: [
                            const Icon(Icons.alarm, color: AppColors.primary, size: 24),
                            const SizedBox(width: 8),
                            const Text('提醒时间', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppColors.textDark)),
                          ]),
                          const SizedBox(height: 12),
                          InkWell(
                            onTap: () async {
                              final time = await showModalBottomSheet<TimeOfDay>(
                                context: context,
                                isScrollControlled: true,
                                shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
                                builder: (ctx) => SimpleTimePicker(
                                  initialTime: displayTime,
                                  onTimeSelected: (t) => Navigator.pop(ctx, t),
                                ),
                              );
                              if (time != null) setDialogState(() => _dialogSelectedTime = time);
                            },
                            borderRadius: BorderRadius.circular(14),
                            child: Container(
                              width: double.infinity,
                              padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(14),
                                boxShadow: [BoxShadow(color: AppColors.primary.withOpacity(0.08), blurRadius: 6, offset: const Offset(0, 2))],
                              ),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Text(
                                    _formatTimeOfDay(displayTime),
                                    style: const TextStyle(fontSize: 40, fontWeight: FontWeight.bold, color: AppColors.primary),
                                  ),
                                  const SizedBox(width: 12),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                    decoration: BoxDecoration(color: AppColors.primary, borderRadius: BorderRadius.circular(16)),
                                    child: const Text('修改', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(height: 6),
                          Center(child: Text(
                            _dialogSelectedTime != null
                              ? '✓ 已设定提醒时间 ${_dialogSelectedTime!.hour}:${_dialogSelectedTime!.minute.toString().padLeft(2, "0")}'
                              : (parsedTime != null
                                ? '✓ 已自动识别提醒时间 ${parsedTime.hour}:${parsedTime.minute.toString().padLeft(2, "0")}'
                                : '默认5分钟后提醒'),
                            style: TextStyle(color: _dialogSelectedTime != null || parsedTime != null ? Colors.green : AppColors.textSecondary, fontSize: 14),
                          )),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                SizedBox(
                  width: double.infinity,
                  child: Row(children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () {
                          Navigator.pop(dialogContext);
                          setState(() { _recognizedText = ''; _recognizedVoiceUrl = null; });
                          _textController.clear();
                        },
                        style: OutlinedButton.styleFrom(
                          foregroundColor: AppColors.textSecondary,
                          side: const BorderSide(color: AppColors.textSecondary),
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
                        ),
                        child: const Text('取消', style: TextStyle(fontSize: 18)),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      flex: 2,
                      child: ElevatedButton(
                        // Bug 3 修复: 使用handleConfirm确保传递最新的selectedTime
                        onPressed: handleConfirm,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.primary, foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
                          elevation: 3,
                        ),
                        child: const Text('确认添加', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                      ),
                    ),
                  ]),
                ),
              ],
            );
          },
        );
      },
    );
  }

  String _formatTimeOfDay(TimeOfDay t) => '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

  Future<void> _playVoice(String path) async {
    if (await File(path).exists()) await _audioPlayer.play(DeviceFileSource(path));
  }

  Future<void> _createReminder(String text, TimeOfDay? time) async {
    if (text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('提醒内容不能为空')));
      return;
    }

    final appState = context.read<AppState>();
    if (appState.userId == null) return;

    List<BindingModel> bindings = await _storage.getBindings(appState.userId!);
    if (bindings.isEmpty) {
      final testBinding = BindingModel(bindingId: 'test_binding', parentId: appState.userId!, childId: 'child_test', status: 'active', createdAt: DateTime.now());
      await _storage.saveBinding(testBinding);
      bindings = [testBinding];
    }

    // 精确使用用户选择的时间
    final now = DateTime.now();
    DateTime triggerTime;
    if (time != null) {
      triggerTime = DateTime(now.year, now.month, now.day, time.hour, time.minute);
      // 如果选择的时间已过，顺延到明天
      if (triggerTime.isBefore(now)) triggerTime = triggerTime.add(const Duration(days: 1));
    } else {
      triggerTime = now.add(const Duration(minutes: 5));
    }
    
    print('🔵 创建提醒: text="$text", time=$time, triggerTime=$triggerTime, serverBindingId=$_serverBindingId');

    final reminderId = _uuid.v4();
    final reminder = ReminderModel(
      reminderId: reminderId,
      bindingId: bindings.first.bindingId,
      createdBy: appState.userId!,
      content: text.trim(),
      voiceUrl: _recognizedVoiceUrl,
      triggerTime: triggerTime,
      category: '生活',
      priority: 'normal',
      status: 'pending',
      createdAt: DateTime.now(),
    );

    // 先本地保存
    await _storage.saveReminder(reminder);
    setState(() { _recognizedText = ''; _recognizedVoiceUrl = null; _textController.clear(); });
    await _loadReminders();

    // 异步同步到后端
    if (_serverBindingId != null) {
      _apiService.createReminder(
        bindingId: _serverBindingId!,
        createdBy: appState.userId!,
        content: text.trim(),
        triggerTime: triggerTime.toIso8601String(),
        category: '生活',
        priority: 'normal',
      ).then((resp) {
        if (resp['success'] == true && resp['data'] != null) {
          // 用后端返回的reminder_id更新本地记录
          final serverId = resp['data']['reminder_id']?.toString();
          if (serverId != null && serverId != reminderId) {
            print('后端提醒ID: $serverId, 本地ID: $reminderId');
          }
        }
      }).catchError((e) => print('同步创建提醒失败: $e'));
    }

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text('提醒已添加：${_formatTimeOfDay(TimeOfDay.fromDateTime(triggerTime))} $text'),
      backgroundColor: AppColors.confirm,
    ));
  }

  Future<void> _confirmReminder(ReminderModel r) async {
    await _storage.confirmReminder(r.reminderId);
    await _alarmService.stopAlarmSound();
    // 同步后端
    _syncReminderStatus(r, 'confirmed');
    await _loadReminders();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('已确认完成'), backgroundColor: AppColors.confirm));
  }

  Future<void> _snoozeReminder(ReminderModel r) async {
    await _storage.snoozeReminder(r.reminderId);
    await _alarmService.stopAlarmSound();
    // 关键：snooze后清除triggeredId，让闹钟可以在新时间重新触发
    _alarmService.clearTriggeredId(r.reminderId);
    // 同步后端
    _syncReminderStatus(r, 'snoozed');
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('已延后5分钟提醒'), backgroundColor: AppColors.snooze));
  }

  /// 同步提醒状态到后端（异步，不阻塞UI）
  void _syncReminderStatus(ReminderModel r, String status) {
    // 尝试解析reminderId为整数（后端用整数ID）
    final serverId = int.tryParse(r.reminderId);
    if (serverId != null) {
      if (status == 'snoozed') {
        _apiService.snoozeReminder(serverId).catchError((e) => print('同步snooze失败: $e'));
      } else {
        _apiService.updateReminderStatus(serverId, status == 'confirmed' ? 'confirmed' : status)
          .catchError((e) => print('同步状态失败: $e'));
      }
    }
  }

  Future<void> _deleteReminder(ReminderModel r) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(children: [
          const Icon(Icons.delete_outline, color: AppColors.urgent, size: 28),
          const SizedBox(width: 8),
          const Text('删除提醒', style: TextStyle(fontSize: 22, color: AppColors.textDark)),
        ]),
        content: Text('确定删除"${r.content}"吗？', style: const TextStyle(fontSize: 18)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('取消', style: TextStyle(fontSize: 18))),
          ElevatedButton(onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.urgent, foregroundColor: Colors.white),
            child: const Text('删除', style: TextStyle(fontSize: 18))),
        ],
      ),
    );
    if (confirmed == true) {
      await _storage.deleteReminder(r.reminderId);
      // 同步后端删除
      final serverId = int.tryParse(r.reminderId);
      if (serverId != null) {
        _apiService.deleteReminder(serverId).catchError((e) => print('同步删除失败: $e'));
      }
      await _loadReminders();
    }
  }

  /// 判断提醒来源 — 比对当前用户ID
  String _getCreatorLabel(ReminderModel r) {
    final appState = context.read<AppState>();
    if (appState.userId != null && r.createdBy == appState.userId) {
      return '我自己设的';
    }
    // 也检查测试数据
    if (r.createdBy == 'parent_test' || r.createdBy == appState.userId) {
      return '我自己设的';
    }
    return '子女设的';
  }

  Widget _buildBody() {
    if (_isLoading) return const Center(child: CircularProgressIndicator(color: AppColors.primary));

    if (_todayReminders.isEmpty) {
      return Center(
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          Icon(Icons.notifications_none, size: 80, color: AppColors.primary.withOpacity(0.3)),
          const SizedBox(height: 16),
          const Text('还没有提醒', style: TextStyle(fontSize: 22, color: AppColors.textSecondary)),
          const SizedBox(height: 8),
          const Text('按住下方按钮说话，或输入文字', style: TextStyle(fontSize: 16, color: AppColors.textSecondary)),
        ]),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      itemCount: _todayReminders.length,
      itemBuilder: (context, i) => Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: _buildReminderCard(_todayReminders[i]),
      ),
    );
  }

  Widget _buildReminderCard(ReminderModel r) {
    final isActive = r.status == 'triggered' || r.status == 'snoozed';
    Color leftBorder = AppColors.primary;
    if (r.priority == 'urgent') leftBorder = AppColors.urgent;
    else if (r.priority == 'important') leftBorder = AppColors.important;
    else if (r.status == 'confirmed') leftBorder = AppColors.confirm;

    return Container(
      decoration: BoxDecoration(
        color: AppColors.cardBg,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 8, offset: const Offset(0, 2))],
      ),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          border: Border(left: BorderSide(color: leftBorder, width: 4)),
        ),
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          // 时间 + 状态 + 删除
          Row(children: [
            Text(r.formattedTime, style: const TextStyle(fontSize: 36, fontWeight: FontWeight.bold, color: AppColors.textDark)),
            const SizedBox(width: 12),
            _buildStatusBadge(r),
            if (r.isImportant) ...[
              const SizedBox(width: 6),
              Icon(r.isUrgent ? Icons.priority_high : Icons.flag, color: r.isUrgent ? AppColors.urgent : AppColors.important, size: 20),
            ],
            const Spacer(),
            Container(
              decoration: BoxDecoration(color: AppColors.urgent.withOpacity(0.08), borderRadius: BorderRadius.circular(8)),
              child: IconButton(
                onPressed: () => _deleteReminder(r),
                icon: const Icon(Icons.delete_outline, size: 22, color: AppColors.urgent),
                padding: const EdgeInsets.all(6),
                constraints: const BoxConstraints(),
              ),
            ),
          ]),
          const SizedBox(height: 8),
          Row(children: [
            Expanded(child: Text(r.content, style: const TextStyle(fontSize: 20, color: AppColors.textDark), maxLines: 2, overflow: TextOverflow.ellipsis)),
            if (r.voiceUrl != null && r.voiceUrl!.isNotEmpty)
              IconButton(onPressed: () => _playVoice(r.voiceUrl!), icon: const Icon(Icons.play_circle, size: 32, color: AppColors.primary), padding: EdgeInsets.zero, constraints: const BoxConstraints()),
          ]),
          const SizedBox(height: 4),
          Row(children: [
            _buildTag(_getCreatorLabel(r), AppColors.primary),
            const SizedBox(width: 6),
            _buildTag(r.category, AppColors.textSecondary),
          ]),
          if (isActive)
            Padding(
              padding: const EdgeInsets.only(top: 14),
              child: Row(children: [
                Expanded(
                  child: ElevatedButton(
                    onPressed: () => _confirmReminder(r),
                    style: ElevatedButton.styleFrom(backgroundColor: AppColors.confirm, foregroundColor: Colors.white, minimumSize: const Size(0, 52), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(26))),
                    child: const Text('知道了', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                  ),
                ),
                const SizedBox(width: 12),
                if (r.canSnooze)
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => _snoozeReminder(r),
                      style: OutlinedButton.styleFrom(foregroundColor: AppColors.snooze, side: const BorderSide(color: AppColors.snooze), minimumSize: const Size(0, 52), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(26))),
                      child: const Text('等一下', style: TextStyle(fontSize: 20)),
                    ),
                  ),
              ]),
            ),
        ]),
      ),
    );
  }

  Widget _buildStatusBadge(ReminderModel r) {
    Color bg; Color fg; String label;
    switch (r.status) {
      case 'confirmed': bg = AppColors.confirm.withOpacity(0.1); fg = AppColors.confirm; label = '已完成';
      case 'triggered': case 'snoozed': bg = AppColors.snooze.withOpacity(0.1); fg = AppColors.snooze; label = r.status == 'snoozed' ? '稍后' : '已响铃';
      default: bg = AppColors.primary.withOpacity(0.1); fg = AppColors.primary; label = '待响';
    }
    return Container(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4), decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(6)), child: Text(label, style: TextStyle(fontSize: 14, color: fg, fontWeight: FontWeight.bold)));
  }

  Widget _buildTag(String text, Color color) {
    return Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3), decoration: BoxDecoration(color: color.withOpacity(0.08), borderRadius: BorderRadius.circular(4)), child: Text(text, style: TextStyle(fontSize: 12, color: color)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      key: _scaffoldKey,  // Bug 1 修复: 添加scaffoldKey
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('念念不忘', style: TextStyle(color: AppColors.textDark, fontWeight: FontWeight.bold)),
        centerTitle: true, elevation: 0, backgroundColor: AppColors.background,
        iconTheme: const IconThemeData(color: AppColors.textDark),
        leading: IconButton(
          icon: const Icon(Icons.menu, color: AppColors.textDark, size: 28),
          // Bug 1 修复: 使用scaffoldKey打开drawer
          onPressed: () => _scaffoldKey.currentState?.openDrawer(),
        ),
        actions: [
          IconButton(icon: const Icon(Icons.link, color: AppColors.primary), tooltip: '绑定子女',
            onPressed: () async {
              final result = await Navigator.push(context, MaterialPageRoute(builder: (_) => const BindScreen()));
              // 🔧 v1.0.27: 绑定页面返回后，立即重新同步
              if (result == true) {
                print('🟢 长辈端: 绑定成功返回，重新同步');
                await _syncFromServer();
              }
            }),
        ],
      ),
      // 侧滑菜单
      drawer: _buildDrawer(),
      body: Column(children: [
        // 🔧 v1.0.27: 闹钟诊断信息条（点击可展开详情）
        _buildDiagnosticBar(),
        // 今日提醒统计条
        Container(
          width: double.infinity, padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          decoration: BoxDecoration(color: AppColors.primary.withOpacity(0.08), border: Border(bottom: BorderSide(color: AppColors.primary.withOpacity(0.15)))),
          child: Row(children: [
            const Icon(Icons.wb_sunny, color: AppColors.primary, size: 22),
            const SizedBox(width: 8),
            const Text('提醒列表', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppColors.textDark)),
            const Spacer(),
            Container(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4), decoration: BoxDecoration(color: AppColors.primary, borderRadius: BorderRadius.circular(12)),
              child: Text('${_todayReminders.length}条', style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold))),
          ]),
        ),
        Expanded(child: _buildBody()),
        // 底部输入区
        Container(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
          decoration: BoxDecoration(color: Colors.white, boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.06), blurRadius: 12, offset: const Offset(0, -3))]),
          child: Column(children: [
            if (_partialText.isNotEmpty)
              Container(width: double.infinity, padding: const EdgeInsets.all(10), margin: const EdgeInsets.only(bottom: 8),
                decoration: BoxDecoration(color: AppColors.primary.withOpacity(0.05), borderRadius: BorderRadius.circular(10)),
                child: Row(children: [
                  const Icon(Icons.mic, color: AppColors.primary, size: 16),
                  const SizedBox(width: 6),
                  Expanded(child: Text(_partialText, style: const TextStyle(fontSize: 16, color: AppColors.primary, fontStyle: FontStyle.italic))),
                ])),
            _buildVoiceButton(),
            const SizedBox(height: 12),
            Row(children: [
              Expanded(
                child: Container(
                  decoration: BoxDecoration(color: AppColors.background, borderRadius: BorderRadius.circular(28), border: Border.all(color: AppColors.primary.withOpacity(0.2))),
                  child: TextField(controller: _textController, style: const TextStyle(fontSize: 18, color: AppColors.textDark),
                    decoration: InputDecoration(hintText: '输入提醒内容...', hintStyle: const TextStyle(color: AppColors.textSecondary), border: InputBorder.none, contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14)),
                    onSubmitted: (t) { if (t.isNotEmpty) { _recognizedText = ''; _showConfirmDialog(prefilledText: t); } },
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Container(
                decoration: BoxDecoration(color: AppColors.primary, shape: BoxShape.circle,
                  boxShadow: [BoxShadow(color: AppColors.primary.withOpacity(0.3), blurRadius: 8, offset: const Offset(0, 2))]),
                child: IconButton(
                  onPressed: () { if (_textController.text.isNotEmpty) { _recognizedText = ''; _showConfirmDialog(prefilledText: _textController.text); } },
                  icon: const Icon(Icons.send, color: Colors.white, size: 22), iconSize: 22),
              ),
            ]),
          ]),
        ),
      ]),
    );
  }

  /// v1.0.28: 闹钟诊断信息条
  Widget _buildDiagnosticBar() {
    final alarm = _alarmService;
    final hasError = !alarm.isInitialized || !alarm.isRunning || alarm.monitoredCount == 0;
    final color = hasError ? Colors.red : (alarm.notificationReady ? Colors.green : Colors.orange);
    final icon = hasError ? Icons.error : (alarm.notificationReady ? Icons.check_circle : Icons.warning);
    final text = alarm.diagnosticText;
    
    return GestureDetector(
      onTap: () {
        showDialog(context: context, builder: (ctx) => AlertDialog(
          title: const Text('闹钟诊断', style: TextStyle(fontSize: 22)),
          content: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            _diagRow('轮询初始化', alarm.isInitialized ? '✅ 完成' : '❌ 未完成'),
            _diagRow('通知插件', alarm.notificationReady ? '✅ 就绪' : '❌ 未就绪'),
            _diagRow('轮询运行', alarm.isRunning ? '✅ 运行中' : '❌ 未启动'),
            _diagRow('监听提醒', '${alarm.monitoredCount}条'),
            _diagRow('待响提醒', '${alarm.pendingCount}条'),
            _diagRow('已触发次数', '${alarm.triggerCount}次'),
            _diagRow('上次检查', alarm.lastCheckTime != null ? alarm.lastCheckTime.toString().substring(11, 19) : '无'),
            _diagRow('初始化错误', alarm.initError ?? '无'),
            _diagRow('serverBindingId', _serverBindingId?.toString() ?? '❌ 未获取'),
            _diagRow('userId', context.read<AppState>().userId ?? '无'),
            _diagRow('本地提醒数', _todayReminders.length.toString()),
            const SizedBox(height: 12),
            const Text('如果"监听提醒"为0：提醒数据没传给闹钟', style: TextStyle(color: Colors.red, fontSize: 14)),
            const Text('如果"serverBindingId"未获取：未绑定或绑定未持久化', style: TextStyle(color: Colors.red, fontSize: 14)),
            const Text('如果"通知插件"未就绪：到点不会弹通知，但状态会变', style: TextStyle(color: Colors.orange, fontSize: 14)),
            const Text('v1.0.29: binding_id已持久化，重启不丢失', style: TextStyle(color: Colors.green, fontSize: 14)),
          ])),
          actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('关闭'))],
        ));
      },
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        decoration: BoxDecoration(color: color.withOpacity(0.1), border: Border(bottom: BorderSide(color: color.withOpacity(0.3)))),
        child: Row(children: [
          Icon(icon, color: color, size: 16),
          const SizedBox(width: 8),
          Expanded(child: Text(text, style: TextStyle(fontSize: 12, color: color), overflow: TextOverflow.ellipsis)),
          Icon(Icons.info_outline, color: color.withOpacity(0.5), size: 14),
        ]),
      ),
    );
  }
  
  Widget _diagRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(children: [
        SizedBox(width: 100, child: Text(label, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15))),
        Expanded(child: Text(value, style: const TextStyle(fontSize: 15))),
      ]),
    );
  }

  /// 侧滑菜单
  Widget _buildDrawer() {
    final appState = context.read<AppState>();
    return Drawer(
      child: ListView(
        padding: EdgeInsets.zero,
        children: [
          DrawerHeader(
            decoration: const BoxDecoration(color: AppColors.primary),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.end, children: [
              const Icon(Icons.notifications_active, color: Colors.white, size: 40),
              const SizedBox(height: 8),
              const Text('念念不忘', style: TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold)),
              Text(appState.nickname ?? '老人端', style: const TextStyle(color: Colors.white70, fontSize: 14)),
            ]),
          ),
          ListTile(
            leading: const Icon(Icons.link, color: AppColors.primary),
            title: const Text('绑定子女', style: TextStyle(fontSize: 18)),
            onTap: () async {
              Navigator.pop(context);
              final result = await Navigator.push(context, MaterialPageRoute(builder: (_) => const BindScreen()));
              if (result == true) {
                print('🟢 长辈端: 绑定成功返回，重新同步');
                await _syncFromServer();
              }
            },
          ),
          ListTile(
            leading: const Icon(Icons.volume_up, color: AppColors.primary),
            title: const Text('测试铃声', style: TextStyle(fontSize: 18)),
            onTap: () { Navigator.pop(context); _alarmService.playAlarmSound(); },
          ),
          ListTile(
            leading: const Icon(Icons.notifications, color: AppColors.primary),
            title: const Text('测试通知', style: TextStyle(fontSize: 18)),
            onTap: () {
              Navigator.pop(context);
              _alarmService.showReminderNotification(ReminderModel(
                reminderId: 'test', bindingId: 'test', createdBy: 'test', content: '这是一条测试通知', triggerTime: DateTime.now(), status: 'pending', createdAt: DateTime.now(),
              ));
            },
          ),
          const Divider(),
          ListTile(
            leading: const Icon(Icons.logout, color: AppColors.urgent),
            title: const Text('退出登录', style: TextStyle(fontSize: 18)),
            onTap: () async {
              Navigator.pop(context);
              await appState.logout();
              if (!mounted) return;
              Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const LoginScreen()));
            },
          ),
        ],
      ),
    );
  }

  // Bug 1 修复: 删除_showMenuDrawer()方法，改用scaffoldKey

  Widget _buildVoiceButton() {
    return GestureDetector(
      onLongPressStart: (_) => _startRecording(),
      onLongPressEnd: (_) => _stopRecording(),
      child: AnimatedBuilder(
        animation: _pulseAnimation,
        builder: (context, child) => SizedBox(
          width: double.infinity, height: 80,
          child: Stack(alignment: Alignment.center, children: [
            if (_isRecording)
              Transform.scale(scale: _pulseAnimation.value,
                child: Container(width: 88, height: 88, decoration: BoxDecoration(color: AppColors.urgent.withOpacity(0.15), shape: BoxShape.circle))),
            Container(
              width: 80, height: 80,
              decoration: BoxDecoration(color: _isRecording ? AppColors.urgent : AppColors.primary, shape: BoxShape.circle,
                boxShadow: [BoxShadow(color: (_isRecording ? AppColors.urgent : AppColors.primary).withOpacity(0.35), blurRadius: 16, offset: const Offset(0, 4))]),
              child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                Icon(_isRecording ? Icons.mic : Icons.mic_none, color: Colors.white, size: 32),
                if (_isRecording) Text('${_recordingSeconds}s', style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold)),
                if (!_isRecording) const Text('说话', style: TextStyle(color: Colors.white, fontSize: 11)),
              ]),
            ),
            if (!_isRecording)
              Positioned(bottom: 0, child: Text('按住说话 · 语音转文字', style: TextStyle(color: AppColors.textSecondary, fontSize: 13))),
          ]),
        ),
      ),
    );
  }

  @override
  void dispose() {
    _pulseController.dispose();
    _recordingTimer?.cancel();
    _refreshTimer?.cancel();
    _serverSyncTimer?.cancel();
    _alarmService.stopChecking();
    _voiceService.dispose();
    _textController.dispose();
    _audioPlayer.dispose();
    super.dispose();
  }
}
