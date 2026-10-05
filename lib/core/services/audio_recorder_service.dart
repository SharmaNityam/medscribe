import 'dart:async';
import 'dart:io';
import 'package:flutter/services.dart';
import 'package:record/record.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import '../models/audio_chunk.dart';
import '../utils/logger.dart';
import '../utils/pcm_chunker.dart';

class AudioRecorderService {
  final AudioRecorder _recorder = AudioRecorder();
  final Uuid _uuid = const Uuid();
  static const MethodChannel _channel = MethodChannel('com.example.medical_transaction_app/recording');

  StreamController<double>? _amplitudeController;
  StreamController<AudioChunk>? _chunkController;
  StreamController<bool>? _recordingStateController;

  StreamSubscription<Uint8List>? _audioSubscription;
  Completer<void>? _streamDone;
  PcmChunker? _chunker;
  Future<void> _chunkWrites = Future.value();
  String? _lastChunkPath;
  DateTime _lastAmplitudeAt = DateTime.fromMillisecondsSinceEpoch(0);
  String? _currentSessionId;
  int _currentSequenceNumber = 0;
  bool _isRecording = false;
  bool _isPaused = false;

  Stream<bool>? get recordingStateStream => _recordingStateController?.stream;

  static const int chunkDurationSeconds = 5;
  static const int sampleRate = 44100;
  static const int numChannels = 1;
  static const Duration amplitudeInterval = Duration(milliseconds: 100);

  double _gain = 1.0;

  double get gain => _gain;

  void setGain(double gain) {
    if (gain < 0.0 || gain > 1.0) {
      AppLogger.warning('Gain value $gain out of range, clamping to [0.0, 1.0]');
      _gain = gain.clamp(0.0, 1.0);
    } else {
      _gain = gain;
    }
    AppLogger.debug('Microphone gain set to: $_gain');
  }

  Stream<double>? get amplitudeStream => _amplitudeController?.stream;
  Stream<AudioChunk>? get chunkStream => _chunkController?.stream;

  Future<bool> hasPermission() async {
    return await _recorder.hasPermission();
  }

  Future<bool> requestPermission() async {
    if (await hasPermission()) {
      return true;
    }

    final status = await Permission.microphone.request();
    if (status.isGranted) {
      return true;
    }

    AppLogger.warning('Microphone permission denied');
    return false;
  }

  Future<void> startRecording(String sessionId) async {
    if (_isRecording) {
      throw Exception('Recording already in progress');
    }

    if (!await requestPermission()) {
      throw Exception('Microphone permission denied');
    }

    _currentSessionId = sessionId;
    _currentSequenceNumber = 0;
    _isRecording = true;
    _isPaused = false;
    _lastChunkPath = null;
    _chunkWrites = Future.value();

    _amplitudeController = StreamController<double>.broadcast();
    _chunkController = StreamController<AudioChunk>.broadcast();
    _recordingStateController = StreamController<bool>.broadcast();

    _chunker = PcmChunker(
      sampleRate: sampleRate,
      numChannels: numChannels,
      chunkDuration: const Duration(seconds: chunkDurationSeconds),
    );

    final audioStream = await _recorder.startStream(
      const RecordConfig(
        encoder: AudioEncoder.pcm16bits,
        sampleRate: sampleRate,
        numChannels: numChannels,
        autoGain: false,
        echoCancel: false,
        noiseSuppress: false,
      ),
    );

    _streamDone = Completer<void>();
    _audioSubscription = audioStream.listen(
      _onAudioData,
      onError: (Object e, StackTrace stackTrace) {
        AppLogger.error('Audio stream error', e, stackTrace);
        _chunkController?.addError(e);
      },
      onDone: () {
        if (!(_streamDone?.isCompleted ?? true)) _streamDone!.complete();
      },
    );

    try {
      await WakelockPlus.enable();
      AppLogger.info('Wake lock enabled - recording will continue when screen is locked');
    } catch (e) {
      AppLogger.warning('Failed to enable wake lock: $e');
    }

    if (Platform.isAndroid) {
      try {
        await _channel.invokeMethod('startForegroundService');
        AppLogger.info('Foreground service started for background recording');
      } catch (e) {
        AppLogger.warning('Failed to start foreground service: $e');
      }
    }

    AppLogger.info('Recording started - streaming PCM, ${chunkDurationSeconds}s chunks with no gaps');
    AppLogger.info('Started recording with gain: $_gain');
  }

  void _onAudioData(Uint8List data) {
    final chunker = _chunker;
    if (chunker == null) return;

    final now = DateTime.now();
    if (now.difference(_lastAmplitudeAt) >= amplitudeInterval) {
      _lastAmplitudeAt = now;
      _amplitudeController?.add(PcmChunker.rmsDbfs(data) * _gain);
    }

    for (final pcm in chunker.add(data)) {
      _queueChunk(pcm);
    }
  }

  void _queueChunk(Uint8List pcm) {
    final sessionId = _currentSessionId;
    if (sessionId == null || pcm.isEmpty) return;
    final sequenceNumber = _currentSequenceNumber++;
    final controller = _chunkController;

    _chunkWrites = _chunkWrites.then((_) async {
      try {
        final chunk = await _writeChunk(sessionId, sequenceNumber, pcm);
        _lastChunkPath = chunk.filePath;
        if (controller != null && !controller.isClosed) {
          controller.add(chunk);
          AppLogger.debug('Created chunk ${chunk.chunkId} (sequence $sequenceNumber), size: ${chunk.fileSize} bytes');
        } else {
          AppLogger.warning('Chunk controller is null or closed, chunk not sent');
        }
      } catch (e, stackTrace) {
        AppLogger.error('Error creating chunk', e, stackTrace);
        controller?.addError(e);
      }
    });
  }

  Future<AudioChunk> _writeChunk(String sessionId, int sequenceNumber, Uint8List pcm) async {
    final directory = await getApplicationDocumentsDirectory();
    final filePath = path.join(
      directory.path,
      'recordings',
      sessionId,
      'chunk_${sequenceNumber.toString().padLeft(5, '0')}.wav',
    );
    final file = File(filePath);
    await file.parent.create(recursive: true);
    final wav = PcmChunker.wrapWav(pcm, sampleRate: sampleRate, numChannels: numChannels);
    await file.writeAsBytes(wav, flush: true);

    return AudioChunk(
      chunkId: _uuid.v4(),
      sessionId: sessionId,
      sequenceNumber: sequenceNumber,
      filePath: filePath,
      timestamp: DateTime.now(),
      fileSize: wav.length,
      status: 'pending',
    );
  }

  Future<void> pause() async {
    if (!_isRecording || _isPaused) {
      return;
    }

    _isPaused = true;
    await _recorder.pause();

    _recordingStateController?.add(true);

    if (Platform.isAndroid) {
      try {
        await _channel.invokeMethod('stopForegroundService');
        AppLogger.info('Foreground service stopped (paused)');
      } catch (e) {
        AppLogger.warning('Failed to stop foreground service: $e');
      }
    }

    try {
      await WakelockPlus.disable();
      AppLogger.info('Wake lock disabled (paused)');
    } catch (e) {
      AppLogger.warning('Failed to disable wake lock: $e');
    }
  }

  Future<void> resume() async {
    if (!_isRecording || !_isPaused) {
      return;
    }

    _isPaused = false;
    await _recorder.resume();

    _recordingStateController?.add(false);

    if (Platform.isAndroid) {
      try {
        await _channel.invokeMethod('startForegroundService');
        AppLogger.info('Foreground service started (resumed)');
      } catch (e) {
        AppLogger.warning('Failed to start foreground service: $e');
      }
    }

    // Re-enable wake lock when resuming
    try {
      await WakelockPlus.enable();
      AppLogger.info('Wake lock enabled (resumed)');
    } catch (e) {
        AppLogger.warning('Failed to enable wake lock: $e');
    }

    AppLogger.info('Recording resumed');
  }

  Future<String?> stop() async {
    if (!_isRecording) {
      return null;
    }

    _isRecording = false;
    _isPaused = false;

    _recordingStateController?.add(false);

    if (Platform.isAndroid) {
      try {
        await _channel.invokeMethod('stopForegroundService');
        AppLogger.info('Foreground service stopped');
      } catch (e) {
        AppLogger.warning('Failed to stop foreground service: $e');
      }
    }

    try {
      await WakelockPlus.disable();
      AppLogger.info('Wake lock disabled');
    } catch (e) {
      AppLogger.warning('Failed to disable wake lock: $e');
    }

    await _recorder.stop();
    try {
      await _streamDone?.future.timeout(const Duration(seconds: 2));
    } on TimeoutException {
      AppLogger.warning('Audio stream did not close within 2s, flushing what was received');
    }
    await _audioSubscription?.cancel();
    _audioSubscription = null;

    final remainder = _chunker?.flush();
    if (remainder != null && remainder.isNotEmpty) {
      AppLogger.info('Creating final chunk (${remainder.length} bytes of audio) for session $_currentSessionId');
      _queueChunk(remainder);
    }
    await _chunkWrites;
    await Future.delayed(const Duration(milliseconds: 300));

    final path = _lastChunkPath;

    // Cleanup
    _currentSessionId = null;
    _currentSequenceNumber = 0;
    _chunker = null;

    await _amplitudeController?.close();
    await _chunkController?.close();
    _amplitudeController = null;
    _chunkController = null;

    return path;
  }

  Future<void> dispose() async {
    if (_isRecording) {
      await stop();
    }

    try {
      await WakelockPlus.disable();
      AppLogger.debug('Wake lock disabled on dispose');
    } catch (e) {
      AppLogger.debug('Error disabling wake lock on dispose: $e');
    }

    await _audioSubscription?.cancel();
    await _recorder.dispose();
    await _amplitudeController?.close();
    await _chunkController?.close();
    await _recordingStateController?.close();
    _amplitudeController = null;
    _chunkController = null;
    _recordingStateController = null;
  }

  bool get isRecording => _isRecording;
  bool get isPaused => _isPaused;
}
