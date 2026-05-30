import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';
import '../main.dart';
import '../models/app_models.dart';
import '../services/local_storage_service.dart';
import '../services/voice_service.dart';
import '../widgets/reminder_card.dart';
import 'bind_screen.dart';

/// 老人端首页
class ParentHomeScreen extends StatefulWidget {
  const ParentHomeScreen({super.key});
  
  @override
  State<ParentHomeScreen> createState() => _ParentHomeScreenState();
}

class _ParentHomeScreenState extends State<ParentHomeScreen> with TickerProviderStateMixin {
  final VoiceService _voiceService = VoiceService();
  final LocalStorageService _storage = LocalStorageService();
  final TextEditingController _textController = TextEditingController();
  final Uuid _uuid = const Uuid();
  
  List<ReminderModel> _todayReminders = [];
  bool _isLoading = true;
  bool _isRecording = false;
  String _recognizedText = '';
  
  // 录音动画
  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;
  Timer? _recordingTimer;
  int _recordingSeconds = 0;
  
  @override
  void initState() {
    super.initState();
    _initAnimations();
    _loadReminders();
  }
  
  void _initAnimations() {
    _pulseController = AnimationController(
      duration: const Duration(milliseconds: 1000),
      vsync: this,
    );
    
    _pulseAnimation = Tween<double>(begin: 1.0, end: 1.3).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
  }
  
  Future<void> _loadReminders() async {
    final appState = context.read<AppState>();
    if (appState.userId == null) {
      setState(() => _isLoading = false);
      return;
    }
    
    // 从本地获取绑定关系
    final bindings = await _storage.getBindings(appState.userId!);
    
    if (bindings.isEmpty) {
      // 没有绑定关系，创建默认的绑定用于测试
      final testBinding = BindingModel(
        bindingId: 'test_binding',
        parentId: appState.userId!,
        childId: 'child_test',
        status: 'active',
        createdAt: DateTime.now(),
      );
      await _storage.saveBinding(testBinding);
    }
    
    List<ReminderModel> allReminders = [];
    for (final binding in bindings) {
      final reminders = await _storage.getReminders(binding.bindingId);
      allReminders.addAll(reminders);
    }
    
    // 如果还是没有提醒，也从测试绑定中加载
    if (allReminders.isEmpty) {
      allReminders = await _storage.getReminders('test_binding');
    }
    
    // 过滤今日提醒
    final now = DateTime.now();
    final todayReminders = allReminders
        .where((r) =>
            r.triggerTime.year == now.year &&
            r.triggerTime.month == now.month &&
            r.triggerTime.day == now.day)
        .toList();
    
    todayReminders.sort((a, b) => a.triggerTime.compareTo(b.triggerTime));
    
    setState(() {
      _todayReminders = todayReminders;
      _isLoading = false;
    });
  }
  
  Future<void> _startRecording() async {
    final started = await _voiceService.startRecording();
    if (started) {
      setState(() {
        _isRecording = true;
        _recordingSeconds = 0;
      });
      _pulseController.repeat(reverse: true);
      _recordingTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
        setState(() => _recordingSeconds++);
        if (_recordingSeconds >= 60) {
          _stopRecording();
        }
      });
    }
  }
  
  Future<void> _stopRecording() async {
    _recordingTimer?.cancel();
    _pulseController.stop();
    _pulseController.reset();
    
    await _voiceService.stopRecording();
    
    setState(() {
      _isRecording = false;
      // Mock识别结果
      _recognizedText = '语音功能开发中，请在下方输入内容';
    });
    
    _showConfirmDialog();
  }
  
  void _showConfirmDialog() {
    _textController.text = _recognizedText.replaceAll('（语音功能开发中，请在下方输入内容）', '');
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.blue[50],
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(Icons.edit_note, color: Colors.blue),
            ),
            const SizedBox(width: 12),
            const Text('确认提醒', style: TextStyle(fontSize: 22)),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              _recognizedText.isEmpty ? '请输入提醒内容' : _recognizedText,
              style: const TextStyle(fontSize: 18),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _textController,
              style: const TextStyle(fontSize: 18),
              maxLines: 3,
              autofocus: true,
              decoration: InputDecoration(
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                hintText: '修改或补充提醒内容...',
                contentPadding: const EdgeInsets.all(12),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              '提醒时间：5分钟后',
              style: TextStyle(fontSize: 14, color: Colors.grey[600]),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              setState(() => _recognizedText = '');
              _textController.clear();
            },
            child: const Text('取消', style: TextStyle(fontSize: 16)),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              _createReminder(_textController.text);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.blue,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            ),
            child: const Text('确认添加', style: TextStyle(fontSize: 16)),
          ),
        ],
      ),
    );
  }
  
  Future<void> _createReminder(String text) async {
    if (text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('提醒内容不能为空')),
      );
      return;
    }
    
    final appState = context.read<AppState>();
    if (appState.userId == null) return;
    
    // 获取或创建绑定关系
    List<BindingModel> bindings = await _storage.getBindings(appState.userId!);
    if (bindings.isEmpty) {
      // 创建测试绑定
      final testBinding = BindingModel(
        bindingId: 'test_binding',
        parentId: appState.userId!,
        childId: 'child_test',
        status: 'active',
        createdAt: DateTime.now(),
      );
      await _storage.saveBinding(testBinding);
      bindings = [testBinding];
    }
    
    final binding = bindings.first;
    
    // 默认5分钟后提醒
    final triggerTime = DateTime.now().add(const Duration(minutes: 5));
    
    final reminder = ReminderModel(
      reminderId: _uuid.v4(),
      bindingId: binding.bindingId,
      createdBy: appState.userId!,
      content: text.trim(),
      triggerTime: triggerTime,
      category: '生活',
      priority: 'normal',
      status: 'pending',
      createdAt: DateTime.now(),
    );
    
    await _storage.saveReminder(reminder);
    
    setState(() {
      _recognizedText = '';
      _textController.clear();
    });
    
    // 刷新列表
    await _loadReminders();
    
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('提醒已添加：$text')),
    );
  }
  
  Future<void> _confirmReminder(ReminderModel reminder) async {
    await _storage.confirmReminder(reminder.reminderId);
    await _loadReminders();
    
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('已确认完成')),
    );
  }
  
  Future<void> _snoozeReminder(ReminderModel reminder) async {
    await _storage.snoozeReminder(reminder.reminderId);
    await _loadReminders();
    
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('已延后5分钟')),
    );
  }
  
  Widget _buildBody() {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    
    if (_todayReminders.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.notifications_none, size: 80, color: Colors.grey[300]),
            const SizedBox(height: 16),
            Text(
              '今天还没有提醒',
              style: TextStyle(fontSize: 20, color: Colors.grey[500]),
            ),
            const SizedBox(height: 8),
            Text(
              '按住下方按钮说出提醒，或输入文字',
              style: TextStyle(fontSize: 14, color: Colors.grey[400]),
            ),
          ],
        ),
      );
    }
    
    return ListView.builder(
      padding: const EdgeInsets.all(12),
      itemCount: _todayReminders.length,
      itemBuilder: (context, i) {
        return ReminderCard(
          reminder: _todayReminders[i],
          isParent: true,
          onConfirm: () => _confirmReminder(_todayReminders[i]),
          onSnooze: () => _snoozeReminder(_todayReminders[i]),
        );
      },
    );
  }
  
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('念念不忘'),
        centerTitle: true,
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.link),
            tooltip: '绑定子女',
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const BindScreen()),
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          // 今日提醒标题
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: Colors.blue[50],
              border: Border(bottom: BorderSide(color: Colors.blue[100]!)),
            ),
            child: Row(
              children: [
                const Icon(Icons.today, color: Colors.blue, size: 20),
                const SizedBox(width: 8),
                Text(
                  '今日提醒',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: Colors.blue[700],
                  ),
                ),
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.blue,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    '${_todayReminders.length}条',
                    style: const TextStyle(color: Colors.white, fontSize: 12),
                  ),
                ),
              ],
            ),
          ),
          
          Expanded(child: _buildBody()),
          
          // 语音和输入区域
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.05),
                  blurRadius: 10,
                  offset: const Offset(0, -2),
                ),
              ],
            ),
            child: Column(
              children: [
                // 识别结果显示
                if (_recognizedText.isNotEmpty)
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    margin: const EdgeInsets.only(bottom: 12),
                    decoration: BoxDecoration(
                      color: Colors.blue[50],
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.blue[200]!),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.record_voice_over, color: Colors.blue[600], size: 20),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            _recognizedText,
                            style: const TextStyle(fontSize: 16),
                          ),
                        ),
                      ],
                    ),
                  ),
                
                // 语音按钮
                _buildVoiceButton(),
                
                const SizedBox(height: 12),
                
                // 文字输入区域
                Row(
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
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 12,
                          ),
                        ),
                        onSubmitted: (t) {
                          if (t.isNotEmpty) _createReminder(t);
                        },
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      decoration: const BoxDecoration(
                        color: Colors.blue,
                        shape: BoxShape.circle,
                      ),
                      child: IconButton(
                        onPressed: () {
                          if (_textController.text.isNotEmpty) {
                            _createReminder(_textController.text);
                          }
                        },
                        icon: const Icon(Icons.send, color: Colors.white),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
  
  Widget _buildVoiceButton() {
    return GestureDetector(
      onLongPressStart: (_) => _startRecording(),
      onLongPressEnd: (_) => _stopRecording(),
      child: AnimatedBuilder(
        animation: _pulseAnimation,
        builder: (context, child) {
          return Stack(
            alignment: Alignment.center,
            children: [
              // 脉冲动画圈
              if (_isRecording)
                Transform.scale(
                  scale: _pulseAnimation.value,
                  child: Container(
                    width: 100,
                    height: 100,
                    decoration: BoxDecoration(
                      color: Colors.red.withOpacity(0.3 - (_pulseAnimation.value - 1.0) * 0.5),
                      shape: BoxShape.circle,
                    ),
                  ),
                ),
              // 主按钮
              Container(
                width: 80,
                height: 80,
                decoration: BoxDecoration(
                  color: _isRecording ? Colors.red : Colors.blue,
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: (_isRecording ? Colors.red : Colors.blue).withOpacity(0.3),
                      blurRadius: 12,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      _isRecording ? Icons.mic : Icons.mic_none,
                      color: Colors.white,
                      size: 32,
                    ),
                    if (_isRecording)
                      Text(
                        '${_recordingSeconds}s',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }
  
  @override
  void dispose() {
    _pulseController.dispose();
    _recordingTimer?.cancel();
    _voiceService.dispose();
    _textController.dispose();
    super.dispose();
  }
}
