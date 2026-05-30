import 'package:flutter/material.dart';

/// 暖炉风配色常量
class WarmColors {
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

/// 老人友好的时间选择器 - 可滚动 + 暖炉风 + 取消按钮
class SimpleTimePicker extends StatefulWidget {
  final TimeOfDay initialTime;
  final ValueChanged<TimeOfDay> onTimeSelected;
  final VoidCallback? onCancel;

  const SimpleTimePicker({
    super.key,
    required this.initialTime,
    required this.onTimeSelected,
    this.onCancel,
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
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.65,
      ),
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // 标题 + 关闭
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(children: [
                  const Icon(Icons.access_time, color: WarmColors.primary, size: 28),
                  const SizedBox(width: 8),
                  const Text('选择提醒时间', style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: WarmColors.textDark)),
                ]),
                IconButton(
                  onPressed: () {
                    Navigator.pop(context);
                    widget.onCancel?.call();
                  },
                  icon: const Icon(Icons.close, size: 28, color: WarmColors.textSecondary),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // 时间选择
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _buildNumberColumn(value: _f(_hour), onIncrement: _incrementHour, onDecrement: _decrementHour, label: '时'),
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 6),
                  child: Text(':', style: TextStyle(fontSize: 48, fontWeight: FontWeight.bold, color: WarmColors.primary)),
                ),
                _buildNumberColumn(value: _f(_minute), onIncrement: _incrementMinute, onDecrement: _decrementMinute, label: '分'),
              ],
            ),
            const SizedBox(height: 16),

            // 快捷时间
            const Text('快捷选择', style: TextStyle(fontSize: 16, color: WarmColors.textSecondary, fontWeight: FontWeight.bold)),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8, runSpacing: 8, alignment: WrapAlignment.center,
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

            // 确定按钮
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
      ),
    );
  }

  Widget _buildNumberColumn({required String value, required VoidCallback onIncrement, required VoidCallback onDecrement, required String label}) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(width: 72, height: 52,
          child: IconButton(onPressed: onIncrement, icon: const Icon(Icons.expand_less, size: 36, color: WarmColors.primary),
            style: IconButton.styleFrom(backgroundColor: WarmColors.primary.withOpacity(0.1), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))))),
        const SizedBox(height: 4),
        Container(width: 84, height: 70,
          decoration: BoxDecoration(border: Border.all(color: WarmColors.primary, width: 2.5), borderRadius: BorderRadius.circular(14), color: WarmColors.primary.withOpacity(0.03)),
          child: Center(child: Text(value, style: const TextStyle(fontSize: 42, fontWeight: FontWeight.bold, color: WarmColors.primary)))),
        const SizedBox(height: 4),
        SizedBox(width: 72, height: 52,
          child: IconButton(onPressed: onDecrement, icon: const Icon(Icons.expand_more, size: 36, color: WarmColors.primary),
            style: IconButton.styleFrom(backgroundColor: WarmColors.primary.withOpacity(0.1), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))))),
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
