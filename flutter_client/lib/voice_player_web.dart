// ignore_for_file: deprecated_member_use, avoid_web_libraries_in_flutter

import 'dart:html' as html;

import 'voice_player_interface.dart';

class _WebVoicePlayer implements VoicePlayer {
  html.AudioElement? _audio;

  @override
  Future<void> playBase64({
    required String audioBase64,
    required String mimeType,
  }) async {
    final payload = audioBase64.trim();
    if (payload.isEmpty) {
      throw ArgumentError('语音数据为空');
    }

    final audio = html.AudioElement('data:$mimeType;base64,$payload');
    audio.preload = 'auto';
    audio.controls = false;
    audio.autoplay = false;

    final old = _audio;
    if (old != null) {
      old.pause();
      old.remove();
    }

    _audio = audio;
    await audio.play();
  }

  @override
  Future<void> stop() async {
    final audio = _audio;
    if (audio == null) {
      return;
    }
    audio.pause();
    audio.currentTime = 0;
  }

  @override
  void dispose() {
    final audio = _audio;
    if (audio == null) {
      return;
    }
    audio.pause();
    audio.src = '';
    audio.remove();
    _audio = null;
  }
}

VoicePlayer createVoicePlayerImpl() => _WebVoicePlayer();
