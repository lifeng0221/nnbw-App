import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import '../services/local_storage_service.dart';

/// v1.0.56: 首次启动引导弹窗——解决"后台耗电权限"用户找不到的问题
/// 仅在首次打开App时弹出，一步一步引导用户完成关键设置
class BatteryGuideDialog extends StatefulWidget {
  const BatteryGuideDialog({super.key});

  @override
  State<BatteryGuideDialog> createState() => _BatteryGuideDialogState();
}

class _BatteryGuideDialogState extends State<BatteryGuideDialog> {
  int _step = 0;
  bool _isOpening = false;

  final List<_GuideStep> _steps = [
    _GuideStep(
      icon: Icons.battery_charging_full,
      title: '允许后台耗电',
      desc: '设置 → 电池 → 后台耗电管理\n找到「念念不忘」→ 设为「允许后台耗电」',
      tip: '这是最关键的设置！不开启的话，息屏后提醒会失效',
      color: Colors.orange,
    ),
    _GuideStep(
      icon: Icons.power_settings_new,
      title: '关闭智能控制（可选）',
      desc: '设置 → 电池 → 后台耗电管理\n关闭「智能控制后台耗电」或把念念不忘设为「无限制」',
      tip: '部分手机系统会自动限制后台应用，关闭后可确保提醒稳定',
      color: Colors.blue,
    ),
    _GuideStep(
      icon: Icons.do_not_disturb_off,
      title: '勿扰模式允许提醒',
      desc: '息屏时请确保勿扰模式关闭，\n或把念念不忘加入勿扰白名单',
      tip: '勿扰模式开启时通知会被静音，提醒铃声也可能不响',
      color: Colors.purple,
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final current = _steps[_step];
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Container(
        constraints: const BoxConstraints(maxWidth: 360, maxHeight: 600),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // 标题
              Row(
                children: [
                  Icon(Icons.settings_backup_restore, color: Colors.orange.shade700, size: 28),
                  const SizedBox(width: 10),
                  const Expanded(
                    child: Text(
                      '息屏响铃设置',
                      style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                '首次使用请按以下步骤设置，否则息屏时提醒可能不响',
                style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
              ),
              const SizedBox(height: 20),

              // 步骤指示器
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(_steps.length, (i) => Container(
                  width: _step == i ? 24 : 8,
                  height: 8,
                  margin: const EdgeInsets.symmetric(horizontal: 3),
                  decoration: BoxDecoration(
                    color: _step == i ? Colors.orange : Colors.grey.shade300,
                    borderRadius: BorderRadius.circular(4),
                  ),
                )),
              ),
              const SizedBox(height: 24),

              // 内容
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: current.color.withOpacity(0.08),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: current.color.withOpacity(0.3)),
                ),
                child: Column(
                  children: [
                    Icon(current.icon, color: current.color, size: 48),
                    const SizedBox(height: 12),
                    Text(
                      current.title,
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: current.color,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      current.desc,
                      textAlign: TextAlign.center,
                      style: const TextStyle(fontSize: 14, height: 1.5),
                    ),
                    const SizedBox(height: 10),
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: Colors.amber.shade50,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.amber.shade200),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.lightbulb, color: Colors.amber.shade700, size: 18),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              current.tip,
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.amber.shade900,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              // v1.0.56: 一键跳转按钮（针对各品牌电池设置页面）
              if (_step == 0) ...[
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: _isOpening ? null : _openBatterySettings,
                    icon: _isOpening
                        ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                        : const Icon(Icons.open_in_new, size: 18),
                    label: Text(_isOpening ? '正在打开...' : '一键跳转设置', style: const TextStyle(fontSize: 14)),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.orange.shade700,
                      side: BorderSide(color: Colors.orange.shade300),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                  ),
                ),
              ],
              // v1.0.56: 最后一步显示"去设置"按钮
              if (_step == _steps.length - 1) ...[
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: _isOpening ? null : _openBatterySettings,
                    icon: _isOpening
                        ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                        : const Icon(Icons.settings, size: 18),
                    label: Text(_isOpening ? '正在打开...' : '去设置', style: const TextStyle(fontSize: 14)),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.purple.shade700,
                      side: BorderSide(color: Colors.purple.shade300),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 20),

              // 按钮
              Row(
                children: [
                  if (_step > 0)
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => setState(() => _step--),
                        child: const Text('上一步'),
                      ),
                    ),
                  if (_step > 0) const SizedBox(width: 12),
                  Expanded(
                    flex: _step > 0 ? 1 : 2,
                    child: ElevatedButton(
                      onPressed: () {
                        if (_step < _steps.length - 1) {
                          setState(() => _step++);
                        } else {
                          _markShown();
                          Navigator.pop(context);
                        }
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.orange,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                      child: Text(
                        _step < _steps.length - 1 ? '下一步 →' : '我知道了，开始使用',
                        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _markShown() async {
    final storage = LocalStorageService();
    await storage.setString('battery_guide_shown', 'true');
  }

  // v1.0.56: 一键跳转电池设置页面
  Future<void> _openBatterySettings() async {
    if (_isOpening) return;
    setState(() => _isOpening = true);
    bool success = false;

    try {
      // 直接打开应用详情页面（最可靠的方式）
      if (Platform.isAndroid) {
        // 尝试打开应用详情页面
        final Uri uri = Uri.parse('package:com.niannianbuwang.app');
        final canLaunch = await canLaunchUrl(uri);
        
        if (canLaunch) {
          print('🟢 打开应用详情页: $uri');
          await launchUrl(uri, mode: LaunchMode.externalApplication);
          success = true;
        } else {
          // 尝试打开设置页面
          final Uri settingsUri = Uri.parse('android-settings:');
          final canLaunchSettings = await canLaunchUrl(settingsUri);
          if (canLaunchSettings) {
            await launchUrl(settingsUri, mode: LaunchMode.externalApplication);
            success = true;
          }
        }
      }

      if (!success) {
        _showManualGuide();
      }
    } catch (e) {
      print('🔴 电池设置跳转失败: $e');
      _showManualGuide();
    } finally {
      if (mounted) {
        setState(() => _isOpening = false);
      }
    }
  }

  void _showManualGuide() {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('请按上方步骤手动设置：设置→电池→后台耗电→允许'),
          backgroundColor: Colors.orange,
          duration: Duration(seconds: 4),
        ),
      );
    }
  }
}

class _GuideStep {
  final IconData icon;
  final String title;
  final String desc;
  final String tip;
  final Color color;
  _GuideStep({
    required this.icon,
    required this.title,
    required this.desc,
    required this.tip,
    required this.color,
  });
}

/// 检查是否需要显示首次引导弹窗
Future<bool> shouldShowBatteryGuide() async {
  final storage = LocalStorageService();
  final shown = await storage.getString('battery_guide_shown');
  return shown != 'true';
}
