import 'dart:io';
import 'package:flutter/material.dart';
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
  
  Future<bool> requestPermission() async {
    final status = await Permission.microphone.request();
    return status.isGranted;
  }
  
  Future<bool> startRecording() async {
    if (_isRecording) return false;
    final hasPermission = await requestPermission();
    if (!hasPermission) return false;
    
    try {
      final tempDir = await Directory.systemTemp.createTemp('voice_');
      final tempPath = '${tempDir.path}/recording_${DateTime.now().millisecondsSinceEpoch}.m4a';
      _currentRecordingPath = tempPath;
      await _recorder.start(
        const RecordConfig(
          encoder: AudioEncoder.aacLc,
          numChannels: 1,
          sampleRate: 16000,
        ),
        path: tempPath,
      );
      _isRecording = true;
      return true;
    } catch (e) {
      _isRecording = false;
      return false;
    }
  }
  
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
  
  Future<void> cancelRecording() async {
    if (!_isRecording) return;
    try {
      await _recorder.stop();
      if (_currentRecordingPath != null) {
        final file = File(_currentRecordingPath!);
        if (await file.exists()) await file.delete();
      }
    } catch (e) {}
    _isRecording = false;
    _currentRecordingPath = null;
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
  
  Future<void> dispose() async {
    await _recorder.dispose();
  }
}
