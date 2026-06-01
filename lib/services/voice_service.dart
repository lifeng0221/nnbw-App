import 'dart:async';
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;

/// 语音服务 — 语音识别（录音用平台原生接口，后续接入）
class VoiceService {
  final stt.SpeechToText _speech = stt.SpeechToText();
  
  bool _isRecording = false;
  bool _speechAvailable = false;
  String _lastRecognizedText = '';
  
  bool get isRecording => _isRecording;
  bool get speechAvailable => _speechAvailable;
  
  /// 初始化语音识别
  Future<bool> init() async {
    _speechAvailable = await _speech.initialize(
      onError: (error) => print('语音识别错误: $error'),
      onStatus: (status) => print('语音识别状态: $status'),
    );
    return _speechAvailable;
  }
  
  /// 请求权限
  Future<bool> requestPermission() async {
    final micStatus = await Permission.microphone.request();
    return micStatus.isGranted;
  }
  
  /// 开始语音识别
  Future<bool> startListening({
    Function(String)? onResult,
    Function(String)? onPartialResult,
  }) async {
    if (_isRecording) return false;
    
    final hasPermission = await requestPermission();
    if (!hasPermission) return false;
    
    _isRecording = true;
    _lastRecognizedText = '';
    
    if (_speechAvailable) {
      _speech.listen(
        onResult: (result) {
          if (result.finalResult) {
            _lastRecognizedText = result.recognizedWords;
            onResult?.call(result.recognizedWords);
          } else {
            onPartialResult?.call(result.recognizedWords);
          }
        },
        localeId: 'zh_CN',
        listenMode: stt.ListenMode.dictation,
        partialResults: true,
      );
    }
    
    return true;
  }
  
  /// 停止语音识别
  Future<String> stopListening() async {
    if (!_isRecording) return '';
    
    _isRecording = false;
    
    try {
      await _speech.stop();
    } catch (e) {
      print('停止识别失败: $e');
    }
    
    return _lastRecognizedText;
  }
  
  /// 取消
  Future<void> cancel() async {
    if (!_isRecording) return;
    _isRecording = false;
    
    try {
      await _speech.cancel();
    } catch (e) {
      print('取消识别失败: $e');
    }
  }
  
  Future<void> dispose() async {
    await _speech.stop();
  }
}
