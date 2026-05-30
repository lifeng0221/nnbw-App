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
  final TextEditingController _textController = TextEditingController();
  final AudioPlayer _audioPlayer = AudioPlayer();
  final Uuid _uuid = const Uuid();

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
  int _recordingSeconds = 0;

  @override
  void initState() {
    super.initState();
    _initAnimations();
    _initVoice();
    _loadReminders();
    _setupAlarmCallback();
    // Bug 7 修复: 前台每10秒刷新一次提醒列表
    _refreshTimer = Timer.periodic(const Duration(seconds: 10), (_) => _loadReminders());
  }

  void _initAnimations() {
    _pulseController = AnimationController(duration: const Duration(milliseconds: 1200), vsync: this);
    _pulseAnimation = Tween<double>(begin: 1.0, end: 1.4).animate(CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut));
  }

  Future<void> _initVoice() async => await _voiceService.init();

  void _setupAlarmCallback() {
    _alarmService.onReminderTriggered = (reminder) {
      // 铃声响后刷新列表，把状态更新
      _loadReminders();
    };
  }

  Future<void> _loadReminders() async {
    final appState = context.read<AppState>();
    if (appState.userId == null) {
      setState(() => _isLoading = false);
      return;
    }

    final bindings = await _storage.getBindings(appState.userId!);
    if (bindings.isEmpty) {
      final testBinding = BindingModel(bindingId: 'test_binding', parentId: appState.userId!, childId: 'child_test', status: 'active', createdAt: DateTime.now());
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

    // Bug 7 修复: 自动把过期的pending改为triggered
    for (final r in todayReminders) {
      if (r.status == 'pending' && r.triggerTime.isBefore(now)) {
        await _storage.updateReminderStatus(r.reminderId, 'triggered');
      }
    }
    // 重新加载更新后的状态
    allReminders = [];
    for (final binding in bindings) {
      final reminders = await _storage.getReminders(binding.bindingId);
      allReminders.addAll(reminders);
    }
    if (allReminders.isEmpty) {
      allReminders = await _storage.getReminders('test_binding');
    }
    final updated = allReminders.where((r) =>
      r.triggerTime.year == now.year &&
      r.triggerTime.month == now.month &&
      r.triggerTime.day == now.day
    ).toList();
    updated.sort((a, b) => a.triggerTime.compareTo(b.triggerTime));

    setState(() { _todayReminders = updated; _isLoading = false; });

    // 启动/更新闹钟轮询（传入所有提醒，不只是今天的）
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

  /// Bug 2 & 3 修复: 确认弹窗 — selectedTime正确传递
  void _showConfirmDialog({String? prefilledText}) {
    final displayText = prefilledText ?? _recognizedText;
    _textController.text = displayText;
    // 默认5分钟后
    final defaultTime = TimeOfDay.fromDateTime(DateTime.now().add(const Duration(minutes: 5)));

    showDialog(
      context: context,
      barrierDismissible: true, // 允许点击外部关闭
      builder: (dialogContext) {
        TimeOfDay? selectedTime;

        return StatefulBuilder(
          builder: (context, setDialogState) {
            // Bug 2 修复: 大号时间优先显示selectedTime
            final displayTime = selectedTime ?? defaultTime;
            // Bug 3 修复: 确认按钮使用setState后的最新selectedTime
            void handleConfirm() {
              Navigator.pop(dialogContext);
              _createReminder(_textController.text, selectedTime);
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
                      decoration: InputDecoration(
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: AppColors.primary)),
                        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: AppColors.primary, width: 2)),
                        hintText: '输入提醒内容...',
                        hintStyle: const TextStyle(color: AppColors.textSecondary),
                        contentPadding: const EdgeInsets.all(16),
                      ),
                    ),

                    if (displayText.isNotEmpty && prefilledText == null && _recognizedText.isNotEmpty)
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
                              if (time != null) setDialogState(() => selectedTime = time);
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
                                  // Bug 2 修复: 使用displayTime而不是defaultTime
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
                          // Bug 2 修复: 底部提示根据selectedTime更新
                          Center(child: Text(
                            selectedTime != null ? '已设定提醒时间' : '默认5分钟后提醒',
                            style: TextStyle(color: AppColors.textSecondary, fontSize: 14),
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
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text('提醒已添加：${_formatTimeOfDay(TimeOfDay.fromDateTime(triggerTime))} $text'),
      backgroundColor: AppColors.confirm,
    ));
  }

  Future<void> _confirmReminder(ReminderModel r) async {
    await _storage.confirmReminder(r.reminderId);
    await _alarmService.stopAlarmSound();
    await _loadReminders();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('已确认完成'), backgroundColor: AppColors.confirm));
  }

  Future<void> _snoozeReminder(ReminderModel r) async {
    await _storage.snoozeReminder(r.reminderId);
    await _alarmService.stopAlarmSound();
    await _loadReminders();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('已延后5分钟提醒'), backgroundColor: AppColors.snooze));
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
            onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const BindScreen()))),
        ],
      ),
      // 侧滑菜单
      drawer: _buildDrawer(),
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
            onTap: () { Navigator.pop(context); Navigator.push(context, MaterialPageRoute(builder: (_) => const BindScreen())); },
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
    _refreshTimer?.cancel();  // Bug 7 修复: 清理刷新定时器
    _alarmService.stopChecking();
    _voiceService.dispose();
    _textController.dispose();
    _audioPlayer.dispose();
    super.dispose();
  }
}
