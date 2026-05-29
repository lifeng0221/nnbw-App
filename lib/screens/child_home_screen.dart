import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../main.dart';
import '../models/app_models.dart';
import '../services/api_service.dart';
import '../services/voice_service.dart';
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
  bool _isLoading = true;
  String _selectedCategory = '生活';
  String _selectedPriority = 'normal';

  final List<Map<String, String>> _categories = [
    {'value': '吃药', 'icon': '💊', 'label': '吃药'},
    {'value': '运动', 'icon': '🏃', 'label': '运动'},
    {'value': '生活', 'icon': '🏠', 'label': '生活'},
    {'value': '医疗', 'icon': '🏥', 'label': '医疗'},
    {'value': '其他', 'icon': '📌', 'label': '其他'},
  ];

  @override
  void initState() { super.initState(); _loadData(); }

  Future<void> _loadData() async {
    final appState = context.read<AppState>();
    if (appState.userId == null) return;
    final result = await _api.getReminders(appState.userId!);
    if (result['reminders'] != null) {
      final list = (result['reminders'] as List).map((r) => ReminderModel.fromJson(r)).toList();
      list.sort((a, b) => a.triggerTime.compareTo(b.triggerTime));
      setState(() { _reminders = list; _isLoading = false; });
    } else { setState(() => _isLoading = false); }
  }

  void _showCreateReminderSheet() {
    showModalBottomSheet(context: context, isScrollControlled: true, builder: (context) => StatefulBuilder(
      builder: (context, setModalState) => Container(
        padding: EdgeInsets.only(left: 16, right: 16, top: 16, bottom: MediaQuery.of(context).viewInsets.bottom + 16),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            const Text('为爸妈设提醒', style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
            IconButton(onPressed: () => Navigator.pop(context), icon: const Icon(Icons.close)),
          ]),
          const SizedBox(height: 12),
          TextField(controller: _textController, style: const TextStyle(fontSize: 18), maxLines: 2,
            decoration: const InputDecoration(border: OutlineInputBorder(), hintText: '提醒内容')),
          const SizedBox(height: 12),
          const Text('分类', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          Wrap(spacing: 8, children: _categories.map((cat) => ChoiceChip(
            label: Text('${cat['icon']} ${cat['label']}', style: const TextStyle(fontSize: 16)),
            selected: _selectedCategory == cat['value'],
            onSelected: (_) => setModalState(() => _selectedCategory = cat['value']!),
          )).toList()),
          const SizedBox(height: 16),
          SizedBox(width: double.infinity, height: 52, child: ElevatedButton(
            onPressed: () { Navigator.pop(context); _createReminder(_textController.text); },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.blue, foregroundColor: Colors.white),
            child: const Text('确认添加', style: TextStyle(fontSize: 20)),
          )),
        ]),
      ),
    ));
  }

  Future<void> _createReminder(String text) async {
    _textController.clear();
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('提醒已添加：$text')));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('念念不忘'), actions: [
        IconButton(icon: const Icon(Icons.link), onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const BindScreen()))),
      ]),
      body: _isLoading ? const Center(child: CircularProgressIndicator()) : SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          _buildParentStatusCard(),
          const SizedBox(height: 20),
          const Text('提醒列表', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
          const SizedBox(height: 12),
          if (_reminders.isEmpty) const Center(child: Padding(padding: EdgeInsets.all(32), child: Text('还没有提醒，点击下方按钮添加', style: TextStyle(color: Colors.grey, fontSize: 16))))
          else ..._reminders.map((r) => Padding(padding: const EdgeInsets.only(bottom: 8), child: ReminderCard(reminder: r, isParent: false))),
        ]),
      ),
      floatingActionButton: FloatingActionButton.extended(onPressed: _showCreateReminderSheet, icon: const Icon(Icons.add), label: const Text('设提醒')),
    );
  }

  Widget _buildParentStatusCard() {
    return Card(elevation: 2, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(padding: const EdgeInsets.all(16), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [const Icon(Icons.family_restroom, size: 28), const SizedBox(width: 8), const Text('看看爸妈', style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold))]),
        const SizedBox(height: 16),
        Row(mainAxisAlignment: MainAxisAlignment.spaceAround, children: [
          _buildStatItem('今日提醒', _reminders.length.toString(), Colors.blue),
          _buildStatItem('已完成', _reminders.where((r) => r.status == 'confirmed').length.toString(), Colors.green),
          _buildStatItem('待确认', _reminders.where((r) => r.status == 'triggered' || r.status == 'snoozed').length.toString(), Colors.orange),
        ]),
      ])),
    );
  }

  Widget _buildStatItem(String label, String value, Color color) {
    return Column(children: [
      Text(value, style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: color)),
      const SizedBox(height: 4), Text(label, style: const TextStyle(fontSize: 14, color: Colors.grey)),
    ]);
  }
}
