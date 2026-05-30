import 'package:flutter/material.dart';

/// 老人友好的时间选择器 - 大数字 + 加减按钮
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

  void _incrementHour() {
    setState(() {
      _hour = (_hour + 1) % 24;
    });
  }

  void _decrementHour() {
    setState(() {
      _hour = (_hour - 1) % 24;
    });
  }

  void _incrementMinute() {
    setState(() {
      _minute = (_minute + 1) % 60;
    });
  }

  void _decrementMinute() {
    setState(() {
      _minute = (_minute - 1) % 60;
    });
  }

  String _formatHour() {
    return _hour.toString().padLeft(2, '0');
  }

  String _formatMinute() {
    return _minute.toString().padLeft(2, '0');
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // 小时
              _buildNumberColumn(
                value: _formatHour(),
                onIncrement: _incrementHour,
                onDecrement: _decrementHour,
                label: '时',
              ),
              
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 8),
                child: Text(':', style: TextStyle(fontSize: 48, fontWeight: FontWeight.bold)),
              ),
              
              // 分钟
              _buildNumberColumn(
                value: _formatMinute(),
                onIncrement: _incrementMinute,
                onDecrement: _decrementMinute,
                label: '分',
              ),
            ],
          ),
          const SizedBox(height: 20),
          
          // 快捷时间按钮
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
          const SizedBox(height: 16),
          
          // 确认按钮
          SizedBox(
            width: double.infinity,
            height: 52,
            child: ElevatedButton(
              onPressed: () {
                widget.onTimeSelected(TimeOfDay(hour: _hour, minute: _minute));
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.blue,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(26),
                ),
              ),
              child: const Text('确定', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
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
        // 加号按钮
        SizedBox(
          width: 72,
          height: 56,
          child: IconButton(
            onPressed: onIncrement,
            icon: const Icon(Icons.expand_less, size: 36),
            style: IconButton.styleFrom(
              backgroundColor: Colors.blue[50],
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
          ),
        ),
        const SizedBox(height: 4),
        // 数字
        Container(
          width: 80,
          height: 72,
          decoration: BoxDecoration(
            border: Border.all(color: Colors.blue, width: 2),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Center(
            child: Text(
              value,
              style: const TextStyle(
                fontSize: 40,
                fontWeight: FontWeight.bold,
                color: Colors.blue,
              ),
            ),
          ),
        ),
        const SizedBox(height: 4),
        // 减号按钮
        SizedBox(
          width: 72,
          height: 56,
          child: IconButton(
            onPressed: onDecrement,
            icon: const Icon(Icons.expand_more, size: 36),
            style: IconButton.styleFrom(
              backgroundColor: Colors.blue[50],
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
          ),
        ),
        const SizedBox(height: 4),
        Text(label, style: const TextStyle(fontSize: 14, color: Colors.grey)),
      ],
    );
  }

  Widget _buildQuickButton(String label, VoidCallback onTap) {
    return ActionChip(
      label: Text(label, style: const TextStyle(fontSize: 14)),
      onPressed: onTap,
      backgroundColor: Colors.grey[100],
      side: BorderSide(color: Colors.grey[300]!),
    );
  }

  void _quickMinutes(int minutes) {
    final now = DateTime.now();
    final target = now.add(Duration(minutes: minutes));
    setState(() {
      _hour = target.hour;
      _minute = target.minute;
    });
  }

  void _quickTime(int hour, int minute) {
    setState(() {
      _hour = hour;
      _minute = minute;
    });
  }
}

/// 弹出时间选择器的便捷方法
Future<TimeOfDay?> showSimpleTimePicker(BuildContext context, {TimeOfDay? initialTime}) {
  TimeOfDay? result;
  showModalBottomSheet(
    context: context,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (context) => SimpleTimePicker(
      initialTime: initialTime ?? TimeOfDay.now(),
      onTimeSelected: (time) {
        result = time;
        Navigator.pop(context);
      },
    ),
  );
  return Future.value(result);
}
