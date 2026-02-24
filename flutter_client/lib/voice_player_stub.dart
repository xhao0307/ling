import 'voice_player_interface.dart';

class _StubVoicePlayer implements VoicePlayer {
  @override
  void dispose() {}

  @override
  Future<void> playBase64({
    required String audioBase64,
    required String mimeType,
  }) async {
    throw UnsupportedError('当前平台暂不支持内置语音播放');
  }

  @override
  Future<void> stop() async {}
}

VoicePlayer createVoicePlayerImpl() => _StubVoicePlayer();
