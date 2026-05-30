import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';
import 'package:intl/intl.dart';
import '../main.dart';
import '../models/app_models.dart';
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
  final TextEditingController _textController = TextEditingController();
  final Uuid _uuid = const Uuid();

  List<ReminderModel> _reminders = [];
  bool _isLoading = true;
  String _selectedCategory = '生活';
  String _selectedPriority = 'normal';
  TimeOfDay _selectedTime = TimeOfDay.fromDateTime(DateTime.now().add(const Duration(minutes: 5)));
  DateTime _selectedDate = DateTime.now();

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
                    labelText: '提醒内容', hintText: '例如：记得吃药',
                    labelStyle: const TextStyle(color: Color(0xFFFF8C42)),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                    focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Color(0xFFFF8C42), width: 2)),
                    contentPadding: const EdgeInsets.all(16),
                  ),
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
    if (confirmed == true) { await _storage.deleteReminder(reminder.reminderId); await _loadData(); }
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
