import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../main.dart';
import '../models/app_models.dart';
import '../services/api_service.dart';
import '../services/voice_service.dart';
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

  @override
  void initState() { super.initState(); _loadReminders(); }

  Future<void> _loadReminders() async {
    final appState = context.read<AppState>();
    if (appState.userId == null) return;
    final result = await _api.getReminders(appState.userId!);
    if (result['reminders'] != null) {
      final list = (result['reminders'] as List).map((r) => ReminderModel.fromJson(r)).toList();
      final now = DateTime.now();
      final today = list.where((r) => r.triggerTime.year == now.year && r.triggerTime.month == now.month && r.triggerTime.day == now.day).toList();
      today.sort((a, b) => a.triggerTime.compareTo(b.triggerTime));
      setState(() { _todayReminders = today; _isLoading = false; });
    } else { setState(() => _isLoading = false); }
  }

  Future<void> _startRecording() async {
    final started = await _voiceService.startRecording();
    if (started) setState(() => _isRecording = true);
  }

  Future<void> _stopRecording() async {
    await _voiceService.stopRecording();
    setState(() { _isRecording = false; _recognizedText = '识别结果（待接入讯飞SDK）'; });
    _showConfirmDialog();
  }

  void _showConfirmDialog() {
    _textController.text = _recognizedText;
    showDialog(context: context, barrierDismissible: false, builder: (context) => AlertDialog(
      title: const Text('确认提醒', style: TextStyle(fontSize: 22)),
      content: TextField(controller: _textController, style: const TextStyle(fontSize: 20), maxLines: 3,
        decoration: const InputDecoration(border: OutlineInputBorder(), hintText: '修改提醒内容')),
      actions: [
        TextButton(onPressed: () { Navigator.pop(context); setState(() => _recognizedText = ''); }, child: const Text('取消')),
        ElevatedButton(onPressed: () { Navigator.pop(context); _createReminder(_textController.text); },
          child: const Text('确认添加', style: TextStyle(fontSize: 18))),
      ],
    ));
  }

  Future<void> _createReminder(String text) async {
    setState(() => _recognizedText = '');
    _textController.clear();
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('提醒已添加：$text')));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('念念不忘'), actions: [
        IconButton(icon: const Icon(Icons.link), onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const BindScreen()))),
      ]),
      body: Column(children: [
        Expanded(child: _isLoading ? const Center(child: CircularProgressIndicator())
          : _todayReminders.isEmpty ? Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
              Icon(Icons.notifications_none, size: 64, color: Colors.grey[400]),
              const SizedBox(height: 16),
              const Text('今天还没有提醒', style: TextStyle(fontSize: 20, color: Colors.grey)),
            ]) : ListView.builder(padding: const EdgeInsets.all(12), itemCount: _todayReminders.length,
              itemBuilder: (context, i) => ReminderCard(reminder: _todayReminders[i], isParent: true))),
        Container(padding: const EdgeInsets.all(16), child: Column(children: [
          if (_recognizedText.isNotEmpty) Container(width: double.infinity, padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: Colors.blue[50], borderRadius: BorderRadius.circular(12)),
            child: Text(_recognizedText, style: const TextStyle(fontSize: 18))),
          const SizedBox(height: 12),
          SizedBox(width: double.infinity, height: 72, child: GestureDetector(
            onLongPressStart: (_) => _startRecording(),
            onLongPressEnd: (_) => _stopRecording(),
            child: Container(decoration: BoxDecoration(color: _isRecording ? Colors.red : Colors.blue, borderRadius: BorderRadius.circular(36)),
              child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                Icon(_isRecording ? Icons.mic : Icons.mic_none, color: Colors.white, size: 32),
                const SizedBox(width: 12),
                Text(_isRecording ? '松开结束' : '按住说话', style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold)),
              ])),
          )),
        ])),
        Container(padding: const EdgeInsets.fromLTRB(16, 0, 16, 16), child: Row(children: [
          Expanded(child: TextField(controller: _textController, style: const TextStyle(fontSize: 18),
            decoration: InputDecoration(hintText: '或输入提醒内容...', border: OutlineInputBorder(borderRadius: BorderRadius.circular(24)),
              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12)),
            onSubmitted: (t) { if (t.isNotEmpty) _createReminder(t); })),
          const SizedBox(width: 8),
          IconButton(onPressed: () { if (_textController.text.isNotEmpty) _createReminder(_textController.text); },
            icon: const Icon(Icons.send, size: 28), style: IconButton.styleFrom(backgroundColor: Colors.blue, foregroundColor: Colors.white)),
        ])),
      ]),
    );
  }

  @override void dispose() { _voiceService.dispose(); _textController.dispose(); super.dispose(); }
}
