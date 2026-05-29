import 'dart:io';
import 'package:record/record.dart';
import 'package:permission_handler/permission_handler.dart';
import 'api_service.dart';

/// 语音录制+识别服务
class VoiceService {
  final AudioRecorder _recorder = AudioRecorder();
  final ApiService _api = ApiService();
  
  bool _isRecording = false;
  bool get isRecording => _isRecording;
  
  String? _currentRecordingPath;
  
  /// 请求录音权限
  Future<bool> requestPermission() async {
    final status = await Permission.microphone.request();
    return status.isGranted;
  }
  
  /// 开始录音
  Future<bool> startRecording() async {
    if (_isRecording) return false;
    
    final hasPermission = await requestPermission();
    if (!hasPermission) return false;
    
    try {
      _currentRecordingPath = await _recorder.start(
        const RecordConfig(
          encoder: AudioEncoder.aacLc,
          numChannels: 1,
          sampleRate: 16000, // 讯飞ASR推荐采样率
        ),
      );
      
      _isRecording = true;
      return true;
    } catch (e) {
      _isRecording = false;
      return false;
    }
  }
  
  /// 停止录音，返回录音文件路径
  Future<String?> stopRecording() async {
    if (!_isRecording) return null;
    
    try {
      final path = await _recorder.stop();
      _isRecording = false;
      return path;
    } catch (e) {
      _isRecording = false;
      return null;
    }
  }
  
  /// 取消录音
  Future<void> cancelRecording() async {
    if (!_isRecording) return;
    
    try {
      await _recorder.stop();
      // 删除临时文件
      if (_currentRecordingPath != null) {
        final file = File(_currentRecordingPath!);
        if (await file.exists()) await file.delete();
      }
    } catch (e) {
      // ignore
    }
    _isRecording = false;
    _currentRecordingPath = null;
  }
  
  /// 录音+识别一体化
  /// 返回 {text: 识别文字, voicePath: 录音路径, voiceUrl: 上传后URL}
  Future<Map<String, String>?> recordAndTranscribe() async {
    // 开始录音
    final started = await startRecording();
    if (!started) return null;
    
    // 等待用户停止（由调用方控制）
    // 调用方在松开按钮时调 stopRecording + transcribe
    return null;
  }
  
  /// 上传录音并转文字
  Future<Map<String, String>?> transcribe(String audioPath) async {
    final file = File(audioPath);
    if (!await file.exists()) return null;
    
    // 上传到后端进行ASR
    final result = await _api.transcribeVoice(file);
    
    if (result['success'] == true || result['text'] != null) {
      return {
        'text': result['text'] ?? '',
        'voiceUrl': result['voice_url'] ?? '',
        'voicePath': audioPath,
      };
    }
    
    return null;
  }
  
  /// 释放资源
  Future<void> dispose() async {
    await _recorder.dispose();
  }
}
