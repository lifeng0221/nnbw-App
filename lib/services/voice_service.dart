import 'dart:io';
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'api_service.dart';

/// 语音录制+识别服务（简化版，先跑通编译）
/// 正式版会替换为讯飞SDK原生集成
class VoiceService {
  final ApiService _api = ApiService();
  
  bool _isRecording = false;
  bool get isRecording => _isRecording;
  
  Future<bool> requestPermission() async {
    final status = await Permission.microphone.request();
    return status.isGranted;
  }
  
  Future<bool> startRecording() async {
    if (_isRecording) return false;
    final hasPermission = await requestPermission();
    if (!hasPermission) return false;
    // TODO: 接入讯飞SDK或record包后实现录音
    _isRecording = true;
    return true;
  }
  
  Future<String?> stopRecording() async {
    if (!_isRecording) return null;
    _isRecording = false;
    // TODO: 返回录音文件路径
    return null;
  }
  
  Future<void> cancelRecording() async {
    _isRecording = false;
  }
  
  Future<Map<String, String>?> transcribe(String audioPath) async {
    final file = File(audioPath);
    if (!await file.exists()) return null;
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
  
  Future<void> dispose() async {}
}
