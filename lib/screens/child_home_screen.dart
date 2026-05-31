import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';
import 'package:intl/intl.dart';
import '../main.dart';
import '../models/app_models.dart';
import '../services/api_service.dart';
import '../services/local_storage_service.dart';
import '../widgets/reminder_card.dart';
import '../widgets/simple_time_picker.dart';
import 'bind_screen.dart';

/// 子女端首页 — 暖炉风
class ChildHomeScreen extends StatefulWidget {
  const ChildHomeScreen({super.key});
  @override
  State<ChildHomeScreen> createState() => _ChildHomeScreenState();
}

class _ChildHomeScreenState extends State<ChildHomeScreen> {
  final LocalStorageService _storage = LocalStorageService();
  final ApiService _apiService = ApiService();
  final TextEditingController _textController = TextEditingController();
  final Uuid _uuid = const Uuid();

  List<ReminderModel> _reminders = [];
  bool _isLoading = true;
  bool _isSyncing = false;
  int? _serverBindingId; // 后端binding_id（整数）
  String _selectedCategory = '生活';
  String _selectedPriority = 'normal';
  TimeOfDay _selectedTime = TimeOfDay.fromDateTime(DateTime.now().add(const Duration(minutes: 5)));
  DateTime _selectedDate = DateTime.now();

  /// 从文字中智能提取时间（中文自然语言解析）
  /// 支持：12点、下午3点、3点半、半小时后、过一会、一会儿 等
  /// 中文数字转阿拉伯数字
  static int _chineseNumToInt(String s) {
    const map = {'零':0,'一':1,'二':2,'两':2,'三':3,'四':4,'五':5,'六':6,'七':7,'八':8,'九':9,'十':10};
    s = s.trim();
    if (s.isEmpty) return -1;
    final n = int.tryParse(s);
    if (n != null) return n;
    if (map.containsKey(s)) return map[s]!;
    if (s.startsWith('十') && s.length > 1) return 10 + (map[s[1]] ?? 0);
    if (s.endsWith('十') && s.length > 1) return (map[s[0]] ?? 0) * 10;
    if (s.contains('十')) {
      final parts = s.split('十');
      final tens = parts[0].isEmpty ? 1 : (map[parts[0]] ?? 0);
      final ones = parts.length > 1 && parts[1].isNotEmpty ? (map[parts[1]] ?? 0) : 0;
      return tens * 10 + ones;
    }
    return -1;
  }

  TimeOfDay? _parseTimeFromText(String text) {
    final now = DateTime.now();
    
    // 中文数字归一化
    String normalized = text;
    normalized = normalized.replaceAllMapped(
      RegExp(r'([零一二两三四五六七八九十百]+)\s*点'),
      (m) { final num = _chineseNumToInt(m.group(1)!); return num >= 0 ? '$num点' : m.group(0)!; },
    );
    normalized = normalized.replaceAllMapped(
      RegExp(r'([零一二两三四五六七八九十百]+)\s*点半'),
      (m) { final num = _chineseNumToInt(m.group(1)!); return num >= 0 ? '$num点半' : m.group(0)!; },
    );
    normalized = normalized.replaceAllMapped(
      RegExp(r'([零一二两三四五六七八九十百]+)\s*点\s*([零一二两三四五六七八九十百]+)\s*分?'),
      (m) { final h = _chineseNumToInt(m.group(1)!); final min = _chineseNumToInt(m.group(2)!); return (h >= 0 && min >= 0) ? '$h点$min分' : m.group(0)!; },
    );
    normalized = normalized.replaceAllMapped(
      RegExp(r'([零一二两三四五六七八九十百]+)\s*分钟\s*后'),
      (m) { final num = _chineseNumToInt(m.group(1)!); return num >= 0 ? '$num分钟后' : m.group(0)!; },
    );
    normalized = normalized.replaceAllMapped(
      RegExp(r'([零一二两三四五六七八九十百]+)\s*小时\s*后'),
      (m) { final num = _chineseNumToInt(m.group(1)!); return num >= 0 ? '$num小时后' : m.group(0)!; },
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
    // "今天"/"今" 开头+时间 → 今天
    // "明天"/"明早"/"明晚" → 明天
    // 这些暂时不处理日期，只提取时间部分
    
    // 4. 明确的时间点
    bool isAfternoon = false, isMorning = false, isEvening = false;
    if (normalized.contains('下午') || normalized.contains('午后') || normalized.contains('pm')) isAfternoon = true;
    if (normalized.contains('上午') || normalized.contains('早上') || normalized.contains('早晨') || normalized.contains('上午')) isMorning = true;
    if (normalized.contains('晚上') || normalized.contains('傍晚') || normalized.contains('夜里') || normalized.contains('夜晚')) isEvening = true;
    
    // "X点半"
    final halfMatch = RegExp(r'(\d+)\s*点半').firstMatch(normalized);
    if (halfMatch != null) {
      var h = int.tryParse(halfMatch.group(1) ?? '') ?? 0;
      if (isAfternoon || isEvening) { if (h < 12) h += 12; }
      else if (isMorning && h == 12) h = 0;
      return TimeOfDay(hour: h, minute: 30);
    }
    
    // "X点XX分" / "X点XX"
    final hourMinMatch = RegExp(r'(\d+)\s*点\s*(\d+)\s*分?').firstMatch(normalized);
    if (hourMinMatch != null) {
      var h = int.tryParse(hourMinMatch.group(1) ?? '') ?? 0;
      final m = int.tryParse(hourMinMatch.group(2) ?? '') ?? 0;
      if (isAfternoon || isEvening) { if (h < 12) h += 12; }
      else if (isMorning && h == 12) h = 0;
      return TimeOfDay(hour: h, minute: m);
    }
    
    // "X点"
    final simpleHourMatch = RegExp(r'(?<!\d)(\d{1,2})\s*点(?!\s*[半分\d])').firstMatch(normalized);
    if (simpleHourMatch != null) {
      var h = int.tryParse(simpleHourMatch.group(1) ?? '') ?? -1;
      if (h >= 0 && h <= 24) {
        if (isAfternoon || isEvening) { if (h < 12) h += 12; }
        else if (isMorning && h == 12) h = 0;
        return TimeOfDay(hour: h, minute: 0);
      }
    }
    
    return null;
  }

  final List<Map<String, String>> _categories = [
    {'value': '吃药', 'icon': '💊', 'label': '吃药'},
    {'value': '运动', 'icon': '🏃', 'label': '运动'},
    {'value': '生活', 'icon': '🏠', 'label': '生活'},
    {'value': '医疗', 'icon': '🏥', 'label': '医疗'},
    {'value': '其他', 'icon': '📌', 'label': '其他'},
  ];

  @override
  void initState() { super.initState(); _syncFromServer(); }

  /// 从后端同步数据
  Future<void> _syncFromServer() async {
    final appState = context.read<AppState>();
    if (appState.userId == null) { setState(() => _isLoading = false); return; }

    setState(() => _isSyncing = true);
    
    try {
      // 1. 注册/获取用户
      await _apiService.createUser(userId: appState.userId!, role: 'child', nickname: appState.nickname);
      
      // 2. 拉取绑定关系
      final bindResp = await _apiService.getBindings(childId: appState.userId!);
      if (bindResp['success'] == true && bindResp['data'] is List) {
        for (final j in bindResp['data'] as List) {
          final binding = BindingModel(
            bindingId: (j['binding_id'] ?? '').toString(),
            parentId: j['parent_id'] ?? '',
            childId: j['child_id'] ?? '',
            status: j['status'] ?? 'pending',
            createdAt: j['created_at'] != null ? DateTime.parse(j['created_at']) : DateTime.now(),
          );
          await _storage.saveBinding(binding);
          if (binding.status == 'active' && _serverBindingId == null) {
            _serverBindingId = j['binding_id'] as int?;
          }
        }
      }
      
      // 3. 拉取提醒
      if (_serverBindingId != null) {
        final reminderResp = await _apiService.getReminders(_serverBindingId!);
        if (reminderResp['success'] == true && reminderResp['data'] is List) {
          for (final j in reminderResp['data'] as List) {
            final reminder = ReminderModel(
              reminderId: (j['reminder_id'] ?? '').toString(),
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
          }
        }
      }
    } catch (e) {
      debugPrint('子女端同步失败: $e');
    }
    
    setState(() => _isSyncing = false);
    await _loadData();
  }

  Future<void> _loadData() async {
    final appState = context.read<AppState>();
    if (appState.userId == null) { setState(() => _isLoading = false); return; }

    List<BindingModel> bindings = await _storage.getBindings(appState.userId!);
    if (bindings.isEmpty) {
      final testBinding = BindingModel(bindingId: 'test_binding', parentId: 'parent_test', childId: appState.userId!, status: 'active', createdAt: DateTime.now());
      await _storage.saveBinding(testBinding);
      bindings = [testBinding];
    }

    List<ReminderModel> allReminders = [];
    for (final binding in bindings) {
      final reminders = await _storage.getReminders(binding.bindingId);
      allReminders.addAll(reminders);
    }
    if (allReminders.isEmpty) allReminders = await _storage.getReminders('test_binding');
    allReminders.sort((a, b) => a.triggerTime.compareTo(b.triggerTime));

    setState(() { _reminders = allReminders; _isLoading = false; });
  }

  void _showCreateReminderSheet() {
    _selectedCategory = '生活';
    _selectedPriority = 'normal';
    _selectedTime = TimeOfDay.fromDateTime(DateTime.now().add(const Duration(minutes: 5)));
    _selectedDate = DateTime.now();
    _textController.clear();

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (context) => StatefulBuilder(
        builder: (context, setModalState) => Container(
          padding: EdgeInsets.only(left: 20, right: 20, top: 16, bottom: MediaQuery.of(context).viewInsets.bottom + 20),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(children: [
                      Container(padding: const EdgeInsets.all(10), decoration: BoxDecoration(color: const Color(0xFFFF8C42).withOpacity(0.1), borderRadius: BorderRadius.circular(10)),
                        child: const Icon(Icons.add_alarm, color: Color(0xFFFF8C42))),
                      const SizedBox(width: 12),
                      const Text('为爸妈设提醒', style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Color(0xFF3E2723))),
                    ]),
                    IconButton(onPressed: () => Navigator.pop(context), icon: const Icon(Icons.close, color: Color(0xFF8D6E63))),
                  ],
                ),
                const SizedBox(height: 20),

                TextField(
                  controller: _textController,
                  style: const TextStyle(fontSize: 18, color: Color(0xFF3E2723)),
                  maxLines: 3, autofocus: true,
                  decoration: InputDecoration(
                    labelText: '提醒内容', hintText: '例如：记得吃药，下午3点',
                    labelStyle: const TextStyle(color: Color(0xFFFF8C42)),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                    focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Color(0xFFFF8C42), width: 2)),
                    contentPadding: const EdgeInsets.all(16),
                  ),
                  onChanged: (text) {
                    // 智能提取时间，自动更新选择器
                    final parsed = _parseTimeFromText(text);
                    if (parsed != null) {
                      setModalState(() => _selectedTime = parsed);
                    }
                  },
                ),
                const SizedBox(height: 20),

                const Text('提醒日期', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Color(0xFF3E2723))),
                const SizedBox(height: 8),
                Wrap(spacing: 8, children: [
                  _buildDateChip('今天', DateTime.now(), setModalState),
                  _buildDateChip('明天', DateTime.now().add(const Duration(days: 1)), setModalState),
                  _buildDateChip('后天', DateTime.now().add(const Duration(days: 2)), setModalState),
                ]),
                const SizedBox(height: 16),

                // 时间 — 醒目显示
                const Text('提醒时间', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Color(0xFF3E2723))),
                const SizedBox(height: 8),
                InkWell(
                  onTap: () async {
                    final time = await showModalBottomSheet<TimeOfDay>(
                      context: context,
                      isScrollControlled: true,
                      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
                      builder: (ctx) => SimpleTimePicker(initialTime: _selectedTime, onTimeSelected: (t) => Navigator.pop(ctx, t)),
                    );
                    if (time != null) setModalState(() => _selectedTime = time);
                  },
                  child: Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      border: Border.all(color: const Color(0xFFFF8C42), width: 2),
                      borderRadius: BorderRadius.circular(12),
                      color: const Color(0xFFFF8C42).withOpacity(0.05),
                    ),
                    child: Row(children: [
                      const Icon(Icons.access_time, color: Color(0xFFFF8C42), size: 24),
                      const SizedBox(width: 12),
                      Text(_selectedTime.format(context), style: const TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: Color(0xFFFF8C42))),
                      const Spacer(),
                      Container(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                        decoration: BoxDecoration(color: const Color(0xFFFF8C42), borderRadius: BorderRadius.circular(16)),
                        child: const Text('修改', style: TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold))),
                    ]),
                  ),
                ),
                const SizedBox(height: 20),

                const Text('分类', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Color(0xFF3E2723))),
                const SizedBox(height: 8),
                Wrap(spacing: 8, runSpacing: 8,
                  children: _categories.map((cat) {
                    final isSelected = _selectedCategory == cat['value'];
                    return ChoiceChip(
                      label: Text('${cat['icon']} ${cat['label']}', style: TextStyle(fontSize: 16, color: isSelected ? Colors.white : const Color(0xFF3E2723))),
                      selected: isSelected, selectedColor: const Color(0xFFFF8C42),
                      onSelected: (_) => setModalState(() => _selectedCategory = cat['value']!),
                    );
                  }).toList(),
                ),
                const SizedBox(height: 20),

                const Text('优先级', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Color(0xFF3E2723))),
                const SizedBox(height: 8),
                Row(children: [
                  _buildPriorityChip('普通', 'normal', Colors.grey, setModalState),
                  const SizedBox(width: 8),
                  _buildPriorityChip('重要', 'important', const Color(0xFFFF9800), setModalState),
                  const SizedBox(width: 8),
                  _buildPriorityChip('紧急', 'urgent', const Color(0xFFE53935), setModalState),
                ]),
                const SizedBox(height: 24),

                SizedBox(
                  width: double.infinity, height: 56,
                  child: ElevatedButton(
                    onPressed: () { Navigator.pop(context); _createReminder(); },
                    style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFFF8C42), foregroundColor: Colors.white, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28))),
                    child: const Text('确认添加提醒', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildDateChip(String label, DateTime date, StateSetter setModalState) {
    final isSelected = _selectedDate.year == date.year && _selectedDate.month == date.month && _selectedDate.day == date.day;
    return ChoiceChip(label: Text(label), selected: isSelected, selectedColor: const Color(0xFFFF8C42),
      labelStyle: TextStyle(color: isSelected ? Colors.white : const Color(0xFF3E2723)),
      onSelected: (_) => setModalState(() => _selectedDate = date));
  }

  Widget _buildPriorityChip(String label, String value, Color color, StateSetter setModalState) {
    final isSelected = _selectedPriority == value;
    return ChoiceChip(label: Text(label, style: TextStyle(color: isSelected ? Colors.white : color)),
      selected: isSelected, selectedColor: color, backgroundColor: color.withOpacity(0.1), side: BorderSide(color: color),
      onSelected: (_) => setModalState(() => _selectedPriority = value));
  }

  Future<void> _createReminder() async {
    final text = _textController.text.trim();
    if (text.isEmpty) { ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('请输入提醒内容'))); return; }

    final appState = context.read<AppState>();
    if (appState.userId == null) return;

    List<BindingModel> bindings = await _storage.getBindings(appState.userId!);
    if (bindings.isEmpty) bindings = await _storage.getBindings('child_test');
    if (bindings.isEmpty) {
      final testBinding = BindingModel(bindingId: 'test_binding', parentId: 'parent_test', childId: appState.userId!, status: 'active', createdAt: DateTime.now());
      await _storage.saveBinding(testBinding);
      bindings = [testBinding];
    }

    final binding = bindings.first;
    var triggerTime = DateTime(_selectedDate.year, _selectedDate.month, _selectedDate.day, _selectedTime.hour, _selectedTime.minute);

    // 如果是今天且时间已过，自动顺延到明天
    final now = DateTime.now();
    if (_selectedDate.year == now.year && _selectedDate.month == now.month && _selectedDate.day == now.day && triggerTime.isBefore(now)) {
      triggerTime = triggerTime.add(const Duration(days: 1));
    }

    final reminder = ReminderModel(
      reminderId: _uuid.v4(), bindingId: binding.bindingId, createdBy: appState.userId!,
      content: text, triggerTime: triggerTime, category: _selectedCategory, priority: _selectedPriority,
      status: 'pending', createdAt: DateTime.now(),
    );

    await _storage.saveReminder(reminder);
    _textController.clear();
    await _loadData();

    // 异步同步到后端
    if (_serverBindingId != null) {
      _apiService.createReminder(
        bindingId: _serverBindingId!,
        createdBy: appState.userId!,
        content: text,
        triggerTime: triggerTime.toIso8601String(),
        category: _selectedCategory,
        priority: _selectedPriority,
      ).catchError((e) => debugPrint('子女端同步创建失败: $e'));
    }

    if (!mounted) return;
    final timeStr = DateFormat('MM/dd HH:mm').format(triggerTime);
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('提醒已添加：$timeStr'), backgroundColor: const Color(0xFF4CAF50)));
  }

  Future<void> _deleteReminder(ReminderModel reminder) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('删除提醒'), content: Text('确定删除"${reminder.content}"吗？'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('取消')),
          ElevatedButton(onPressed: () => Navigator.pop(context, true), style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFE53935)), child: const Text('删除')),
        ],
      ),
    );
    if (confirmed == true) {
      await _storage.deleteReminder(reminder.reminderId);
      // 同步后端删除
      final serverId = int.tryParse(reminder.reminderId);
      if (serverId != null) {
        _apiService.deleteReminder(serverId).catchError((e) => debugPrint('同步删除失败: $e'));
      }
      await _loadData();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFFFF8F0),
      appBar: AppBar(
        title: const Text('念念不忘', style: TextStyle(color: Color(0xFF3E2723), fontWeight: FontWeight.bold)),
        centerTitle: true, elevation: 0, backgroundColor: const Color(0xFFFFF8F0),
        iconTheme: const IconThemeData(color: Color(0xFF3E2723)),
        actions: [
          IconButton(icon: const Icon(Icons.link, color: Color(0xFFFF8C42)), tooltip: '生成配对码',
            onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const BindScreen()))),
        ],
      ),
      body: _isLoading
        ? const Center(child: CircularProgressIndicator(color: Color(0xFFFF8C42)))
        : RefreshIndicator(
            color: const Color(0xFFFF8C42), onRefresh: _loadData,
            child: SingleChildScrollView(
              physics: const AlwaysScrollableScrollPhysics(), padding: const EdgeInsets.all(16),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                _buildParentStatusCard(),
                const SizedBox(height: 24),
                Row(children: [
                  Container(width: 4, height: 24, decoration: BoxDecoration(color: const Color(0xFFFF8C42), borderRadius: BorderRadius.circular(2))),
                  const SizedBox(width: 8),
                  const Text('提醒列表', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Color(0xFF3E2723))),
                  const Spacer(),
                  Text('共${_reminders.length}条', style: const TextStyle(color: Color(0xFF8D6E63))),
                ]),
                const SizedBox(height: 12),
                if (_reminders.isEmpty) _buildEmptyState()
                else ..._reminders.map((r) => Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: ReminderCard(reminder: r, isParent: false, onDelete: () => _deleteReminder(r)),
                )),
                const SizedBox(height: 80),
              ]),
            ),
          ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _showCreateReminderSheet, icon: const Icon(Icons.add), label: const Text('设提醒'),
        backgroundColor: const Color(0xFFFF8C42), foregroundColor: Colors.white,
      ),
    );
  }

  Widget _buildParentStatusCard() {
    final pending = _reminders.where((r) => r.status == 'pending' || r.status == 'triggered').length;
    final confirmed = _reminders.where((r) => r.status == 'confirmed').length;
    final snoozed = _reminders.where((r) => r.status == 'snoozed').length;
    return Card(
      elevation: 2, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(padding: const EdgeInsets.all(20), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Container(padding: const EdgeInsets.all(10), decoration: BoxDecoration(color: const Color(0xFFFF8C42).withOpacity(0.1), borderRadius: BorderRadius.circular(12)),
            child: const Icon(Icons.family_restroom, size: 28, color: Color(0xFFFF8C42))),
          const SizedBox(width: 12),
          const Text('看看爸妈', style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Color(0xFF3E2723))),
        ]),
        const SizedBox(height: 20),
        Row(mainAxisAlignment: MainAxisAlignment.spaceAround, children: [
          _buildStatItem('待响', pending.toString(), const Color(0xFFFF8C42)),
          _buildStatItem('已完成', confirmed.toString(), const Color(0xFF4CAF50)),
          _buildStatItem('稍后', snoozed.toString(), const Color(0xFFFFB74D)),
        ]),
      ])),
    );
  }

  Widget _buildStatItem(String label, String value, Color color) {
    return Column(children: [
      Container(width: 56, height: 56, decoration: BoxDecoration(color: color.withOpacity(0.1), borderRadius: BorderRadius.circular(16)),
        child: Center(child: Text(value, style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: color)))),
      const SizedBox(height: 8),
      Text(label, style: const TextStyle(fontSize: 14, color: Color(0xFF8D6E63))),
    ]);
  }

  Widget _buildEmptyState() {
    return Container(
      width: double.infinity, padding: const EdgeInsets.all(32),
      decoration: BoxDecoration(color: const Color(0xFFFF8C42).withOpacity(0.05), borderRadius: BorderRadius.circular(16), border: Border.all(color: const Color(0xFFFF8C42).withOpacity(0.15))),
      child: Column(children: [
        Icon(Icons.notifications_none, size: 64, color: const Color(0xFFFF8C42).withOpacity(0.4)),
        const SizedBox(height: 16),
        const Text('还没有提醒', style: TextStyle(fontSize: 18, color: Color(0xFF8D6E63))),
        const SizedBox(height: 8),
        const Text('点击右下角按钮为爸妈添加提醒', style: TextStyle(fontSize: 14, color: Color(0xFF8D6E63))),
      ]),
    );
  }

  @override
  void dispose() { _textController.dispose(); super.dispose(); }
}
