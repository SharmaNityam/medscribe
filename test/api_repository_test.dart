import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:medical_transaction_app/core/repositories/api_repository.dart';

class FixedResponseAdapter implements HttpClientAdapter {
  final int statusCode;
  final String body;

  FixedResponseAdapter(this.statusCode, this.body);

  @override
  Future<ResponseBody> fetch(RequestOptions options, Stream<Uint8List>? requestStream, Future<void>? cancelFuture) async {
    return ResponseBody.fromString(body, statusCode, headers: {
      Headers.contentTypeHeader: [Headers.jsonContentType],
    });
  }

  @override
  void close({bool force = false}) {}
}

ApiRepository repoReturning(int status, String body) => ApiRepository(
      baseUrl: 'https://example.com',
      httpClientAdapter: FixedResponseAdapter(status, body),
    );

void main() {
  late File audioFile;

  setUpAll(() async {
    audioFile = File('${Directory.systemTemp.createTempSync('medscribe_test').path}/chunk.wav');
    await audioFile.writeAsBytes(List.filled(64, 1));
  });

  const sessionNotFound = '{"error":"Session not found"}';

  test('getPresignedUrl maps a 404 "Session not found" to SessionNotFoundException', () {
    final repo = repoReturning(404, sessionNotFound);

    expect(
      repo.getPresignedUrl(sessionId: 'B1', chunkNumber: 0),
      throwsA(isA<SessionNotFoundException>().having((e) => e.sessionId, 'sessionId', 'B1')),
    );
  });

  test('uploadChunk treats a 404 "Session not found" as SessionNotFoundException, not success', () {
    final repo = repoReturning(404, sessionNotFound);

    expect(
      repo.uploadChunk(
        presignedUrl: 'https://example.com/v1/upload-chunk/B1/0',
        filePath: audioFile.path,
        sessionId: 'B1',
      ),
      throwsA(isA<SessionNotFoundException>()),
    );
  });

  test('uploadChunk fails on other 4xx responses', () {
    final repo = repoReturning(400, '{"error":"Empty audio data"}');

    expect(
      repo.uploadChunk(presignedUrl: 'https://example.com/v1/upload-chunk/B1/0', filePath: audioFile.path),
      throwsA(isA<Exception>().having((e) => e, 'type', isNot(isA<SessionNotFoundException>()))),
    );
  });

  test('uploadChunk succeeds on 200', () async {
    final repo = repoReturning(200, '');

    await repo.uploadChunk(presignedUrl: 'https://example.com/v1/upload-chunk/B1/0', filePath: audioFile.path);
  });

  test('notifyChunkUploaded maps a 404 "Session not found" to SessionNotFoundException', () {
    final repo = repoReturning(404, sessionNotFound);

    expect(
      repo.notifyChunkUploaded(
        sessionId: 'B1',
        gcsPath: 'sessions/B1/chunk_0.wav',
        chunkNumber: 0,
        isLast: false,
        totalChunksClient: 1,
      ),
      throwsA(isA<SessionNotFoundException>()),
    );
  });

  test('a 404 for some other reason is not treated as session not found', () {
    final repo = repoReturning(404, '{"error":"Patient not found"}');

    expect(
      repo.getPresignedUrl(sessionId: 'B1', chunkNumber: 0),
      throwsA(isNot(isA<SessionNotFoundException>())),
    );
  });
}
