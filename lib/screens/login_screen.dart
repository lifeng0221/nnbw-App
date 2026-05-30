import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../main.dart';
import 'parent_home_screen.dart';
import 'child_home_screen.dart';

/// 登录页面 - 暖炉风
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});
  
  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  String _selectedRole = 'parent';
  bool _isLoading = false;
  
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFFFF8F0),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // Logo区
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: const Color(0xFFFF8C42).withOpacity(0.1),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.notifications_active, size: 64, color: Color(0xFFFF8C42)),
              ),
              const SizedBox(height: 20),
              const Text(
                '念念不忘',
                style: TextStyle(
                  fontSize: 40,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF3E2723),
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                '到点一定响',
                style: TextStyle(fontSize: 18, color: Color(0xFF8D6E63)),
              ),
              const SizedBox(height: 48),
              
              // 角色选择
              const Text('我是', style: TextStyle(fontSize: 20, color: Color(0xFF3E2723))),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: GestureDetector(
                      onTap: () => setState(() => _selectedRole = 'parent'),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        padding: const EdgeInsets.symmetric(vertical: 24),
                        decoration: BoxDecoration(
                          color: _selectedRole == 'parent' ? const Color(0xFFFF8C42) : Colors.white,
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                            color: _selectedRole == 'parent' ? const Color(0xFFFF8C42) : Colors.grey[300]!,
                            width: 2,
                          ),
                          boxShadow: _selectedRole == 'parent'
                              ? [BoxShadow(color: const Color(0xFFFF8C42).withOpacity(0.3), blurRadius: 12, offset: const Offset(0, 4))]
                              : [],
                        ),
                        child: Column(
                          children: [
                            Icon(Icons.elderly, size: 48,
                              color: _selectedRole == 'parent' ? Colors.white : const Color(0xFF8D6E63)),
                            const SizedBox(height: 10),
                            Text('长辈',
                              style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold,
                                color: _selectedRole == 'parent' ? Colors.white : const Color(0xFF3E2723))),
                            const SizedBox(height: 4),
                            Text('接收提醒',
                              style: TextStyle(fontSize: 14,
                                color: _selectedRole == 'parent' ? Colors.white70 : const Color(0xFF8D6E63))),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: GestureDetector(
                      onTap: () => setState(() => _selectedRole = 'child'),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        padding: const EdgeInsets.symmetric(vertical: 24),
                        decoration: BoxDecoration(
                          color: _selectedRole == 'child' ? const Color(0xFFFF8C42) : Colors.white,
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                            color: _selectedRole == 'child' ? const Color(0xFFFF8C42) : Colors.grey[300]!,
                            width: 2,
                          ),
                          boxShadow: _selectedRole == 'child'
                              ? [BoxShadow(color: const Color(0xFFFF8C42).withOpacity(0.3), blurRadius: 12, offset: const Offset(0, 4))]
                              : [],
                        ),
                        child: Column(
                          children: [
                            Icon(Icons.volunteer_activism, size: 48,
                              color: _selectedRole == 'child' ? Colors.white : const Color(0xFF8D6E63)),
                            const SizedBox(height: 10),
                            Text('子女',
                              style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold,
                                color: _selectedRole == 'child' ? Colors.white : const Color(0xFF3E2723))),
                            const SizedBox(height: 4),
                            Text('设置提醒',
                              style: TextStyle(fontSize: 14,
                                color: _selectedRole == 'child' ? Colors.white70 : const Color(0xFF8D6E63))),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 48),
              
              // 进入按钮
              SizedBox(
                width: double.infinity,
                height: 56,
                child: ElevatedButton(
                  onPressed: _isLoading ? null : _enterApp,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFFF8C42),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
                    elevation: 2,
                  ),
                  child: _isLoading
                      ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(color: Colors.white))
                      : const Text('进入', style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
                ),
              ),
              const SizedBox(height: 16),
              const Text(
                '登录即代表同意《用户协议》和《隐私政策》',
                style: TextStyle(fontSize: 12, color: Color(0xFF8D6E63)),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }
  
  Future<void> _enterApp() async {
    setState(() => _isLoading = true);
    
    final appState = context.read<AppState>();
    await Future.delayed(const Duration(milliseconds: 500));
    
    final mockUserId = 'user_${DateTime.now().millisecondsSinceEpoch}';
    await appState.setUser(mockUserId, _selectedRole, _selectedRole == 'parent' ? '长辈' : '子女');
    
    setState(() => _isLoading = false);
    
    if (!mounted) return;
    
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (_) => _selectedRole == 'parent'
            ? const ParentHomeScreen()
            : const ChildHomeScreen(),
      ),
    );
  }
}
