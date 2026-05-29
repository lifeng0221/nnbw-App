import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../main.dart';
import '../services/api_service.dart';

/// 绑定页面 - 配对码绑定
class BindScreen extends StatefulWidget {
  const BindScreen({super.key});
  
  @override
  State<BindScreen> createState() => _BindScreenState();
}

class _BindScreenState extends State<BindScreen> {
  final ApiService _api = ApiService();
  final TextEditingController _pairCodeController = TextEditingController();
  
  String? _generatedCode;
  bool _isLoading = false;
  
  @override
  Widget build(BuildContext context) {
    final appState = context.watch<AppState>();
    
    return Scaffold(
      appBar: AppBar(title: const Text('绑定')),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: appState.isChild 
            ? _buildChildView() 
            : _buildParentView(),
      ),
    );
  }
  
  /// 子女端 - 生成配对码
  Widget _buildChildView() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        const SizedBox(height: 40),
        const Text(
          '让爸妈输入配对码',
          style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 12),
        const Text(
          '将以下配对码告诉爸妈，在老人端输入即可绑定',
          style: TextStyle(fontSize: 16, color: Colors.grey),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 40),
        
        if (_generatedCode != null)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: Colors.blue[50],
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.blue, width: 2),
            ),
            child: Column(
              children: [
                const Text('配对码', style: TextStyle(fontSize: 16, color: Colors.grey)),
                const SizedBox(height: 8),
                Text(
                  _generatedCode!,
                  style: const TextStyle(
                    fontSize: 48, 
                    fontWeight: FontWeight.bold,
                    letterSpacing: 8,
                    color: Colors.blue,
                  ),
                ),
              ],
            ),
          )
        else
          const SizedBox.shrink(),
        
        const SizedBox(height: 24),
        SizedBox(
          width: double.infinity,
          height: 52,
          child: ElevatedButton(
            onPressed: _isLoading ? null : _generatePairCode,
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.blue,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(26)),
            ),
            child: _isLoading
                ? const CircularProgressIndicator(color: Colors.white)
                : const Text('生成配对码', style: TextStyle(fontSize: 20)),
          ),
        ),
      ],
    );
  }
  
  /// 老人端 - 输入配对码
  Widget _buildParentView() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        const SizedBox(height: 40),
        const Text(
          '输入子女给的配对码',
          style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 12),
        const Text(
          '让子女在他们的手机上生成配对码',
          style: TextStyle(fontSize: 16, color: Colors.grey),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 40),
        
        TextField(
          controller: _pairCodeController,
          style: const TextStyle(
            fontSize: 36,
            fontWeight: FontWeight.bold,
            letterSpacing: 8,
          ),
          textAlign: TextAlign.center,
          maxLength: 6,
          keyboardType: TextInputType.number,
          decoration: InputDecoration(
            hintText: '------',
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
              borderSide: const BorderSide(width: 2),
            ),
            counterText: '',
          ),
        ),
        
        const SizedBox(height: 24),
        SizedBox(
          width: double.infinity,
          height: 52,
          child: ElevatedButton(
            onPressed: _isLoading ? null : _confirmBind,
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.blue,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(26)),
            ),
            child: _isLoading
                ? const CircularProgressIndicator(color: Colors.white)
                : const Text('确认绑定', style: TextStyle(fontSize: 20)),
          ),
        ),
      ],
    );
  }
  
  Future<void> _generatePairCode() async {
    final appState = context.read<AppState>();
    setState(() => _isLoading = true);
    
    final result = await _api.generatePairCode(appState.userId!);
    
    setState(() {
      _isLoading = false;
      if (result['pair_code'] != null) {
        _generatedCode = result['pair_code'];
      }
    });
  }
  
  Future<void> _confirmBind() async {
    final appState = context.read<AppState>();
    final code = _pairCodeController.text.trim();
    
    if (code.length != 6) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请输入6位配对码')),
      );
      return;
    }
    
    setState(() => _isLoading = true);
    
    final result = await _api.confirmBind(appState.userId!, code);
    
    setState(() => _isLoading = false);
    
    if (result['status'] == 'active' || result['binding_id'] != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('绑定成功！')),
      );
      Navigator.pop(context);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('绑定失败：${result['error'] ?? '配对码无效'}')),
      );
    }
  }
}
