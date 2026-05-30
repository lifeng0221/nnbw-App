import 'package:flutter/material.dart';

/// 暖炉风配色常量
class WarmColors {
  static const Color background = Color(0xFFFFF8F0);
  static const Color primary = Color(0xFFFF8C42);
  static const Color confirm = Color(0xFF4CAF50);
  static const Color snooze = Color(0xFFFFB74D);
  static const Color textDark = Color(0xFF3E2723);
  static const Color textSecondary = Color(0xFF8D6E63);
  static const CardBg = Color(0xFFFFFFFF);
  static const Color urgent = Color(0xFFE53935);
  static const Color important = Color(0xFFFF9800);
}

/// 老人友好的时间选择器 - 大数字 + 加减按钮 + 暖炉风
class SimpleTimePicker extends StatefulWidget {
  final TimeOfDay initialTime;
  final ValueChanged<TimeOfDay> onTimeSelected;

  const SimpleTimePicker({
    super.key,
    required this.initialTime,
    required this.onTimeSelected,
  });

  @override
  State<SimpleTimePicker> createState() => _SimpleTimePickerState();
}

class _SimpleTimePickerState extends State<SimpleTimePicker> {
  late int _hour;
  late int _minute;

  @override
  void initState() {
    super.initState();
    _hour = widget.initialTime.hour;
    _minute = widget.initialTime.minute;
  }

  void _incrementHour() => setState(() => _hour = (_hour + 1) % 24);
  void _decrementHour() => setState(() => _hour = (_hour - 1) % 24);
  void _incrementMinute() => setState(() => _minute = (_minute + 1) % 60);
  void _decrementMinute() => setState(() => _minute = (_minute - 1) % 60);

  String _f(int v) => v.toString().padLeft(2, '0');

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // 标题
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.access_time, color: WarmColors.primary, size: 28),
              const SizedBox(width: 8),
              const Text('选择提醒时间', style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: WarmColors.textDark)),
            ],
          ),
          const SizedBox(height: 24),

          // 时间选择
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _buildNumberColumn(
                value: _f(_hour),
                onIncrement: _incrementHour,
                onDecrement: _decrementHour,
                label: '时',
              ),
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 8),
                child: Text(':', style: TextStyle(fontSize: 52, fontWeight: FontWeight.bold, color: WarmColors.primary)),
              ),
              _buildNumberColumn(
                value: _f(_minute),
                onIncrement: _incrementMinute,
                onDecrement: _decrementMinute,
                label: '分',
              ),
            ],
          ),
          const SizedBox(height: 24),

          // 快捷时间
          const Text('快捷选择', style: TextStyle(fontSize: 16, color: WarmColors.textSecondary, fontWeight: FontWeight.bold)),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            alignment: WrapAlignment.center,
            children: [
              _buildQuickButton('5分钟后', () => _quickMinutes(5)),
              _buildQuickButton('10分钟后', () => _quickMinutes(10)),
              _buildQuickButton('30分钟后', () => _quickMinutes(30)),
              _buildQuickButton('1小时后', () => _quickMinutes(60)),
              _buildQuickButton('早上8点', () => _quickTime(8, 0)),
              _buildQuickButton('中午12点', () => _quickTime(12, 0)),
              _buildQuickButton('晚上8点', () => _quickTime(20, 0)),
            ],
          ),
          const SizedBox(height: 20),

          // 确认按钮 — 大号暖橙
          SizedBox(
            width: double.infinity,
            height: 56,
            child: ElevatedButton(
              onPressed: () => widget.onTimeSelected(TimeOfDay(hour: _hour, minute: _minute)),
              style: ElevatedButton.styleFrom(
                backgroundColor: WarmColors.primary,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
                elevation: 2,
              ),
              child: const Text('确定', style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNumberColumn({
    required String value,
    required VoidCallback onIncrement,
    required VoidCallback onDecrement,
    required String label,
  }) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          width: 76,
          height: 56,
          child: IconButton(
            onPressed: onIncrement,
            icon: const Icon(Icons.expand_less, size: 40, color: WarmColors.primary),
            style: IconButton.styleFrom(
              backgroundColor: WarmColors.primary.withOpacity(0.1),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            ),
          ),
        ),
        const SizedBox(height: 4),
        Container(
          width: 88,
          height: 76,
          decoration: BoxDecoration(
            border: Border.all(color: WarmColors.primary, width: 2.5),
            borderRadius: BorderRadius.circular(14),
            color: WarmColors.primary.withOpacity(0.03),
          ),
          child: Center(
            child: Text(value, style: const TextStyle(fontSize: 44, fontWeight: FontWeight.bold, color: WarmColors.primary)),
          ),
        ),
        const SizedBox(height: 4),
        SizedBox(
          width: 76,
          height: 56,
          child: IconButton(
            onPressed: onDecrement,
            icon: const Icon(Icons.expand_more, size: 40, color: WarmColors.primary),
            style: IconButton.styleFrom(
              backgroundColor: WarmColors.primary.withOpacity(0.1),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            ),
          ),
        ),
        const SizedBox(height: 4),
        Text(label, style: const TextStyle(fontSize: 16, color: WarmColors.textSecondary, fontWeight: FontWeight.bold)),
      ],
    );
  }

  Widget _buildQuickButton(String label, VoidCallback onTap) {
    return ActionChip(
      label: Text(label, style: const TextStyle(fontSize: 15, color: WarmColors.textDark)),
      onPressed: onTap,
      backgroundColor: WarmColors.primary.withOpacity(0.08),
      side: const BorderSide(color: WarmColors.primary, width: 1),
      labelPadding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
    );
  }

  void _quickMinutes(int minutes) {
    final target = DateTime.now().add(Duration(minutes: minutes));
    setState(() { _hour = target.hour; _minute = target.minute; });
  }

  void _quickTime(int hour, int minute) {
    setState(() { _hour = hour; _minute = minute; });
  }
}
