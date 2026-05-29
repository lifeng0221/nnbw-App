import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../main.dart';
import '../models/app_models.dart';
import '../services/api_service.dart';
import '../services/voice_service.dart';
import '../services/alarm_service.dart';
import '../widgets/reminder_card.dart';
import 'bind_screen.dart';

/// 子女端首页
class ChildHomeScreen extends StatefulWidget {
  const ChildHomeScreen({super.key});
  
  @override
  State<ChildHomeScreen> createState() => _ChildHomeScreenState();
}

class _ChildHomeScreenState extends State<ChildHomeScreen> {
  final VoiceService _voiceService = VoiceService();
  final ApiService _api = ApiService();
  final TextEditingController _textController = TextEditingController();
  
  List<ReminderModel> _reminders = [];
  Map<String, dynamic>? _parentStatus; // 父母今日状态
  bool _isLoading = true;
  bool _isRecording = false;
  String _recognizedText = '';
  String? _voicePath;
  
  // 创建提醒的选项
  String _selectedCategory = '生活';
  String _selectedPriority = 'normal';
  String? _selectedBindingId;
  
  final List<Map<String, String>> _categories = [
    {'value': '吃药', 'icon': '💊', 'label': '吃药'},
    {'value': '运动', 'icon': '🏃', 'label': '运动'},
    {'value': '生活', 'icon': '🏠', 'label': '生活'},
    {'value': '医疗', 'icon': '🏥', 'label': '医疗'},
    {'value': '其他', 'icon': '📌', 'label': '其他'},
  ];
  
  final List<Map<String, String>> _priorities = [
    {'value': 'normal', 'label': '普通', 'color': 'grey'},
    {'value': 'important', 'label': '重要', 'color': 'orange'},
    {'value': 'urgent', 'label': '紧急', 'color': 'red'},
  ];
  
  @override
  void initState() {
    super.initState();
    _loadData();
  }
  
  Future<void> _loadData() async {
    final appState = context.read<AppState>();
    
    // 并行加载
    final results = await Future.wait([
      _api.getReminders(appState.userId!),
      _api.getBindings(appState.userId!),
    ]);
    
    final reminderResult = results[0];
    final bindingResult = results[1];
    
    List<ReminderModel> reminders = [];
    if (reminderResult['reminders'] != null) {
      reminders = (reminderResult['reminders'] as List)
          .map((r) => ReminderModel.fromJson(r))
          .toList();
      reminders.sort((a, b) => a.triggerTime.compareTo(b.triggerTime));
    }
    
    // 取第一个绑定
    if (bindingResult['bindings'] != null && 
        (bindingResult['bindings'] as List).isNotEmpty) {
      _selectedBindingId = bindingResult['bindings'][0]['binding_id'];
    }
    
    // 统计父母今日状态
    final today = DateTime.now();
    final todayReminders = reminders.where((r) =>
        r.triggerTime.year == today.year &&
        r.triggerTime.month == today.month &&
        r.triggerTime.day == today.day).toList();
    
    final confirmed = todayReminders.where((r) => r.status == 'confirmed').length;
    final pending = todayReminders.where((r) => 
        r.status == 'triggered' || r.status == 'snoozed').length;
    
    setState(() {
      _reminders = reminders;
      _parentStatus = {
        'total': todayReminders.length,
        'confirmed': confirmed,
        'pending': pending,
      };
      _isLoading = false;
    });
  }
  
  /// 开始录音
  Future<void> _startRecording() async {
    final started = await _voiceService.startRecording();
    if (started) {
      setState(() => _isRecording = true);
    }
  }
  
  /// 停止录音并识别
  Future<void> _stopRecording() async {
    final path = await _voiceService.stopRecording();
    setState(() => _isRecording = false);
    
    if (path != null) {
      _voicePath = path;
      setState(() => _recognizedText = '正在识别...');
      
      final result = await _voiceService.transcribe(path);
      if (result != null) {
        setState(() => _recognizedText = result['text'] ?? '');
        _showCreateReminderSheet();
      }
    }
  }
  
  /// 显示创建提醒的底部面板
  void _showCreateReminderSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (context) => StatefulBuilder(
        builder: (context, setModalState) => Container(
          padding: EdgeInsets.only(
            left: 16, right: 16, 
            top: 16, 
            bottom: MediaQuery.of(context).viewInsets.bottom + 16,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('为爸妈设提醒', style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              
              // 提醒内容
              TextField(
                controller: _textController..text = _recognizedText,
                style: const TextStyle(fontSize: 18),
                maxLines: 2,
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                  hintText: '提醒内容',
                ),
              ),
              const SizedBox(height: 12),
              
              // 分类选择
              const Text('分类', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                children: _categories.map((cat) => 
                  ChoiceChip(
                    label: Text('${cat['icon']} ${cat['label']}', style: const TextStyle(fontSize: 16)),
                    selected: _selectedCategory == cat['value'],
                    onSelected: (_) => setModalState(() => _selectedCategory = cat['value']!),
                  ),
                ).toList(),
              ),
              const SizedBox(height: 12),
              
              // 优先级选择
              const Text('优先级', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                children: _priorities.map((pri) => 
                  ChoiceChip(
                    label: Text(pri['label']!, style: const TextStyle(fontSize: 16)),
                    selected: _selectedPriority == pri['value'],
                    onSelected: (_) => setModalState(() => _selectedPriority = pri['value']!),
                    selectedColor: pri['color'] == 'red' ? Colors.red[100] 
                        : pri['color'] == 'orange' ? Colors.orange[100] 
                        : Colors.grey[200],
                  ),
                ).toList(),
              ),
              const SizedBox(height: 16),
              
              // 确认按钮
              SizedBox(
                width: double.infinity,
                height: 52,
                child: ElevatedButton(
                  onPressed: () {
                    Navigator.pop(context);
                    _createReminder(_textController.text);
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.blue,
                    foregroundColor: Colors.white,
                  ),
                  child: const Text('确认添加', style: TextStyle(fontSize: 20)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
  
  /// 创建提醒
  Future<void> _createReminder(String text) async {
    final appState = context.read<AppState>();
    
    if (_selectedBindingId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请先绑定老人')),
      );
      return;
    }
    
    final result = await _api.naturalCreateReminder(
      bindingId: _selectedBindingId!,
      createdBy: appState.userId!,
      text: text,
      category: _selectedCategory,
      priority: _selectedPriority,
    );
    
    if (result['reminder_id'] != null || result['trigger_time'] != null) {
      final reminder = ReminderModel.fromJson(result);
      await 
      
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('提醒已添加：${result['time_display'] ?? '已设定'}')),
      );
      _loadData();
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('添加失败：${result['error'] ?? '未知错误'}')),
      );
    }
    
    _textController.clear();
    setState(() {
      _recognizedText = '';
      _voicePath = null;
    });
  }
  
  @override
  Widget build(BuildContext context) {
    final appState = context.watch<AppState>();
    
    return Scaffold(
      appBar: AppBar(
        title: const Text('念念不忘'),
        actions: [
          IconButton(
            icon: const Icon(Icons.link),
            onPressed: () => Navigator.push(
              context, 
              MaterialPageRoute(builder: (_) => const BindScreen()),
            ),
            tooltip: '绑定管理',
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 看看爸妈状态卡片
                  _buildParentStatusCard(),
                  const SizedBox(height: 20),
                  
                  // 快捷设提醒
                  _buildQuickActions(),
                  const SizedBox(height: 20),
                  
                  // 提醒列表
                  const Text('提醒列表', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 12),
                  _buildReminderList(),
                ],
              ),
            ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _showCreateReminderSheet,
        icon: const Icon(Icons.add),
        label: const Text('设提醒'),
      ),
    );
  }
  
  Widget _buildParentStatusCard() {
    final total = _parentStatus?['total'] ?? 0;
    final confirmed = _parentStatus?['confirmed'] ?? 0;
    final pending = _parentStatus?['pending'] ?? 0;
    
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.family_restroom, size: 28),
                const SizedBox(width: 8),
                const Text('看看爸妈', style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _buildStatItem('今日提醒', total.toString(), Colors.blue),
                _buildStatItem('已完成', confirmed.toString(), Colors.green),
                _buildStatItem('待确认', pending.toString(), 
                    pending > 0 ? Colors.red : Colors.grey),
              ],
            ),
            if (pending > 0) ...[
              const SizedBox(height: 12),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.red[50],
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Text(
                  '有提醒待确认，请关注',
                  style: TextStyle(fontSize: 16, color: Colors.red),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
  
  Widget _buildStatItem(String label, String value, Color color) {
    return Column(
      children: [
        Text(value, style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: color)),
        const SizedBox(height: 4),
        Text(label, style: const TextStyle(fontSize: 14, color: Colors.grey)),
      ],
    );
  }
  
  Widget _buildQuickActions() {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        _buildQuickChip('💊 吃药', '吃药'),
        _buildQuickChip('🏃 遛弯', '运动'),
        _buildQuickChip('💧 喝水', '生活'),
        _buildQuickChip('🏥 复查', '医疗'),
      ],
    );
  }
  
  Widget _buildQuickChip(String label, String category) {
    return ActionChip(
      label: Text(label, style: const TextStyle(fontSize: 16)),
      onPressed: () {
        setState(() {
          _selectedCategory = category;
          _recognizedText = label.replaceAll(RegExp(r'[^\u4e00-\u9fa5]'), '');
        });
        _showCreateReminderSheet();
      },
    );
  }
  
  Widget _buildReminderList() {
    if (_reminders.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(32),
          child: Text('还没有提醒，点击下方按钮添加', style: TextStyle(color: Colors.grey, fontSize: 16)),
        ),
      );
    }
    
    return Column(
      children: _reminders.map((r) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: ReminderCard(
          reminder: r,
          isParent: false,
          onPlayVoice: r.voiceUrl != null
              ? () => AlarmService().playVoice(r.voiceUrl!)
              : null,
          onDelete: () async {
            await _api.deleteReminder(r.reminderId);
            _loadData();
          },
        ),
      )).toList(),
    );
  }
  
  @override
  void dispose() {
    _voiceService.dispose();
    _textController.dispose();
    super.dispose();
  }
}
