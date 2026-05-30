import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;
import 'package:record/record.dart';
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

/// 语音服务 — 真实语音识别 + 录音
class VoiceService {
  final stt.SpeechToText _speech = stt.SpeechToText();
  final AudioRecorder _recorder = AudioRecorder();
  final Uuid _uuid = const Uuid();
  
  bool _isRecording = false;
  bool _speechAvailable = false;
  String? _currentRecordingPath;
  
  bool get isRecording => _isRecording;
  bool get speechAvailable => _speechAvailable;
  
  /// 初始化语音识别
  Future<bool> init() async {
    _speechAvailable = await _speech.initialize(
      onError: (error) => debugPrint('语音识别错误: $error'),
      onStatus: (status) => debugPrint('语音识别状态: $status'),
    );
    return _speechAvailable;
  }
  
  /// 请求权限
  Future<bool> requestPermission() async {
    final micStatus = await Permission.microphone.request();
    return micStatus.isGranted;
  }
  
  /// 开始录音 + 语音识别
  /// 返回 Stream 识别结果，录音文件保存在本地
  Future<String?> startRecordingAndListen({
    Function(String)? onResult,
    Function(String)? onPartialResult,
  }) async {
    if (_isRecording) return null;
    
    final hasPermission = await requestPermission();
    if (!hasPermission) return null;
    
    // 准备录音文件路径
    final dir = await getApplicationDocumentsDirectory();
    final filename = 'voice_${_uuid.v4()}.m4a';
    _currentRecordingPath = '${dir.path}/voices/$filename';
    
    // 确保目录存在
    final voiceDir = Directory('${dir.path}/voices');
    if (!await voiceDir.exists()) {
      await voiceDir.create(recursive: true);
    }
    
    _isRecording = true;
    
    // 同时启动录音和语音识别
    try {
      // 启动录音
      await _recorder.start(
        const RecordConfig(
          encoder: AudioEncoder.aacLc,
          numChannels: 1,
          sampleRate: 16000,
        ),
        path: _currentRecordingPath!,
      );
      
      // 启动语音识别
      if (_speechAvailable) {
        _speech.listen(
          onResult: (result) {
            if (result.finalResult) {
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
    } catch (e) {
      debugPrint('录音启动失败: $e');
      _isRecording = false;
      return null;
    }
    
    return _currentRecordingPath;
  }
  
  /// 停止录音 + 语音识别
  /// 返回 {text, voicePath}
  Future<Map<String, String?>> stopRecording() async {
    if (!_isRecording) return {'text': null, 'voicePath': null};
    
    _isRecording = false;
    
    String? recognizedText;
    String? voicePath;
    
    try {
      // 停止语音识别
      await _speech.stop();
      recognizedText = _speech.lastRecognizedWords;
      
      // 停止录音
      voicePath = await _recorder.stop();
    } catch (e) {
      debugPrint('停止录音失败: $e');
    }
    
    _currentRecordingPath = null;
    
    return {
      'text': recognizedText?.isNotEmpty == true ? recognizedText : null,
      'voicePath': voicePath,
    };
  }
  
  /// 仅录音（不识别），用于录制语音标签
  Future<String?> startRecordingOnly() async {
    if (_isRecording) return null;
    
    final hasPermission = await requestPermission();
    if (!hasPermission) return null;
    
    final dir = await getApplicationDocumentsDirectory();
    final filename = 'tag_${_uuid.v4()}.m4a';
    _currentRecordingPath = '${dir.path}/voices/$filename';
    
    final voiceDir = Directory('${dir.path}/voices');
    if (!await voiceDir.exists()) {
      await voiceDir.create(recursive: true);
    }
    
    _isRecording = true;
    
    try {
      await _recorder.start(
        const RecordConfig(
          encoder: AudioEncoder.aacLc,
          numChannels: 1,
          sampleRate: 16000,
        ),
        path: _currentRecordingPath!,
      );
    } catch (e) {
      debugPrint('录音启动失败: $e');
      _isRecording = false;
      return null;
    }
    
    return _currentRecordingPath;
  }
  
  /// 停止纯录音
  Future<String?> stopRecordingOnly() async {
    if (!_isRecording) return null;
    _isRecording = false;
    
    try {
      final path = await _recorder.stop();
      _currentRecordingPath = null;
      return path;
    } catch (e) {
      debugPrint('停止录音失败: $e');
      return null;
    }
  }
  
  /// 取消录音
  Future<void> cancelRecording() async {
    if (!_isRecording) return;
    _isRecording = false;
    
    try {
      await _speech.cancel();
      await _recorder.stop();
      
      // 删除录音文件
      if (_currentRecordingPath != null) {
        final file = File(_currentRecordingPath!);
        if (await file.exists()) {
          await file.delete();
        }
      }
    } catch (e) {
      debugPrint('取消录音失败: $e');
    }
    
    _currentRecordingPath = null;
  }
  
  Future<void> dispose() async {
    await _speech.stop();
    await _recorder.dispose();
  }
}
