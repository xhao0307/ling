import 'voice_player_interface.dart';
import 'voice_player_stub.dart' if (dart.library.html) 'voice_player_web.dart';

export 'voice_player_interface.dart';

VoicePlayer createVoicePlayer() => createVoicePlayerImpl();
