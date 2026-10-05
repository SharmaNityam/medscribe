import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:medical_transaction_app/core/models/audio_chunk.dart';
import 'package:medical_transaction_app/core/models/session.dart';
import 'package:medical_transaction_app/core/repositories/api_repository.dart';
import 'package:medical_transaction_app/core/repositories/local_storage_repository.dart';
import 'package:medical_transaction_app/core/services/session_service.dart';
import 'package:medical_transaction_app/core/services/upload_service.dart';

class FakeApiRepository implements ApiRepository {
  final Set<String> knownSessions;
  int putFailuresRemaining = 0;
  int putCalls = 0;
  int createCalls = 0;
  int _nextSessionNumber = 2;
  final List<String> uploadedTo = [];

  FakeApiRepository({Set<String>? knownSessions}) : knownSessions = knownSessions ?? {'B1'};

  @override
  Future<Map<String, dynamic>> createUploadSession({
    required String userId,
    String? patientId,
    String? patientName,
    String? templateId,
  }) async {
    createCalls++;
    await Future.delayed(const Duration(milliseconds: 10));
    final id = 'B${_nextSessionNumber++}';
    knownSessions.add(id);
    return {'id': id};
  }

  @override
  Future<Map<String, dynamic>> getPresignedUrl({
    required String sessionId,
    required int chunkNumber,
    String mimeType = 'audio/wav',
  }) async {
    await Future<void>.delayed(Duration.zero);
    if (!knownSessions.contains(sessionId)) throw SessionNotFoundException(sessionId);
    return {
      'url': 'https://example.com/v1/upload-chunk/$sessionId/$chunkNumber',
      'gcsPath': 'sessions/$sessionId/chunk_$chunkNumber.wav',
    };
  }

  @override
  Future<void> uploadChunk({
    required String presignedUrl,
    required String filePath,
    String sessionId = '',
  }) async {
    putCalls++;
    if (putFailuresRemaining > 0) {
      putFailuresRemaining--;
      throw Exception('network down');
    }
    if (!knownSessions.contains(sessionId)) throw SessionNotFoundException(sessionId);
  }

  @override
  Future<void> notifyChunkUploaded({
    required String sessionId,
    required String gcsPath,
    required int chunkNumber,
    required bool isLast,
    required int totalChunksClient,
    String? publicUrl,
    String mimeType = 'audio/wav',
    String? selectedTemplate,
    String? selectedTemplateId,
    String model = 'fast',
  }) async {
    uploadedTo.add(sessionId);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class FakeLocalStorage implements LocalStorageRepository {
  final Map<String, RecordingSession> sessions = {};
  final Map<String, AudioChunk> chunks = {};
  final Map<String, List<String>> statusHistory = {};

  @override
  Future<void> saveSession(RecordingSession session) async => sessions[session.sessionId] = session;

  @override
  Future<RecordingSession?> getSession(String sessionId) async => sessions[sessionId];

  @override
  Future<void> updateSession(RecordingSession session) async => sessions[session.sessionId] = session;

  @override
  Future<void> saveChunk(AudioChunk chunk) async {
    chunks[chunk.chunkId] = chunk;
    statusHistory.putIfAbsent(chunk.chunkId, () => []).add(chunk.status);
  }

  @override
  Future<List<AudioChunk>> getAllPendingChunks() async {
    final pending = chunks.values.where((c) => c.status == 'pending' || c.status == 'failed').toList();
    pending.sort((a, b) => a.sequenceNumber.compareTo(b.sequenceNumber));
    return pending;
  }

  @override
  Future<int> resetStaleUploads() async {
    var count = 0;
    for (final c in chunks.values.where((c) => c.status == 'uploading').toList()) {
      chunks[c.chunkId] = c.copyWith(status: 'pending');
      count++;
    }
    return count;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class FakeConnectivity implements Connectivity {
  ConnectivityResult result;

  FakeConnectivity([this.result = ConnectivityResult.wifi]);

  @override
  Future<ConnectivityResult> checkConnectivity() async => result;

  @override
  Stream<ConnectivityResult> get onConnectivityChanged => const Stream.empty();

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

AudioChunk makeChunk(String id, {int sequence = 0, String status = 'pending'}) => AudioChunk(
      chunkId: id,
      sessionId: 'L',
      sequenceNumber: sequence,
      filePath: '/tmp/$id.wav',
      timestamp: DateTime(2026),
      status: status,
    );

void main() {
  late FakeApiRepository api;
  late FakeLocalStorage storage;
  late FakeConnectivity connectivity;
  late UploadService service;
  final backoffs = <Duration>[];

  setUp(() {
    api = FakeApiRepository();
    storage = FakeLocalStorage();
    connectivity = FakeConnectivity();
    backoffs.clear();
    storage.sessions['L'] = RecordingSession(
      sessionId: 'L',
      userId: 'user_123',
      startTime: DateTime(2026),
      uploadSessionId: 'B1',
    );
    service = UploadService(
      apiRepository: api,
      localStorage: storage,
      sessionService: SessionService(apiRepository: api, localStorage: storage),
      connectivity: connectivity,
      backoff: (attempt) {
        backoffs.add(Duration(seconds: 1 << attempt));
        return Duration.zero;
      },
    );
  });

  test('successful upload moves through pending, uploading, uploaded', () async {
    await service.uploadChunk(makeChunk('c1'));

    expect(storage.statusHistory['c1'], ['pending', 'uploading', 'uploaded']);
    expect(api.uploadedTo, ['B1']);
  });

  test('a transient failure is retried in-process until it succeeds', () async {
    api.putFailuresRemaining = 2;

    await service.uploadChunk(makeChunk('c1'));

    expect(api.putCalls, 3);
    expect(storage.chunks['c1']!.status, 'uploaded');
    expect(storage.chunks['c1']!.retryCount, 2);
    expect(backoffs, [const Duration(seconds: 2), const Duration(seconds: 4)]);
  });

  test('a chunk that keeps failing stops after maxAttempts and gets a fresh budget next pass', () async {
    api.putFailuresRemaining = 1000;

    await service.uploadChunk(makeChunk('c1'));
    expect(api.putCalls, UploadService.maxAttempts);
    expect(storage.chunks['c1']!.status, 'failed');
    expect(storage.chunks['c1']!.errorMessage, startsWith('Max retries reached'));

    api.putFailuresRemaining = 0;
    await service.processPendingChunks();
    expect(storage.chunks['c1']!.status, 'uploaded');
  });

  test('session not found recreates the backend session and keeps the local ID', () async {
    api.knownSessions.clear();

    await service.uploadChunk(makeChunk('c1'));

    expect(api.createCalls, 1);
    expect(storage.sessions['L']!.uploadSessionId, 'B2');
    expect(storage.sessions.keys, ['L']);
    expect(storage.chunks['c1']!.sessionId, 'L');
    expect(storage.chunks['c1']!.status, 'uploaded');
    expect(api.uploadedTo, ['B2']);
  });

  test('chunks failing with session not found together share one recreation', () async {
    api.knownSessions.clear();

    await Future.wait([
      service.uploadChunk(makeChunk('c1', sequence: 0)),
      service.uploadChunk(makeChunk('c2', sequence: 1)),
      service.uploadChunk(makeChunk('c3', sequence: 2)),
    ]);

    expect(api.createCalls, 1);
    expect(api.uploadedTo, everyElement('B2'));
    expect(storage.chunks.values.map((c) => c.status), everyElement('uploaded'));
  });

  test('with no network the chunk is queued and nothing is sent', () async {
    connectivity.result = ConnectivityResult.none;

    await service.uploadChunk(makeChunk('c1'));

    expect(api.putCalls, 0);
    expect(storage.chunks['c1']!.status, 'pending');
  });

  test('resumePendingWork uploads chunks interrupted mid-upload by an app kill', () async {
    storage.chunks['c1'] = makeChunk('c1', status: 'uploading');
    storage.chunks['c2'] = makeChunk('c2', sequence: 1, status: 'failed');

    await service.resumePendingWork();

    expect(storage.chunks['c1']!.status, 'uploaded');
    expect(storage.chunks['c2']!.status, 'uploaded');
  });

  test('the same chunk is not uploaded twice concurrently', () async {
    final chunk = makeChunk('c1');

    await Future.wait([service.uploadChunk(chunk), service.uploadChunk(chunk)]);

    expect(api.putCalls, 1);
  });
}
