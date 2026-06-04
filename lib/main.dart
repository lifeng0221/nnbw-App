import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'screens/parent_home_screen.dart';
import 'screens/child_home_screen.dart';
import 'screens/bind_screen.dart';
import 'screens/binding_management_screen.dart';
import 'screens/login_screen.dart';
import 'services/api_service.dart';
import 'services/alarm_service.dart';


void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => AppState()),
        Provider(create: (_) => ApiService()),
      ],
      child: const NianNianBuWangApp(),
    ),
  );
}

class AppState extends ChangeNotifier {
  String? userId;
  String? userRole;
  String? nickname;
  bool get isLoggedIn => userId != null;
  bool get isParent => userRole == 'parent';
  bool get isChild => userRole == 'child';

  Future<void> loadFromPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    userId = prefs.getString('user_id');
    userRole = prefs.getString('user_role');
    nickname = prefs.getString('nickname');
    notifyListeners();
  }

  Future<void> setUser(String id, String role, String name) async {
    userId = id; userRole = role; nickname = name;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('user_id', id);
    await prefs.setString('user_role', role);
    await prefs.setString('nickname', name);
    notifyListeners();
  }

  Future<void> logout() async {
    // 🔧 v1.0.27: 退出登录时保留持久化的角色userId（parent_user_id / child_user_id）
    // 只清除当前session信息，不删除跨session的持久数据
    final prefs = await SharedPreferences.getInstance();
    final parentUserId = prefs.getString('parent_user_id');
    final childUserId = prefs.getString('child_user_id');
    
    userId = null; userRole = null; nickname = null;
    await prefs.clear();
    
    // 恢复持久化的角色userId
    if (parentUserId != null) await prefs.setString('parent_user_id', parentUserId);
    if (childUserId != null) await prefs.setString('child_user_id', childUserId);
    
    notifyListeners();
  }
}

class NianNianBuWangApp extends StatelessWidget {
  const NianNianBuWangApp({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '念念不忘',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFFFF8C42),
          brightness: Brightness.light,
        ),
        useMaterial3: true,
        scaffoldBackgroundColor: const Color(0xFFFFF8F0),
        appBarTheme: const AppBarTheme(
          backgroundColor: Color(0xFFFFF8F0),
          elevation: 0,
        ),
      ),
      home: const SplashScreen(),
    );
  }
}

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});
  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  @override
  void initState() { super.initState(); _checkLogin(); }

  Future<void> _checkLogin() async {
    final appState = context.read<AppState>();
    await appState.loadFromPrefs();
    await Future.delayed(const Duration(seconds: 1));
    if (!mounted) return;
    if (appState.isLoggedIn) {
      Navigator.pushReplacement(context, MaterialPageRoute(
        builder: (_) => appState.isParent ? const ParentHomeScreen() : const ChildHomeScreen()));
    } else {
      Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const LoginScreen()));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFFF8C42),
      body: Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        const Icon(Icons.notifications_active, size: 80, color: Colors.white),
        const SizedBox(height: 20),
        const Text('念念不忘', style: TextStyle(fontSize: 36, fontWeight: FontWeight.bold, color: Colors.white)),
        const SizedBox(height: 8),
        Text('到点一定响', style: TextStyle(fontSize: 18, color: Colors.white.withAlpha(200))),
      ])),
    );
  }
}
