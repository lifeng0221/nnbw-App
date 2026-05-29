import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../main.dart';
import '../models/app_models.dart';
import '../services/api_service.dart';
import '../services/voice_service.dart';
import '../services/alarm_service.dart';
import '../widgets/reminder_card.dart';
import 'bind_screen.dart';

/// 老人端首页
class ParentHomeScreen extends StatefulWidget {
  const ParentHomeScreen({super.key});
  
  @override
  State<ParentHomeScreen> createState() => _ParentHomeScreenState();
}

class _ParentHomeScreenState extends State<ParentHomeScreen> {
  final VoiceService _voiceService = VoiceService();
  final ApiService _api = ApiService();
  final TextEditingController _textController = TextEditingController();
  
  List<ReminderModel> _todayReminders = [];
  bool _isLoading = true;
  bool _isRecording = false;
  String _recognizedText = '';
  String? _voicePath;
  String? _voiceUrl;
  
  @override
  void initState() {
    super.initState();
    _loadReminders();
    _checkBinding();
  }
  
  Future<void> _loadReminders() async {
    final appState = context.read<AppState>();
    final result = await _api.getReminders(appState.userId!);
    
    if (result['reminders'] != null) {
      final list = (result['reminders'] as List)
          .map((r) => ReminderModel.fromJson(r))
          .toList();
      
      // 过滤今日提醒
      final now = DateTime.now();
      final today = list.where((r) {
        return r.triggerTime.year == now.year &&
            r.triggerTime.month == now.month &&
            r.triggerTime.day == now.day;
      }).toList();
      
      // 按时间排序
      today.sort((a, b) => a.triggerTime.compareTo(b.triggerTime));
      
      setState(() {
        _todayReminders = today;
        _isLoading = false;
      });
    } else {
      setState(() => _isLoading = false);
    }
  }
  
  Future<void> _checkBinding() async {
    final appState = context.read<AppState>();
    final result = await _api.getBindings(appState.userId!);
    
    if (result['bindings'] == null || (result['bindings'] as List).isEmpty) {
      // 未绑定，引导绑定
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('还没有绑定子女，请先绑定')),
        );
      }
    }
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
      
      // 显示加载
      setState(() => _recognizedText = '正在识别...');
      
      // 上传并识别
      final result = await _voiceService.transcribe(path);
      if (result != null) {
        setState(() {
          _recognizedText = result['text'] ?? '';
          _voiceUrl = result['voiceUrl'];
        });
        // 弹出确认弹窗
        _showConfirmDialog();
      } else {
        setState(() => _recognizedText = '识别失败，请重试或手动输入');
      }
    }
  }
  
  /// 确认添加提醒弹窗
  void _showConfirmDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: const Text('确认提醒', style: TextStyle(fontSize: 22)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _textController..text = _recognizedText,
              style: const TextStyle(fontSize: 20),
              maxLines: 3,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                hintText: '修改提醒内容',
              ),
            ),
            const SizedBox(height: 12),
            if (_voicePath != null)
              TextButton.icon(
                onPressed: () => AlarmService().playVoice(_voicePath!),
                icon: const Icon(Icons.play_circle),
                label: const Text('听原声', style: TextStyle(fontSize: 16)),
              ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              _resetInput();
            },
            child: const Text('取消', style: TextStyle(fontSize: 18)),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              _createReminder(_textController.text);
            },
            style: ElevatedButton.styleFrom(
              minimumSize: const Size(120, 48),
            ),
            child: const Text('确认添加', style: TextStyle(fontSize: 18)),
          ),
        ],
      ),
    );
  }
  
  /// 创建提醒
  Future<void> _createReminder(String text) async {
    final appState = context.read<AppState>();
    
    // 获取绑定ID
    final bindResult = await _api.getBindings(appState.userId!);
    String? bindingId;
    if (bindResult['bindings'] != null && (bindResult['bindings'] as List).isNotEmpty) {
      bindingId = bindResult['bindings'][0]['binding_id'];
    }
    
    if (bindingId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请先绑定子女')),
      );
      return;
    }
    
    final result = await _api.naturalCreateReminder(
      bindingId: bindingId,
      createdBy: appState.userId!,
      text: text,
      voiceUrl: _voiceUrl,
    );
    
    if (result['reminder_id'] != null || result['trigger_time'] != null) {
      // 注册系统闹钟
      final reminder = ReminderModel.fromJson(result);
      await AlarmService().scheduleReminder(reminder);
      
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('提醒已添加：${result['time_display'] ?? '已设定时间'}')),
      );
      
      _loadReminders();
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('添加失败：${result['error'] ?? '未知错误'}')),
      );
    }
    
    _resetInput();
  }
  
  void _resetInput() {
    _textController.clear();
    setState(() {
      _recognizedText = '';
      _voicePath = null;
      _voiceUrl = null;
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
            tooltip: '绑定子女',
          ),
        ],
      ),
      body: Column(
        children: [
          // 今日提醒列表
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _todayReminders.isEmpty
                    ? _buildEmptyState()
                    : _buildReminderList(),
          ),
          
          // 未确认提醒提示
          _buildPendingAlert(),
          
          // 语音输入区
          _buildVoiceInput(),
          
          // 文字输入区（备选）
          _buildTextInput(),
        ],
      ),
    );
  }
  
  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.notifications_none, size: 64, color: Colors.grey[400]),
          const SizedBox(height: 16),
          const Text('今天还没有提醒', style: TextStyle(fontSize: 20, color: Colors.grey)),
          const SizedBox(height: 8),
          const Text('按住下方按钮说话添加', style: TextStyle(fontSize: 16, color: Colors.grey)),
        ],
      ),
    );
  }
  
  Widget _buildReminderList() {
    return RefreshIndicator(
      onRefresh: _loadReminders,
      child: ListView.builder(
        padding: const EdgeInsets.all(12),
        itemCount: _todayReminders.length,
        itemBuilder: (context, index) {
          return ReminderCard(
            reminder: _todayReminders[index],
            isParent: true,
            onConfirm: () => _confirmReminder(_todayReminders[index]),
            onSnooze: () => _snoozeReminder(_todayReminders[index]),
            onPlayVoice: _todayReminders[index].voiceUrl != null
                ? () => AlarmService().playVoice(_todayReminders[index].voiceUrl!)
                : null,
          );
        },
      ),
    );
  }
  
  Widget _buildPendingAlert() {
    final pending = _todayReminders.where((r) => 
        r.status == 'triggered' || r.status == 'snoozed').toList();
    
    if (pending.isEmpty) return const SizedBox.shrink();
    
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      color: Colors.orange[100],
      child: Row(
        children: [
          const Icon(Icons.warning, color: Colors.orange),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              '您有${pending.length}条未确认提醒',
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );
  }
  
  Widget _buildVoiceInput() {
    return Container(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          if (_recognizedText.isNotEmpty)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.blue[50],
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                _recognizedText,
                style: const TextStyle(fontSize: 18),
              ),
            ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            height: 72,
            child: GestureDetector(
              onLongPressStart: (_) => _startRecording(),
              onLongPressEnd: (_, __) => _stopRecording(),
              child: Container(
                decoration: BoxDecoration(
                  color: _isRecording ? Colors.red : Colors.blue,
                  borderRadius: BorderRadius.circular(36),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      _isRecording ? Icons.mic : Icons.mic_none,
                      color: Colors.white,
                      size: 32,
                    ),
                    const SizedBox(width: 12),
                    Text(
                      _isRecording ? '松开结束' : '按住说话',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
  
  Widget _buildTextInput() {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _textController,
              style: const TextStyle(fontSize: 18),
              decoration: InputDecoration(
                hintText: '或输入提醒内容...',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(24),
                ),
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              ),
              onSubmitted: (text) {
                if (text.isNotEmpty) {
                  _createReminder(text);
                }
              },
            ),
          ),
          const SizedBox(width: 8),
          IconButton(
            onPressed: () {
              if (_textController.text.isNotEmpty) {
                _createReminder(_textController.text);
              }
            },
            icon: const Icon(Icons.send, size: 28),
            style: IconButton.styleFrom(
              backgroundColor: Colors.blue,
              foregroundColor: Colors.white,
            ),
          ),
        ],
      ),
    );
  }
  
  Future<void> _confirmReminder(ReminderModel reminder) async {
    final appState = context.read<AppState>();
    await _api.confirmReminder(reminder.reminderId, appState.userId!);
    _loadReminders();
  }
  
  Future<void> _snoozeReminder(ReminderModel reminder) async {
    if (!reminder.canSnooze) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('已达到最大延迟次数，请确认提醒')),
      );
      return;
    }
    final appState = context.read<AppState>();
    await _api.snoozeReminder(reminder.reminderId, appState.userId!);
    _loadReminders();
  }
  
  @override
  void dispose() {
    _voiceService.dispose();
    _textController.dispose();
    super.dispose();
  }
}
