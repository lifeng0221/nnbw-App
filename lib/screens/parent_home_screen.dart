import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';
import '../main.dart';
import '../models/app_models.dart';
import '../services/local_storage_service.dart';
import '../services/voice_service.dart';
import '../widgets/reminder_card.dart';
import '../widgets/simple_time_picker.dart';
import 'bind_screen.dart';

/// 暖炉风配色
class AppColors {
  static const Color background = Color(0xFFFFF8F0);     // 暖奶油白
  static const Color primary = Color(0xFFFF8C42);        // 暖橙
  static const Color confirm = Color(0xFF4CAF50);        // 确认绿
  static const Color snooze = Color(0xFFFFB74D);         // 稍后橙
  static const Color textDark = Color(0xFF3E2723);        // 深棕
  static const Color textSecondary = Color(0xFF8D6E63);   // 灰棕
  static const Color cardBg = Color(0xFFFFFFFF);          // 卡片白
  static const Color urgent = Color(0xFFE53935);          // 紧急红
  static const Color important = Color(0xFFFF9800);       // 重要橙
}

/// 老人端首页 — 暖炉风
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
      duration: const Duration(milliseconds: 1200),
      vsync: this,
    );
    _pulseAnimation = Tween<double>(begin: 1.0, end: 1.4).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
  }
  
  Future<void> _loadReminders() async {
    final appState = context.read<AppState>();
    if (appState.userId == null) {
      setState(() => _isLoading = false);
      return;
    }
    
    final bindings = await _storage.getBindings(appState.userId!);
    
    if (bindings.isEmpty) {
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
    
    if (allReminders.isEmpty) {
      allReminders = await _storage.getReminders('test_binding');
    }
    
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
      _recognizedText = '';
    });
    
    _showConfirmDialog();
  }
  
  void _showConfirmDialog() {
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
                color: AppColors.primary.withOpacity(0.1),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(Icons.edit_note, color: AppColors.primary),
            ),
            const SizedBox(width: 12),
            const Text('添加提醒', style: TextStyle(fontSize: 24, color: AppColors.textDark)),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: _textController,
              style: const TextStyle(fontSize: 22, color: AppColors.textDark),
              maxLines: 3,
              autofocus: true,
              decoration: InputDecoration(
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: AppColors.primary),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: AppColors.primary, width: 2),
                ),
                hintText: '输入提醒内容...',
                hintStyle: const TextStyle(color: AppColors.textSecondary),
                contentPadding: const EdgeInsets.all(16),
              ),
            ),
            const SizedBox(height: 16),
            // 时间选择
            InkWell(
              onTap: () async {
                final time = await showModalBottomSheet<TimeOfDay>(
                  context: context,
                  shape: const RoundedRectangleBorder(
                    borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
                  ),
                  builder: (ctx) => SimpleTimePicker(
                    initialTime: TimeOfDay.fromDateTime(DateTime.now().add(const Duration(minutes: 5))),
                    onTimeSelected: (t) => Navigator.pop(ctx, t),
                  ),
                );
                if (time != null) {
                  // 存到临时变量，创建时用
                  _tempTime = time;
                }
              },
              child: Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  border: Border.all(color: AppColors.primary.withOpacity(0.3)),
                  borderRadius: BorderRadius.circular(12),
                  color: AppColors.primary.withOpacity(0.05),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.access_time, color: AppColors.primary, size: 24),
                    const SizedBox(width: 12),
                    Text(
                      _tempTime != null
                          ? '${_tempTime!.hour.toString().padLeft(2, '0')}:${_tempTime!.minute.toString().padLeft(2, '0')} 提醒'
                          : '5分钟后提醒',
                      style: const TextStyle(fontSize: 18, color: AppColors.textDark),
                    ),
                    const Spacer(),
                    Text('点击修改', style: TextStyle(color: AppColors.textSecondary, fontSize: 14)),
                  ],
                ),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              setState(() {
                _recognizedText = '';
                _tempTime = null;
              });
              _textController.clear();
            },
            child: const Text('取消', style: TextStyle(fontSize: 18, color: AppColors.textSecondary)),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              _createReminder(_textController.text);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            ),
            child: const Text('确认添加', style: TextStyle(fontSize: 18)),
          ),
        ],
      ),
    );
  }
  
  TimeOfDay? _tempTime;
  
  Future<void> _createReminder(String text) async {
    if (text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('提醒内容不能为空')),
      );
      return;
    }
    
    final appState = context.read<AppState>();
    if (appState.userId == null) return;
    
    List<BindingModel> bindings = await _storage.getBindings(appState.userId!);
    if (bindings.isEmpty) {
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
    
    // 计算触发时间
    DateTime triggerTime;
    if (_tempTime != null) {
      final now = DateTime.now();
      triggerTime = DateTime(now.year, now.month, now.day, _tempTime!.hour, _tempTime!.minute);
      if (triggerTime.isBefore(now)) {
        triggerTime = triggerTime.add(const Duration(days: 1));
      }
    } else {
      triggerTime = DateTime.now().add(const Duration(minutes: 5));
    }
    
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
      _tempTime = null;
      _textController.clear();
    });
    
    await _loadReminders();
    
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('提醒已添加：$text'),
        backgroundColor: AppColors.confirm,
      ),
    );
  }
  
  Future<void> _confirmReminder(ReminderModel reminder) async {
    await _storage.confirmReminder(reminder.reminderId);
    await _loadReminders();
    
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('已确认完成'), backgroundColor: AppColors.confirm),
    );
  }
  
  Future<void> _snoozeReminder(ReminderModel reminder) async {
    await _storage.snoozeReminder(reminder.reminderId);
    await _loadReminders();
    
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('已延后提醒'), backgroundColor: AppColors.snooze),
    );
  }
  
  Future<void> _deleteReminder(ReminderModel reminder) async {
    await _storage.deleteReminder(reminder.reminderId);
    await _loadReminders();
  }
  
  Widget _buildBody() {
    if (_isLoading) {
      return const Center(
        child: CircularProgressIndicator(color: AppColors.primary),
      );
    }
    
    if (_todayReminders.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.notifications_none, size: 80, color: AppColors.primary.withOpacity(0.3)),
            const SizedBox(height: 16),
            const Text(
              '今天还没有提醒',
              style: TextStyle(fontSize: 22, color: AppColors.textSecondary),
            ),
            const SizedBox(height: 8),
            const Text(
              '按住下方按钮说话，或输入文字',
              style: TextStyle(fontSize: 16, color: AppColors.textSecondary),
            ),
          ],
        ),
      );
    }
    
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      itemCount: _todayReminders.length,
      itemBuilder: (context, i) {
        final r = _todayReminders[i];
        return Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: _buildReminderCard(r),
        );
      },
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
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          border: Border(left: BorderSide(color: leftBorder, width: 4)),
        ),
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 时间 + 状态
            Row(
              children: [
                Text(
                  r.formattedTime,
                  style: const TextStyle(
                    fontSize: 36,
                    fontWeight: FontWeight.bold,
                    color: AppColors.textDark,
                  ),
                ),
                const SizedBox(width: 12),
                _buildStatusBadge(r),
                if (r.isImportant) ...[
                  const SizedBox(width: 6),
                  Icon(
                    r.isUrgent ? Icons.priority_high : Icons.flag,
                    color: r.isUrgent ? AppColors.urgent : AppColors.important,
                    size: 20,
                  ),
                ],
              ],
            ),
            const SizedBox(height: 8),
            // 内容
            Text(
              r.content,
              style: const TextStyle(fontSize: 20, color: AppColors.textDark),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 4),
            // 来源标签
            Row(
              children: [
                _buildTag(r.createdBy == 'parent_test' ? '我自己设的' : '子女设的', AppColors.primary),
                const SizedBox(width: 6),
                _buildTag(r.category, AppColors.textSecondary),
              ],
            ),
            // 操作按钮
            if (isActive)
              Padding(
                padding: const EdgeInsets.only(top: 14),
                child: Row(
                  children: [
                    Expanded(
                      child: ElevatedButton(
                        onPressed: () => _confirmReminder(r),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.confirm,
                          foregroundColor: Colors.white,
                          minimumSize: const Size(0, 52),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(26)),
                        ),
                        child: const Text('知道了', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                      ),
                    ),
                    const SizedBox(width: 12),
                    if (r.canSnooze)
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () => _snoozeReminder(r),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: AppColors.snooze,
                            side: const BorderSide(color: AppColors.snooze),
                            minimumSize: const Size(0, 52),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(26)),
                          ),
                          child: const Text('等一下', style: TextStyle(fontSize: 20)),
                        ),
                      ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
  
  Widget _buildStatusBadge(ReminderModel r) {
    Color bg;
    Color fg;
    String label;
    switch (r.status) {
      case 'confirmed':
        bg = AppColors.confirm.withOpacity(0.1);
        fg = AppColors.confirm;
        label = '已完成';
        break;
      case 'triggered':
      case 'snoozed':
        bg = AppColors.snooze.withOpacity(0.1);
        fg = AppColors.snooze;
        label = r.status == 'snoozed' ? '稍后' : '已响铃';
        break;
      default:
        bg = AppColors.primary.withOpacity(0.1);
        fg = AppColors.primary;
        label = '待响';
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(6)),
      child: Text(label, style: TextStyle(fontSize: 14, color: fg, fontWeight: FontWeight.bold)),
    );
  }
  
  Widget _buildTag(String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withOpacity(0.08),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(text, style: TextStyle(fontSize: 12, color: color)),
    );
  }
  
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('念念不忘', style: TextStyle(color: AppColors.textDark, fontWeight: FontWeight.bold)),
        centerTitle: true,
        elevation: 0,
        backgroundColor: AppColors.background,
        iconTheme: const IconThemeData(color: AppColors.textDark),
        actions: [
          IconButton(
            icon: const Icon(Icons.link, color: AppColors.primary),
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
          // 今日提醒标题栏
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            decoration: BoxDecoration(
              color: AppColors.primary.withOpacity(0.08),
              border: Border(bottom: BorderSide(color: AppColors.primary.withOpacity(0.15))),
            ),
            child: Row(
              children: [
                const Icon(Icons.wb_sunny, color: AppColors.primary, size: 22),
                const SizedBox(width: 8),
                const Text(
                  '今日提醒',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppColors.textDark),
                ),
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: AppColors.primary,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    '${_todayReminders.length}条',
                    style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ),
          ),
          
          Expanded(child: _buildBody()),
          
          // 语音和输入区域
          Container(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
            decoration: BoxDecoration(
              color: Colors.white,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.06),
                  blurRadius: 12,
                  offset: const Offset(0, -3),
                ),
              ],
            ),
            child: Column(
              children: [
                // 语音按钮 — 核心交互
                _buildVoiceButton(),
                const SizedBox(height: 12),
                // 文字输入
                Row(
                  children: [
                    Expanded(
                      child: Container(
                        decoration: BoxDecoration(
                          color: AppColors.background,
                          borderRadius: BorderRadius.circular(28),
                          border: Border.all(color: AppColors.primary.withOpacity(0.2)),
                        ),
                        child: TextField(
                          controller: _textController,
                          style: const TextStyle(fontSize: 18, color: AppColors.textDark),
                          decoration: InputDecoration(
                            hintText: '或输入提醒内容...',
                            hintStyle: const TextStyle(color: AppColors.textSecondary),
                            border: InputBorder.none,
                            contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                          ),
                          onSubmitted: (t) {
                            if (t.isNotEmpty) _createReminder(t);
                          },
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Container(
                      decoration: BoxDecoration(
                        color: AppColors.primary,
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: AppColors.primary.withOpacity(0.3),
                            blurRadius: 8,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: IconButton(
                        onPressed: () {
                          if (_textController.text.isNotEmpty) {
                            _createReminder(_textController.text);
                          }
                        },
                        icon: const Icon(Icons.send, color: Colors.white, size: 22),
                        iconSize: 22,
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
          return SizedBox(
            width: double.infinity,
            height: 80,
            child: Stack(
              alignment: Alignment.center,
              children: [
                // 脉冲圈
                if (_isRecording)
                  Transform.scale(
                    scale: _pulseAnimation.value,
                    child: Container(
                      width: 88,
                      height: 88,
                      decoration: BoxDecoration(
                        color: AppColors.urgent.withOpacity(0.15),
                        shape: BoxShape.circle,
                      ),
                    ),
                  ),
                // 主按钮
                Container(
                  width: 80,
                  height: 80,
                  decoration: BoxDecoration(
                    color: _isRecording ? AppColors.urgent : AppColors.primary,
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: (_isRecording ? AppColors.urgent : AppColors.primary).withOpacity(0.35),
                        blurRadius: 16,
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
                            fontSize: 13,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      if (!_isRecording)
                        const Text(
                          '说话',
                          style: TextStyle(color: Colors.white, fontSize: 11),
                        ),
                    ],
                  ),
                ),
                // 提示文字
                if (!_isRecording)
                  Positioned(
                    bottom: 0,
                    child: Text(
                      '按住说话',
                      style: TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 13,
                      ),
                    ),
                  ),
              ],
            ),
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
