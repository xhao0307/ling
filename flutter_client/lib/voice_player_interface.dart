abstract class VoicePlayer {
  Future<void> playBase64({
    required String audioBase64,
    required String mimeType,
  });

  Future<void> stop();

  void dispose();
}
