import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';

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

/// Bug 5 修复: 老人友好的时间选择器 - 滑动选择 + 暖炉风 + 老人大字
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
  bool _isPM = false; // true=下午，false=上午（默认下午，兼容用户说"3点"≈下午3点的习惯）

  @override
  void initState() {
    super.initState();
    _hour = widget.initialTime.hour;
    _minute = widget.initialTime.minute;
    // 如果是下午时段（13-23点），默认勾选下午
    _isPM = _hour >= 13;
    // 统一转为12小时制显示
    if (_hour == 0) {
      _hour = 12;
    } else if (_hour > 12) {
      _hour = _hour - 12;
    }
  }

  /// 把12小时制显示值转为24小时制
  int _to24Hour(int displayHour, bool isPM) {
    if (displayHour == 12) {
      return isPM ? 12 : 0; // 12 PM=12, 12 AM=0
    }
    return isPM ? displayHour + 12 : displayHour;
  }

  String _f(int v) => v.toString().padLeft(2, '0');

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.65,
      ),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
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

            // Bug 5 修复: 滑动选择器 - 大号数字显示 + 实时更新
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: WarmColors.primary.withOpacity(0.06),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: WarmColors.primary.withOpacity(0.3)),
              ),
              child: Column(
                children: [
                  // 大号时间显示（带上下午标识）
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        _f(_hour),
                        style: const TextStyle(
                          fontSize: 72,
                          fontWeight: FontWeight.bold,
                          color: WarmColors.primary,
                        ),
                      ),
                      const Padding(
                        padding: EdgeInsets.symmetric(horizontal: 8),
                        child: Text(':', style: TextStyle(fontSize: 72, fontWeight: FontWeight.bold, color: WarmColors.primary)),
                      ),
                      Text(
                        _f(_minute),
                        style: const TextStyle(
                          fontSize: 72,
                          fontWeight: FontWeight.bold,
                          color: WarmColors.primary,
                        ),
                      ),
                    ],
                  ),
                  // 上下午大标签
                  Container(
                    margin: const EdgeInsets.only(top: 4),
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
                    decoration: BoxDecoration(
                      color: _isPM ? Colors.deepOrange.withOpacity(0.15) : Colors.blue.withOpacity(0.15),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      _isPM ? '下午' : '上午',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: _isPM ? Colors.deepOrange : Colors.blue,
                      ),
                    ),
                  ),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text('时', style: TextStyle(fontSize: 18, color: WarmColors.textSecondary)),
                      const SizedBox(width: 60),
                      Text('分', style: TextStyle(fontSize: 18, color: WarmColors.textSecondary)),
                    ],
                  ),
                  const SizedBox(height: 16),

                  // 小时滑动条
                  Row(
                    children: [
                      const Icon(Icons.schedule, color: WarmColors.primary, size: 20),
                      const SizedBox(width: 8),
                      const Text('小时', style: TextStyle(fontSize: 16, color: WarmColors.textDark, fontWeight: FontWeight.w500)),
                      const Spacer(),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                        decoration: BoxDecoration(
                          color: WarmColors.primary,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          _isPM ? '下午 ${_f(_hour)}' : '上午 ${_f(_hour)}',
                          style: const TextStyle(fontSize: 16, color: Colors.white, fontWeight: FontWeight.bold),
                        ),
                      ),
                    ],
                  ),
                  SliderTheme(
                    data: SliderTheme.of(context).copyWith(
                      activeTrackColor: WarmColors.primary,
                      inactiveTrackColor: WarmColors.primary.withOpacity(0.2),
                      thumbColor: WarmColors.primary,
                      overlayColor: WarmColors.primary.withOpacity(0.2),
                      trackHeight: 8,
                      thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 14),
                    ),
                    child: Slider(
                      value: _hour.toDouble(),
                      min: 1,
                      max: 12,
                      divisions: 11,
                      onChanged: (v) => setState(() => _hour = v.round()),
                    ),
                  ),
                  const SizedBox(height: 8),

                  // AM/PM 切换按钮
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      _buildAmPmButton('上午', !_isPM, () => setState(() => _isPM = false)),
                      const SizedBox(width: 16),
                      _buildAmPmButton('下午', _isPM, () => setState(() => _isPM = true)),
                    ],
                  ),

                  // 分钟滑动条
                  Row(
                    children: [
                      const Icon(Icons.timer, color: WarmColors.primary, size: 20),
                      const SizedBox(width: 8),
                      const Text('分钟', style: TextStyle(fontSize: 16, color: WarmColors.textDark, fontWeight: FontWeight.w500)),
                      const Spacer(),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                        decoration: BoxDecoration(
                          color: WarmColors.primary,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          _f(_minute),
                          style: const TextStyle(fontSize: 18, color: Colors.white, fontWeight: FontWeight.bold),
                        ),
                      ),
                    ],
                  ),
                  SliderTheme(
                    data: SliderTheme.of(context).copyWith(
                      activeTrackColor: WarmColors.primary,
                      inactiveTrackColor: WarmColors.primary.withOpacity(0.2),
                      thumbColor: WarmColors.primary,
                      overlayColor: WarmColors.primary.withOpacity(0.2),
                      trackHeight: 8,
                      thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 14),
                    ),
                    child: Slider(
                      value: _minute.toDouble(),
                      min: 0,
                      max: 59,
                      divisions: 59,
                      onChanged: (v) => setState(() => _minute = v.round()),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // 快捷时间（保留）
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
                _buildQuickButton('下午3点', () { setState(() { _hour = 3; _isPM = true; }); }),
                _buildQuickButton('下午6点', () { setState(() { _hour = 6; _isPM = true; }); }),
                _buildQuickButton('晚上8点', () { setState(() { _hour = 8; _isPM = true; }); }),
              ],
            ),
            const SizedBox(height: 16),

            // 确定按钮
            SizedBox(
              width: double.infinity,
              height: 56,
              child: ElevatedButton(
                onPressed: () => widget.onTimeSelected(TimeOfDay(hour: _to24Hour(_hour, _isPM), minute: _minute)),
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

  Widget _buildQuickButton(String label, VoidCallback onTap) {
    return ActionChip(
      label: Text(label, style: const TextStyle(fontSize: 15, color: WarmColors.textDark)),
      onPressed: onTap,
      backgroundColor: WarmColors.primary.withOpacity(0.08),
      side: const BorderSide(color: WarmColors.primary, width: 1),
      labelPadding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
    );
  }

  Widget _buildAmPmButton(String label, bool isSelected, VoidCallback onTap) {
    final isPM = label == '下午';
    final activeColor = isPM ? Colors.deepOrange : Colors.blue;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 10),
        decoration: BoxDecoration(
          color: isSelected ? activeColor : Colors.grey.shade300,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isSelected ? activeColor : Colors.grey.shade400,
            width: 2,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: isSelected ? Colors.white : Colors.grey.shade600,
          ),
        ),
      ),
    );
  }

  void _quickMinutes(int minutes) {
    final target = DateTime.now().add(Duration(minutes: minutes));
    setState(() {
      _minute = target.minute;
      _isPM = target.hour >= 12;
      _hour = target.hour == 0 ? 12 : (target.hour > 12 ? target.hour - 12 : target.hour);
    });
  }

  void _quickTime(int hour, int minute) {
    setState(() {
      _minute = minute;
      _isPM = hour >= 12;
      _hour = hour == 0 ? 12 : (hour > 12 ? hour - 12 : hour);
    });
  }
}
