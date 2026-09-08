import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_tts/flutter_tts.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';

/// Recording the meal, and reading the answer back.
///
/// Behind an interface for the same reason purchases are: the screens should be
/// testable without a microphone, and a test that needs a real one is a test
/// nobody runs.
abstract class VoiceService {
  /// Whether the user has already granted the microphone.
  Future<bool> hasPermission();

  Future<void> startRecording();

  /// The recording, or null if nothing usable was captured. Always safe to call
  /// even if recording never started.
  Future<VoiceClip?> stopRecording();

  /// Throws nothing: a failure here is a silent one, never an error in front of
  /// someone who is mid-sentence.
  Future<void> speak(String text);

  Future<void> stopSpeaking();

  Future<void> dispose();
}

class VoiceClip {
  const VoiceClip({required this.bytes, required this.mimeType});

  final Uint8List bytes;
  final String mimeType;
}

class DeviceVoiceService implements VoiceService {
  DeviceVoiceService({AudioRecorder? recorder, FlutterTts? tts})
      : _recorder = recorder ?? AudioRecorder(),
        _tts = tts ?? FlutterTts();

  final AudioRecorder _recorder;
  final FlutterTts _tts;

  /// Where the current clip is being written. Deleted the moment it has been
  /// read into memory — a recording of someone's dinner has no business
  /// outliving the request it was made for.
  String? _path;

  bool _configured = false;

  @override
  Future<bool> hasPermission() => _recorder.hasPermission();

  @override
  Future<void> startRecording() async {
    final dir = await getTemporaryDirectory();
    final path = '${dir.path}/meal_${DateTime.now().millisecondsSinceEpoch}.m4a';
    _path = path;
    await _recorder.start(
      // Mono at 16 kHz: speech, not music. Small enough to send over a phone
      // connection without a wait, and all the model needs.
      const RecordConfig(
        encoder: AudioEncoder.aacLc,
        numChannels: 1,
        sampleRate: 16000,
        bitRate: 32000,
      ),
      path: path,
    );
  }

  @override
  Future<VoiceClip?> stopRecording() async {
    if (_path == null) return null;
    final file = File(_path!);
    _path = null;

    try {
      await _recorder.stop();
      if (!file.existsSync()) return null;
      final bytes = await file.readAsBytes();
      // Too short to be a sentence: a mis-tap rather than a meal.
      if (bytes.length < 2048) return null;
      return VoiceClip(bytes: bytes, mimeType: 'audio/mp4');
    } finally {
      // In a finally, not only on success: an abandoned recording is exactly
      // the one that should not be left on the disk.
      if (file.existsSync()) {
        try {
          await file.delete();
        } catch (_) {
          // Nothing useful to do, and nothing worth telling the user.
        }
      }
    }
  }

  @override
  Future<void> speak(String text) async {
    if (text.trim().isEmpty) return;
    try {
      if (!_configured) {
        await _tts.setSpeechRate(0.48);
        await _tts.setPitch(1.0);
        await _tts.awaitSpeakCompletion(true);
        _configured = true;
      }
      await _tts.stop();
      await _tts.speak(text);
    } catch (_) {
      // A phone with no speech engine still gets the words on screen.
    }
  }

  @override
  Future<void> stopSpeaking() async {
    try {
      await _tts.stop();
    } catch (_) {
      // Already quiet.
    }
  }

  @override
  Future<void> dispose() async {
    await stopSpeaking();
    await _recorder.dispose();
  }
}
