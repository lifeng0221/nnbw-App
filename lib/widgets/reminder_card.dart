import 'package:flutter/material.dart';
import '../models/app_models.dart';

/// 提醒卡片组件
class ReminderCard extends StatelessWidget {
  final ReminderModel reminder;
  final bool isParent;
  final String? currentUserId; // 当前登录用户的ID，用于判断是谁创建的
  final VoidCallback? onConfirm;
  final VoidCallback? onSnooze;
  final VoidCallback? onPlayVoice;
  final VoidCallback? onDelete;
  
  const ReminderCard({
    super.key,
    required this.reminder,
    required this.isParent,
    this.currentUserId,
    this.onConfirm,
    this.onSnooze,
    this.onPlayVoice,
    this.onDelete,
  });
  
  @override
  Widget build(BuildContext context) {
    final statusColor = _getStatusColor();
    final priorityIcon = _getPriorityIcon();
    
    return Card(
      elevation: 1,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: statusColor.withOpacity(0.3), width: 1),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 第一行：时间 + 状态 + 优先级
            Row(
              children: [
                Text(
                  reminder.formattedTime,
                  style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                ),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: statusColor.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    reminder.statusLabel,
                    style: TextStyle(fontSize: 12, color: statusColor),
                  ),
                ),
                if (reminder.isImportant) ...[
                  const SizedBox(width: 4),
                  priorityIcon,
                ],
                const Spacer(),
                if (onDelete != null)
                  IconButton(
                    onPressed: onDelete,
                    icon: const Icon(Icons.delete_outline, size: 20),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            
            // 第二行：内容
            Row(
              children: [
                Expanded(
                  child: Text(
                    reminder.content,
                    style: const TextStyle(fontSize: 18),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (reminder.voiceUrl != null && onPlayVoice != null) ...[
                  const SizedBox(width: 8),
                  IconButton(
                    onPressed: onPlayVoice,
                    icon: const Icon(Icons.play_circle_outline, size: 28, color: Colors.blue),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 4),
            
            // 第三行：来源 + 分类 + 确认状态（子女端可见）
            Row(
              children: [
                _buildTag(
                  // v1.0.58: 用 currentUserId 判断
                  // 子女端：我为爸妈设的（自己创建）vs 父母自设（父母创建）
                  // 老人端：我自己设的（自己创建）vs 子女设的（子女创建）
                  reminder.createdBy == (currentUserId ?? '')
                      ? (isParent ? '我自己设的' : '我为爸妈设的')
                      : (isParent ? '子女设的' : '父母自设'),
                  Colors.blue[100]!,
                  Colors.blue,
                ),
                const SizedBox(width: 6),
                _buildTag(reminder.category, Colors.grey[100]!, Colors.grey),
                // v1.0.60: 子女端显示老人确认状态
                if (!isParent && reminder.status == 'confirmed') ...[
                  const SizedBox(width: 6),
                  _buildTag('✅ 老人已确认', Colors.green[100]!, Colors.green[700]!),
                ] else if (!isParent && reminder.status == 'triggered') ...[
                  // v1.0.60: 触发超过30分钟未确认，显示超时警告
                  DateTime now = DateTime.now();
                  Duration elapsed = now.difference(reminder.triggerTime);
                  if (elapsed.inMinutes >= 30) ...[
                    const SizedBox(width: 6),
                    _buildTag('⚠️ 未确认', Colors.orange[100]!, Colors.orange[700]!),
                  ],
                ],
              ],
            ),
            
            // 第四行：操作按钮（老人端已响铃的提醒）
            if (isParent && (reminder.status == 'triggered' || reminder.status == 'snoozed'))
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Row(
                  children: [
                    Expanded(
                      child: ElevatedButton(
                        onPressed: onConfirm,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.green,
                          foregroundColor: Colors.white,
                          minimumSize: const Size(0, 48),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
                        ),
                        child: const Text('知道了', style: TextStyle(fontSize: 20)),
                      ),
                    ),
                    const SizedBox(width: 12),
                    if (reminder.canSnooze)
                      Expanded(
                        child: OutlinedButton(
                          onPressed: onSnooze,
                          style: OutlinedButton.styleFrom(
                            minimumSize: const Size(0, 48),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
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
  
  Widget _buildTag(String text, Color bgColor, Color textColor) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(text, style: TextStyle(fontSize: 12, color: textColor)),
    );
  }
  
  Color _getStatusColor() {
    switch (reminder.status) {
      case 'confirmed': return Colors.green;
      case 'triggered': 
      case 'snoozed': return Colors.orange;
      case 'pending': return Colors.blue;
      case 'expired':
      case 'skipped': return Colors.grey;
      default: return Colors.grey;
    }
  }
  
  Widget _getPriorityIcon() {
    if (reminder.priority == 'urgent') {
      return const Icon(Icons.priority_high, color: Colors.red, size: 18);
    } else if (reminder.priority == 'important') {
      return const Icon(Icons.flag, color: Colors.orange, size: 18);
    }
    return const SizedBox.shrink();
  }
}
