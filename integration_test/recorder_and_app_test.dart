import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:medical_transaction_app/core/di/service_locator.dart';
import 'package:medical_transaction_app/core/models/audio_chunk.dart';
import 'package:medical_transaction_app/core/services/audio_recorder_service.dart';
import 'package:medical_transaction_app/core/services/upload_service.dart';
import 'package:medical_transaction_app/features/settings/theme_language_provider.dart';
import 'package:medical_transaction_app/main.dart';
import 'package:provider/provider.dart';

const bytesPerSecond = AudioRecorderService.sampleRate * AudioRecorderService.numChannels * 2;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('streaming recorder writes gapless 5 second WAV chunks', (tester) async {
    final recorder = AudioRecorderService();
    final chunks = <AudioChunk>[];
    final amplitudes = <double>[];

    await tester.runAsync(() async {
      await recorder.startRecording('it-session');
      recorder.chunkStream!.listen(chunks.add);
      recorder.amplitudeStream!.listen(amplitudes.add);

      final watch = Stopwatch()..start();
      await Future.delayed(const Duration(milliseconds: 6000));
      await recorder.pause();
      final pausedAt = watch.elapsedMilliseconds;
      await Future.delayed(const Duration(seconds: 2));
      await recorder.resume();
      final resumedAt = watch.elapsedMilliseconds;
      await Future.delayed(const Duration(milliseconds: 5500));
      final stoppedAt = watch.elapsedMilliseconds;
      await recorder.stop();

      final recordedMs = pausedAt + (stoppedAt - resumedAt);
      debugPrint('IT recorded ${recordedMs}ms of audio (paused ${resumedAt - pausedAt}ms), '
          '${chunks.length} chunks, ${amplitudes.length} amplitude samples');

      expect(chunks.length, greaterThanOrEqualTo(3));
      expect(chunks.map((c) => c.sequenceNumber).toList(), List.generate(chunks.length, (i) => i));

      var totalPcmBytes = 0;
      for (final chunk in chunks) {
        final bytes = await File(chunk.filePath).readAsBytes();
        final header = ByteData.sublistView(bytes, 0, 44);
        expect(String.fromCharCodes(bytes.sublist(0, 4)), 'RIFF');
        expect(String.fromCharCodes(bytes.sublist(8, 12)), 'WAVE');
        expect(header.getUint32(24, Endian.little), AudioRecorderService.sampleRate);
        expect(header.getUint32(40, Endian.little), bytes.length - 44);
        totalPcmBytes += bytes.length - 44;
        debugPrint('IT chunk ${chunk.sequenceNumber}: ${bytes.length - 44} PCM bytes '
            '(${((bytes.length - 44) / bytesPerSecond).toStringAsFixed(3)}s)');
      }

      for (final chunk in chunks.take(chunks.length - 1)) {
        expect(await File(chunk.filePath).length(), 44 + 5 * bytesPerSecond);
      }

      final audioSeconds = totalPcmBytes / bytesPerSecond;
      debugPrint('IT total audio ${audioSeconds.toStringAsFixed(3)}s vs recording time ${(recordedMs / 1000).toStringAsFixed(3)}s');
      expect(audioSeconds, closeTo(recordedMs / 1000, 0.6));
      expect(amplitudes, isNotEmpty);
    });

    await recorder.dispose();
  });

  testWidgets('app starts with get_it services and switches English to Hindi', (tester) async {
    setupServiceLocator();
    expect(getIt.isRegistered<UploadService>(), isTrue);
    expect(identical(getIt<UploadService>(), getIt<UploadService>()), isTrue);

    await tester.pumpWidget(const MyApp());
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('Medical Transaction App'), findsWidgets);

    final context = tester.element(find.byType(HomeScreen));
    await Provider.of<ThemeLanguageProvider>(context, listen: false).setLanguage('hi');
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('मेडिकल ट्रांजैक्शन ऐप'), findsWidgets);
    expect(find.text('Medical Transaction App'), findsNothing);

    await Provider.of<ThemeLanguageProvider>(context, listen: false).setLanguage('en');
    await tester.pump(const Duration(milliseconds: 500));
  });
}
