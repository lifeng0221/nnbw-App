import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../main.dart';
import '../services/api_service.dart';

/// 登录页面 - 选择角色 + 微信登录
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});
  
  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  String _selectedRole = 'parent'; // 默认老人端
  bool _isLoading = false;
  
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // Logo
              const Icon(Icons.notifications_active, size: 80, color: Colors.blue),
              const SizedBox(height: 16),
              const Text(
                '念念不忘',
                style: TextStyle(fontSize: 36, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              const Text(
                '到点一定响',
                style: TextStyle(fontSize: 18, color: Colors.grey),
              ),
              const SizedBox(height: 48),
              
              // 角色选择
              const Text('我是', style: TextStyle(fontSize: 18)),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: GestureDetector(
                      onTap: () => setState(() => _selectedRole = 'parent'),
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 20),
                        decoration: BoxDecoration(
                          color: _selectedRole == 'parent' ? Colors.blue : Colors.grey[200],
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Column(
                          children: [
                            Icon(
                              Icons.elderly,
                              size: 40,
                              color: _selectedRole == 'parent' ? Colors.white : Colors.grey,
                            ),
                            const SizedBox(height: 8),
                            Text(
                              '长辈',
                              style: TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.bold,
                                color: _selectedRole == 'parent' ? Colors.white : Colors.grey,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              '接收提醒',
                              style: TextStyle(
                                fontSize: 14,
                                color: _selectedRole == 'parent' ? Colors.white70 : Colors.grey,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: GestureDetector(
                      onTap: () => setState(() => _selectedRole = 'child'),
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 20),
                        decoration: BoxDecoration(
                          color: _selectedRole == 'child' ? Colors.blue : Colors.grey[200],
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Column(
                          children: [
                            Icon(
                              Icons.volunteer_activism,
                              size: 40,
                              color: _selectedRole == 'child' ? Colors.white : Colors.grey,
                            ),
                            const SizedBox(height: 8),
                            Text(
                              '子女',
                              style: TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.bold,
                                color: _selectedRole == 'child' ? Colors.white : Colors.grey,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              '设置提醒',
                              style: TextStyle(
                                fontSize: 14,
                                color: _selectedRole == 'child' ? Colors.white70 : Colors.grey,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 40),
              
              // 微信登录按钮
              SizedBox(
                width: double.infinity,
                height: 56,
                child: ElevatedButton.icon(
                  onPressed: _isLoading ? null : _wechatLogin,
                  icon: _isLoading 
                      ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(color: Colors.white))
                      : const Icon(Icons.wechat, size: 28),
                  label: const Text('微信一键登录', style: TextStyle(fontSize: 20)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF07C160), // 微信绿
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              
              const Text(
                '登录即代表同意《用户协议》和《隐私政策》',
                style: TextStyle(fontSize: 12, color: Colors.grey),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }
  
  Future<void> _wechatLogin() async {
    setState(() => _isLoading = true);
    
    // TODO: 接入微信SDK
    // 流程：调起微信授权 → 获取code → 发给后端 → 返回userId
    // 当前先用模拟数据开发
    
    final appState = context.read<AppState>();
    
    // 模拟登录（开发阶段）
    await Future.delayed(const Duration(seconds: 1));
    
    final mockUserId = 'user_${DateTime.now().millisecondsSinceEpoch}';
    await appState.setUser(mockUserId, _selectedRole, 
        _selectedRole == 'parent' ? '长辈' : '子女');
    
    setState(() => _isLoading = false);
    
    if (!mounted) return;
    
    if (_selectedRole == 'parent') {
      Navigator.pushReplacement(
        context, 
        MaterialPageRoute(builder: (_) => const ParentHomeScreen()),
      );
    } else {
      Navigator.pushReplacement(
        context, 
        MaterialPageRoute(builder: (_) => const ChildHomeScreen()),
      );
    }
  }
}

// 需要import的页面
import 'parent_home_screen.dart';
import 'child_home_screen.dart';
