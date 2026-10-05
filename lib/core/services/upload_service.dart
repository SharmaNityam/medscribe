import 'dart:async';
import 'package:connectivity_plus/connectivity_plus.dart';
import '../models/audio_chunk.dart';
import '../repositories/api_repository.dart';
import '../repositories/local_storage_repository.dart';
import '../config/api_config.dart';
import '../utils/logger.dart';
import '../utils/validation.dart';
import 'session_service.dart';

class UploadService {
  static const int maxAttempts = 5;

  final ApiRepository _apiRepository;
  final LocalStorageRepository _localStorage;
  final SessionService? _sessionService;
  final Connectivity _connectivity;
  final Duration Function(int attempt) _backoff;

  StreamController<UploadProgress>? _progressController;
  bool _isUploading = false;

  final Map<String, int> _sessionChunkCounts = {};
  final Set<String> _uploadingChunks = {};
  final Map<String, Future<String?>> _recreations = {};

  UploadService({
    ApiRepository? apiRepository,
    LocalStorageRepository? localStorage,
    SessionService? sessionService,
    Connectivity? connectivity,
    Duration Function(int attempt)? backoff,
  })  : _apiRepository = apiRepository ?? ApiRepository(),
        _localStorage = localStorage ?? LocalStorageRepository(),
        _sessionService = sessionService,
        _connectivity = connectivity ?? Connectivity(),
        _backoff = backoff ?? ((attempt) => Duration(seconds: 1 << attempt)) {
    _progressController = StreamController<UploadProgress>.broadcast();
    _monitorConnectivity();
  }

  Stream<UploadProgress> get progressStream => _progressController!.stream;

  void _monitorConnectivity() {
    _connectivity.onConnectivityChanged.listen((result) {
      if (result != ConnectivityResult.none && !_isUploading) {
        _processPendingChunks();
      }
    });
  }

  Future<void> uploadChunk(AudioChunk chunk, {bool isLast = false}) async {
    if (_uploadingChunks.contains(chunk.chunkId)) {
      AppLogger.warning('Chunk ${chunk.chunkId} is already being uploaded, skipping');
      return;
    }

    _uploadingChunks.add(chunk.chunkId);

    try {
      AppLogger.debug('Saving chunk ${chunk.chunkId} to local storage for session ${chunk.sessionId}');
      await _localStorage.saveChunk(chunk.copyWith(status: 'pending'));

      final connectivityResult = await _connectivity.checkConnectivity();
      if (connectivityResult == ConnectivityResult.none) {
        _progressController?.add(UploadProgress(
          chunkId: chunk.chunkId,
          status: 'queued',
          message: 'No network connection',
        ));
        return;
      }

      await _uploadWithRetry(chunk, isLast);
    } finally {
      _uploadingChunks.remove(chunk.chunkId);
    }
  }

  Future<void> _uploadWithRetry(AudioChunk chunk, bool isLast) async {
    var current = chunk;
    var recreated = false;
    var attempt = 1;

    while (true) {
      Object error;
      try {
        await _attemptUpload(current, isLast);
        return;
      } on SessionNotFoundException catch (e) {
        if (!recreated && _sessionService != null) {
          recreated = true;
          AppLogger.info('Session not found on backend, recreating session for ${current.sessionId}');
          final newSessionId = await _recreateOnce(current.sessionId, e.sessionId);
          if (newSessionId != null) {
            AppLogger.info('Retrying chunk ${current.chunkId} on backend session $newSessionId');
            continue;
          }
        }
        error = e;
      } catch (e) {
        error = e;
      }

      current = current.copyWith(
        status: 'failed',
        retryCount: current.retryCount + 1,
        errorMessage: attempt >= maxAttempts
            ? 'Max retries reached: $error'
            : error.toString(),
      );
      await _localStorage.saveChunk(current);

      if (attempt >= maxAttempts) {
        _progressController?.add(UploadProgress(
          chunkId: current.chunkId,
          status: 'failed',
          message: 'Max retries reached',
        ));
        AppLogger.error('Chunk ${current.chunkId} failed after $maxAttempts attempts', error);
        return;
      }

      final delay = _backoff(attempt);
      _progressController?.add(UploadProgress(
        chunkId: current.chunkId,
        status: 'failed',
        message: 'Retrying in ${delay.inSeconds}s (attempt $attempt/$maxAttempts)',
      ));
      AppLogger.warning('Chunk ${current.chunkId} upload failed, retrying in ${delay.inSeconds}s: $error');

      await Future.delayed(delay);
      attempt++;
    }
  }

  Future<void> _attemptUpload(AudioChunk chunk, bool isLast) async {
    final backendSessionId = await _backendSessionIdFor(chunk.sessionId);

    final updatedChunk = chunk.copyWith(status: 'uploading');
    await _localStorage.saveChunk(updatedChunk);
    _progressController?.add(UploadProgress(
      chunkId: chunk.chunkId,
      status: 'uploading',
    ));

    final presignedUrlData = await _apiRepository.getPresignedUrl(
      sessionId: backendSessionId,
      chunkNumber: chunk.sequenceNumber,
      mimeType: 'audio/wav',
    );

    String? presignedUrl = Validation.getString(presignedUrlData, 'url');
    final gcsPath = Validation.getString(presignedUrlData, 'gcsPath');
    String? publicUrl = Validation.getString(presignedUrlData, 'publicUrl');

    if (presignedUrl == null) {
      throw Exception('Presigned URL is null');
    }
    if (gcsPath == null) {
      throw Exception('GCS path is null');
    }

    final baseUrl = ApiConfig.getBaseUrlForPlatform();
    try {
      if (presignedUrl.contains('localhost') || presignedUrl.startsWith('http://')) {
        final localhostUri = Uri.parse(presignedUrl);
        final path = localhostUri.path;
        final query = localhostUri.query;
        final fullPath = query.isNotEmpty ? '$path?$query' : path;
        presignedUrl = '$baseUrl$fullPath';
        AppLogger.debug('Fixed presigned URL from ${localhostUri.toString()} to $presignedUrl');
      }
      if (publicUrl != null && (publicUrl.contains('localhost') || publicUrl.startsWith('http://'))) {
        final localhostUri = Uri.parse(publicUrl);
        final path = localhostUri.path;
        final query = localhostUri.query;
        final fullPath = query.isNotEmpty ? '$path?$query' : path;
        publicUrl = '$baseUrl$fullPath';
        AppLogger.debug('Fixed public URL from ${localhostUri.toString()} to $publicUrl');
      }
    } catch (e) {
      AppLogger.warning('Failed to parse base URL: $e');
    }

    await _apiRepository.uploadChunk(
      presignedUrl: presignedUrl!,
      filePath: chunk.filePath,
      sessionId: backendSessionId,
    );

    _sessionChunkCounts[backendSessionId] = (_sessionChunkCounts[backendSessionId] ?? 0) + 1;
    final totalChunks = _sessionChunkCounts[backendSessionId] ?? chunk.sequenceNumber + 1;

    await _apiRepository.notifyChunkUploaded(
      sessionId: backendSessionId,
      gcsPath: gcsPath,
      chunkNumber: chunk.sequenceNumber,
      isLast: isLast,
      totalChunksClient: totalChunks,
      publicUrl: publicUrl,
      mimeType: 'audio/wav',
      model: 'fast',
    );

    await _localStorage.saveChunk(updatedChunk.copyWith(
      status: 'uploaded',
      presignedUrl: presignedUrl,
    ));

    _progressController?.add(UploadProgress(
      chunkId: chunk.chunkId,
      status: 'uploaded',
    ));

    AppLogger.info('Successfully uploaded chunk ${chunk.chunkId} (sequence ${chunk.sequenceNumber})');
  }

  Future<String> _backendSessionIdFor(String localSessionId) async {
    final session = await _localStorage.getSession(localSessionId);
    return session?.uploadSessionId ?? localSessionId;
  }

  Future<String?> _recreateOnce(String localSessionId, String staleBackendId) {
    return _recreations.putIfAbsent(
      localSessionId,
      () => _recreate(localSessionId, staleBackendId),
    );
  }

  Future<String?> _recreate(String localSessionId, String staleBackendId) async {
    try {
      final current = await _backendSessionIdFor(localSessionId);
      if (current != staleBackendId) {
        return current;
      }
      return await _sessionService!.recreateRemoteSession(localSessionId);
    } catch (e) {
      AppLogger.error('Failed to recreate session: $e');
      return null;
    } finally {
      _recreations.remove(localSessionId);
    }
  }

  Future<void> _processPendingChunks() async {
    if (_isUploading) {
      AppLogger.debug('Upload already in progress, skipping');
      return;
    }
    _isUploading = true;

    try {
      final pendingChunks = await _localStorage.getAllPendingChunks();

      if (pendingChunks.isEmpty) {
        AppLogger.debug('No pending chunks to upload');
        return;
      }

      AppLogger.info('Processing ${pendingChunks.length} pending chunks');

      for (final chunk in pendingChunks) {
        try {
          await uploadChunk(chunk);
          await Future.delayed(const Duration(milliseconds: 500));
        } catch (e) {
          AppLogger.error('Error processing chunk ${chunk.chunkId}', e);
        }
      }
    } finally {
      _isUploading = false;
    }
  }

  Future<void> processPendingChunks() => _processPendingChunks();

  Future<void> resumePendingWork() async {
    final requeued = await _localStorage.resetStaleUploads();
    if (requeued > 0) {
      AppLogger.info('Requeued $requeued chunks interrupted mid-upload');
    }
    await _processPendingChunks();
  }

  Future<void> dispose() async {
    await _progressController?.close();
  }
}

class UploadProgress {
  final String chunkId;
  final String status;
  final String? message;

  UploadProgress({
    required this.chunkId,
    required this.status,
    this.message,
  });
}
