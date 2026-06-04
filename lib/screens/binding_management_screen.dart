import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../main.dart';
import '../models/app_models.dart';
import '../services/local_storage_service.dart';

/// v1.0.56: 绑定管理页面 - 查看和删除多余绑定
class BindingManagementScreen extends StatefulWidget {
  const BindingManagementScreen({super.key});

  @override
  State<BindingManagementScreen> createState() => _BindingManagementScreenState();
}

class _BindingManagementScreenState extends State<BindingManagementScreen> {
  final LocalStorageService _storage = LocalStorageService();
  List<BindingModel> _bindings = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadBindings();
  }

  Future<void> _loadBindings() async {
    final appState = context.read<AppState>();
    if (appState.userId == null) {
      setState(() => _isLoading = false);
      return;
    }

    final bindings = await _storage.getBindings(appState.userId!);
    // 只显示active状态的绑定
    final activeBindings = bindings.where((b) => b.status == 'active').toList();
    
    setState(() {
      _bindings = activeBindings;
      _isLoading = false;
    });
  }

  Future<void> _deleteBinding(BindingModel binding) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('确认解绑'),
        content: Text('确定要解除与该子女的绑定吗？解绑后子女将无法再为您设置提醒。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('确认解绑'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      await _storage.deleteBinding(binding.bindingId);
      await _loadBindings();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('已解除绑定'), backgroundColor: Colors.green),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('管理绑定'),
        centerTitle: true,
        elevation: 0,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _bindings.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.link_off, size: 64, color: Colors.grey[400]),
                      const SizedBox(height: 16),
                      Text(
                        '暂无绑定关系',
                        style: TextStyle(fontSize: 18, color: Colors.grey[600]),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        '点击"绑定子女"添加绑定',
                        style: TextStyle(fontSize: 14, color: Colors.grey[500]),
                      ),
                    ],
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: _bindings.length,
                  itemBuilder: (context, index) {
                    final binding = _bindings[index];
                    return Card(
                      margin: const EdgeInsets.only(bottom: 12),
                      child: ListTile(
                        leading: CircleAvatar(
                          backgroundColor: Colors.blue[50],
                          child: Icon(Icons.person, color: Colors.blue[700]),
                        ),
                        title: Text(
                          '子女账号',
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                        subtitle: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('绑定ID: ${binding.bindingId}'),
                            Text(
                              '状态: ${binding.status == 'active' ? '已激活' : '待确认'}',
                              style: TextStyle(
                                color: binding.status == 'active' 
                                    ? Colors.green 
                                    : Colors.orange,
                              ),
                            ),
                          ],
                        ),
                        trailing: IconButton(
                          icon: const Icon(Icons.delete_outline, color: Colors.red),
                          onPressed: () => _deleteBinding(binding),
                        ),
                        isThreeLine: true,
                      ),
                    );
                  },
                ),
    );
  }
}
