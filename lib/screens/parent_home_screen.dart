import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';
import 'package:audioplayers/audioplayers.dart';
import '../main.dart';
import '../models/app_models.dart';
import '../services/local_storage_service.dart';
import '../services/voice_service.dart';
import '../widgets/simple_time_picker.dart';
import 'bind_screen.dart';

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

/// 老人端首页 — 暖炉风 + 真实语音 + 删除 + 时间设定优化
class ParentHomeScreen extends StatefulWidget {
  const ParentHomeScreen({super.key});
  @override
  State<ParentHomeScreen> createState() => _ParentHomeScreenState();
}

class _ParentHomeScreenState extends State<ParentHomeScreen> with TickerProviderStateMixin {
  final VoiceService _voiceService = VoiceService();
  final LocalStorageService _storage = LocalStorageService();
  final TextEditingController _textController = TextEditingController();
  final AudioPlayer _audioPlayer = AudioPlayer();
  final Uuid _uuid = const Uuid();

  List<ReminderModel> _todayReminders = [];
  bool _isLoading = true;
  bool _isRecording = false;
  String _recognizedText = '';
  String? _recognizedVoiceUrl;
  String _partialText = '';

  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;
  Timer? _recordingTimer;
  int _recordingSeconds = 0;

  @override
  void initState() {
    super.initState();
    _initAnimations();
    _initVoice();
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

  Future<void> _initVoice() async {
    await _voiceService.init();
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
    final todayReminders = allReminders.where((r) =>
      r.triggerTime.year == now.year &&
      r.triggerTime.month == now.month &&
      r.triggerTime.day == now.day
    ).toList();
    todayReminders.sort((a, b) => a.triggerTime.compareTo(b.triggerTime));

    setState(() { _todayReminders = todayReminders; _isLoading = false; });
  }

  Future<void> _startRecording() async {
    final started = await _voiceService.startListening(
      onPartialResult: (text) {
        setState(() => _partialText = text);
      },
      onResult: (text) {
        setState(() {
          _recognizedText = text;
          _partialText = '';
        });
      },
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

    setState(() {
      _isRecording = false;
      if (text.isNotEmpty) {
        _recognizedText = text;
      }
      _partialText = '';
    });

    _showConfirmDialog();
  }

  /// 统一的确认弹窗 — 语音和文字输入都走这里
  void _showConfirmDialog({String? prefilledText}) {
    final displayText = prefilledText ?? _recognizedText;
    _textController.text = displayText;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        TimeOfDay? tempTime;

        return StatefulBuilder(
          builder: (context, setDialogState) => AlertDialog(
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
                const Text('添加提醒', style: TextStyle(fontSize: 26, color: AppColors.textDark, fontWeight: FontWeight.bold)),
              ],
            ),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 提醒内容输入
                  TextField(
                    controller: _textController,
                    style: const TextStyle(fontSize: 24, color: AppColors.textDark),
                    maxLines: 3,
                    autofocus: true,
                    decoration: InputDecoration(
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: AppColors.primary)),
                      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: AppColors.primary, width: 2)),
                      hintText: '输入提醒内容...',
                      hintStyle: const TextStyle(color: AppColors.textSecondary),
                      contentPadding: const EdgeInsets.all(16),
                    ),
                  ),

                  // 语音来源标记
                  if (displayText.isNotEmpty && prefilledText == null && _recognizedText.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Row(children: [
                        Icon(Icons.mic, color: AppColors.primary, size: 16),
                        const SizedBox(width: 4),
                        Text('语音识别内容，可修改', style: TextStyle(color: AppColors.primary, fontSize: 13)),
                      ]),
                    ),

                  const SizedBox(height: 20),

                  // === 时间设定 — 超级醒目 ===
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: AppColors.primary.withOpacity(0.06),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: AppColors.primary, width: 2),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(children: [
                          const Icon(Icons.alarm, color: AppColors.primary, size: 26),
                          const SizedBox(width: 8),
                          const Text('提醒时间', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: AppColors.textDark)),
                        ]),
                        const SizedBox(height: 14),
                        InkWell(
                          onTap: () async {
                            final time = await showModalBottomSheet<TimeOfDay>(
                              context: context,
                              shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
                              builder: (ctx) => SimpleTimePicker(
                                initialTime: tempTime ?? TimeOfDay.fromDateTime(DateTime.now().add(const Duration(minutes: 5))),
                                onTimeSelected: (t) => Navigator.pop(ctx, t),
                              ),
                            );
                            if (time != null) {
                              setDialogState(() => tempTime = time);
                            }
                          },
                          borderRadius: BorderRadius.circular(14),
                          child: Container(
                            width: double.infinity,
                            padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 20),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(14),
                              boxShadow: [BoxShadow(color: AppColors.primary.withOpacity(0.1), blurRadius: 8, offset: const Offset(0, 2))],
                            ),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Text(
                                  tempTime != null
                                    ? '${tempTime!.hour.toString().padLeft(2, '0')}:${tempTime!.minute.toString().padLeft(2, '0')}'
                                    : '${TimeOfDay.fromDateTime(DateTime.now().add(const Duration(minutes: 5))).hour.toString().padLeft(2, '0')}:${TimeOfDay.fromDateTime(DateTime.now().add(const Duration(minutes: 5))).minute.toString().padLeft(2, '0')}',
                                  style: const TextStyle(fontSize: 48, fontWeight: FontWeight.bold, color: AppColors.primary),
                                ),
                                const SizedBox(width: 16),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                  decoration: BoxDecoration(
                                    color: AppColors.primary,
                                    borderRadius: BorderRadius.circular(20),
                                  ),
                                  child: const Text('点击修改', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 8),
                        Center(
                          child: Text(
                            tempTime != null ? '已选择提醒时间' : '默认5分钟后提醒',
                            style: TextStyle(color: AppColors.textSecondary, fontSize: 14),
                          ),
                        ),
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
                        Navigator.pop(context);
                        setState(() { _recognizedText = ''; _recognizedVoiceUrl = null; });
                        _textController.clear();
                      },
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppColors.textSecondary,
                        side: const BorderSide(color: AppColors.textSecondary),
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
                      ),
                      child: const Text('取消', style: TextStyle(fontSize: 20)),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    flex: 2,
                    child: ElevatedButton(
                      onPressed: () {
                        Navigator.pop(context);
                        _createReminder(_textController.text, tempTime);
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
                        elevation: 3,
                      ),
                      child: const Text('确认添加', style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
                    ),
                  ),
                ]),
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _playVoice(String path) async {
    if (await File(path).exists()) {
      await _audioPlayer.play(DeviceFileSource(path));
    }
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

    DateTime triggerTime;
    if (time != null) {
      final now = DateTime.now();
      triggerTime = DateTime(now.year, now.month, now.day, time.hour, time.minute);
      if (triggerTime.isBefore(now)) triggerTime = triggerTime.add(const Duration(days: 1));
    } else {
      triggerTime = DateTime.now().add(const Duration(minutes: 5));
    }

    final reminder = ReminderModel(
      reminderId: _uuid.v4(),
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

    await _storage.saveReminder(reminder);

    setState(() { _recognizedText = ''; _recognizedVoiceUrl = null; _textController.clear(); });
    await _loadReminders();

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('提醒已添加：$text'), backgroundColor: AppColors.confirm));
  }

  Future<void> _confirmReminder(ReminderModel r) async {
    await _storage.confirmReminder(r.reminderId);
    await _loadReminders();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('已确认完成'), backgroundColor: AppColors.confirm));
  }

  Future<void> _snoozeReminder(ReminderModel r) async {
    await _storage.snoozeReminder(r.reminderId);
    await _loadReminders();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('已延后提醒'), backgroundColor: AppColors.snooze));
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
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消', style: TextStyle(fontSize: 18)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.urgent, foregroundColor: Colors.white),
            child: const Text('删除', style: TextStyle(fontSize: 18)),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await _storage.deleteReminder(r.reminderId);
      await _loadReminders();
    }
  }

  Widget _buildBody() {
    if (_isLoading) return const Center(child: CircularProgressIndicator(color: AppColors.primary));

    if (_todayReminders.isEmpty) {
      return Center(
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          Icon(Icons.notifications_none, size: 80, color: AppColors.primary.withOpacity(0.3)),
          const SizedBox(height: 16),
          const Text('今天还没有提醒', style: TextStyle(fontSize: 22, color: AppColors.textSecondary)),
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
            // 删除按钮
            Container(
              decoration: BoxDecoration(
                color: AppColors.urgent.withOpacity(0.08),
                borderRadius: BorderRadius.circular(8),
              ),
              child: IconButton(
                onPressed: () => _deleteReminder(r),
                icon: const Icon(Icons.delete_outline, size: 22, color: AppColors.urgent),
                padding: const EdgeInsets.all(6),
                constraints: const BoxConstraints(),
              ),
            ),
          ]),
          const SizedBox(height: 8),
          // 内容 + 语音播放
          Row(children: [
            Expanded(child: Text(r.content, style: const TextStyle(fontSize: 20, color: AppColors.textDark), maxLines: 2, overflow: TextOverflow.ellipsis)),
            if (r.voiceUrl != null && r.voiceUrl!.isNotEmpty)
              IconButton(
                onPressed: () => _playVoice(r.voiceUrl!),
                icon: const Icon(Icons.play_circle, size: 32, color: AppColors.primary),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
              ),
          ]),
          const SizedBox(height: 4),
          Row(children: [
            _buildTag(r.createdBy == 'parent_test' ? '我自己设的' : '子女设的', AppColors.primary),
            const SizedBox(width: 6),
            _buildTag(r.category, AppColors.textSecondary),
          ]),
          // 操作按钮（已响铃时）
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
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('念念不忘', style: TextStyle(color: AppColors.textDark, fontWeight: FontWeight.bold)),
        centerTitle: true, elevation: 0, backgroundColor: AppColors.background,
        iconTheme: const IconThemeData(color: AppColors.textDark),
        actions: [
          IconButton(icon: const Icon(Icons.link, color: AppColors.primary), tooltip: '绑定子女',
            onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const BindScreen()))),
        ],
      ),
      body: Column(children: [
        // 今日提醒统计条
        Container(
          width: double.infinity, padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          decoration: BoxDecoration(color: AppColors.primary.withOpacity(0.08), border: Border(bottom: BorderSide(color: AppColors.primary.withOpacity(0.15)))),
          child: Row(children: [
            const Icon(Icons.wb_sunny, color: AppColors.primary, size: 22),
            const SizedBox(width: 8),
            const Text('今日提醒', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppColors.textDark)),
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
            // 实时识别文字
            if (_partialText.isNotEmpty)
              Container(width: double.infinity, padding: const EdgeInsets.all(10), margin: const EdgeInsets.only(bottom: 8),
                decoration: BoxDecoration(color: AppColors.primary.withOpacity(0.05), borderRadius: BorderRadius.circular(10)),
                child: Row(children: [
                  const Icon(Icons.mic, color: AppColors.primary, size: 16),
                  const SizedBox(width: 6),
                  Expanded(child: Text(_partialText, style: const TextStyle(fontSize: 16, color: AppColors.primary, fontStyle: FontStyle.italic))),
                ])),
            // 语音按钮
            _buildVoiceButton(),
            const SizedBox(height: 12),
            // 文字输入 + 发送（文字输入也弹确认框设置时间）
            Row(children: [
              Expanded(
                child: Container(
                  decoration: BoxDecoration(color: AppColors.background, borderRadius: BorderRadius.circular(28), border: Border.all(color: AppColors.primary.withOpacity(0.2))),
                  child: TextField(controller: _textController, style: const TextStyle(fontSize: 18, color: AppColors.textDark),
                    decoration: InputDecoration(hintText: '输入提醒内容...', hintStyle: const TextStyle(color: AppColors.textSecondary), border: InputBorder.none, contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14)),
                    onSubmitted: (t) {
                      if (t.isNotEmpty) {
                        _recognizedText = '';
                        _showConfirmDialog(prefilledText: t);
                      }
                    },
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Container(
                decoration: BoxDecoration(color: AppColors.primary, shape: BoxShape.circle,
                  boxShadow: [BoxShadow(color: AppColors.primary.withOpacity(0.3), blurRadius: 8, offset: const Offset(0, 2))]),
                child: IconButton(
                  onPressed: () {
                    if (_textController.text.isNotEmpty) {
                      _recognizedText = '';
                      _showConfirmDialog(prefilledText: _textController.text);
                    }
                  },
                  icon: const Icon(Icons.send, color: Colors.white, size: 22), iconSize: 22),
              ),
            ]),
          ]),
        ),
      ]),
    );
  }

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
    _voiceService.dispose();
    _textController.dispose();
    _audioPlayer.dispose();
    super.dispose();
  }
}
