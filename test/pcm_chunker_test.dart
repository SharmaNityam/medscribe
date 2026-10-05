import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:medical_transaction_app/core/utils/pcm_chunker.dart';

Uint8List noise(int length, Random random) =>
    Uint8List.fromList(List.generate(length, (_) => random.nextInt(256)));

Uint8List constantSamples(int count, int value) {
  final data = ByteData(count * 2);
  for (var i = 0; i < count; i++) {
    data.setInt16(i * 2, value, Endian.little);
  }
  return data.buffer.asUint8List();
}

void main() {
  group('PcmChunker', () {
    final chunker = PcmChunker(sampleRate: 44100, numChannels: 1, chunkDuration: const Duration(seconds: 5));

    test('a 5 second mono 44.1 kHz chunk is 441000 bytes', () {
      expect(chunker.bytesPerChunk, 441000);
    });

    test('no audio is lost or duplicated across chunk boundaries', () {
      final c = PcmChunker(sampleRate: 44100, numChannels: 1, chunkDuration: const Duration(seconds: 5));
      final random = Random(42);
      final input = BytesBuilder();
      final output = BytesBuilder();
      final chunks = <Uint8List>[];

      var fed = 0;
      while (fed < 441000 * 2 + 123457) {
        final packet = noise(random.nextInt(9000) + 1, random);
        input.add(packet);
        fed += packet.length;
        chunks.addAll(c.add(packet));
      }
      for (final chunk in chunks) {
        output.add(chunk);
      }
      final remainder = c.flush();
      output.add(remainder);

      final inBytes = input.takeBytes();
      final outBytes = output.takeBytes();
      expect(chunks, hasLength(2));
      expect(chunks.every((chunk) => chunk.length == 441000), isTrue);
      expect(outBytes.length, inBytes.length - inBytes.length % 2);
      expect(outBytes, Uint8List.sublistView(inBytes, 0, outBytes.length));
    });

    test('packets that split a sample in half are reassembled', () {
      final c = PcmChunker(sampleRate: 4, numChannels: 1, chunkDuration: const Duration(seconds: 1));
      expect(c.add(Uint8List.fromList([1, 2, 3])), isEmpty);
      final chunks = c.add(Uint8List.fromList([4, 5, 6, 7, 8, 9]));
      expect(chunks.single, [1, 2, 3, 4, 5, 6, 7, 8]);
      expect(c.flush(), isEmpty);
    });

    test('flush drops a trailing half sample and empties the buffer', () {
      final c = PcmChunker(sampleRate: 44100, numChannels: 1, chunkDuration: const Duration(seconds: 5));
      c.add(Uint8List.fromList([1, 2, 3, 4, 5]));
      expect(c.flush(), [1, 2, 3, 4]);
      expect(c.bufferedBytes, 0);
    });
  });

  group('wrapWav', () {
    test('writes a valid 44-byte PCM header', () {
      final pcm = constantSamples(100, 1000);
      final wav = PcmChunker.wrapWav(pcm, sampleRate: 44100, numChannels: 1);
      final header = ByteData.sublistView(wav, 0, 44);

      expect(wav.length, 44 + pcm.length);
      expect(String.fromCharCodes(wav.sublist(0, 4)), 'RIFF');
      expect(header.getUint32(4, Endian.little), 36 + pcm.length);
      expect(String.fromCharCodes(wav.sublist(8, 16)), 'WAVEfmt ');
      expect(header.getUint16(20, Endian.little), 1);
      expect(header.getUint16(22, Endian.little), 1);
      expect(header.getUint32(24, Endian.little), 44100);
      expect(header.getUint32(28, Endian.little), 88200);
      expect(header.getUint16(32, Endian.little), 2);
      expect(header.getUint16(34, Endian.little), 16);
      expect(String.fromCharCodes(wav.sublist(36, 40)), 'data');
      expect(header.getUint32(40, Endian.little), pcm.length);
      expect(wav.sublist(44), pcm);
    });
  });

  group('rmsDbfs', () {
    test('silence is -160 dBFS', () {
      expect(PcmChunker.rmsDbfs(constantSamples(100, 0)), -160.0);
      expect(PcmChunker.rmsDbfs(Uint8List(0)), -160.0);
    });

    test('full scale is about 0 dBFS and half scale about -6 dBFS', () {
      expect(PcmChunker.rmsDbfs(constantSamples(100, 32767)), closeTo(0, 0.01));
      expect(PcmChunker.rmsDbfs(constantSamples(100, 16384)), closeTo(-6.02, 0.05));
    });
  });
}
