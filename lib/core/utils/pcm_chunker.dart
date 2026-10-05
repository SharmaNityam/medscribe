import 'dart:math' as math;
import 'dart:typed_data';

class PcmChunker {
  static const int bytesPerSample = 2;

  final int sampleRate;
  final int numChannels;
  final Duration chunkDuration;
  final BytesBuilder _buffer = BytesBuilder();

  PcmChunker({
    required this.sampleRate,
    required this.numChannels,
    required this.chunkDuration,
  });

  int get frameSize => numChannels * bytesPerSample;

  int get bytesPerChunk => sampleRate * chunkDuration.inMilliseconds ~/ 1000 * frameSize;

  int get bufferedBytes => _buffer.length;

  List<Uint8List> add(Uint8List data) {
    _buffer.add(data);
    final chunks = <Uint8List>[];
    while (_buffer.length >= bytesPerChunk) {
      final all = _buffer.takeBytes();
      chunks.add(Uint8List.fromList(Uint8List.sublistView(all, 0, bytesPerChunk)));
      _buffer.add(Uint8List.sublistView(all, bytesPerChunk));
    }
    return chunks;
  }

  Uint8List flush() {
    final all = _buffer.takeBytes();
    final usable = all.length - all.length % frameSize;
    return Uint8List.fromList(Uint8List.sublistView(all, 0, usable));
  }

  static Uint8List wrapWav(Uint8List pcm, {required int sampleRate, required int numChannels}) {
    final byteRate = sampleRate * numChannels * bytesPerSample;
    final header = ByteData(44)
      ..setUint32(0, 0x52494646, Endian.big)
      ..setUint32(4, 36 + pcm.length, Endian.little)
      ..setUint32(8, 0x57415645, Endian.big)
      ..setUint32(12, 0x666d7420, Endian.big)
      ..setUint32(16, 16, Endian.little)
      ..setUint16(20, 1, Endian.little)
      ..setUint16(22, numChannels, Endian.little)
      ..setUint32(24, sampleRate, Endian.little)
      ..setUint32(28, byteRate, Endian.little)
      ..setUint16(32, numChannels * bytesPerSample, Endian.little)
      ..setUint16(34, bytesPerSample * 8, Endian.little)
      ..setUint32(36, 0x64617461, Endian.big)
      ..setUint32(40, pcm.length, Endian.little);
    return (BytesBuilder(copy: false)
          ..add(header.buffer.asUint8List())
          ..add(pcm))
        .takeBytes();
  }

  static double rmsDbfs(Uint8List pcm) {
    final samples = pcm.length ~/ bytesPerSample;
    if (samples == 0) return -160.0;
    final data = ByteData.sublistView(pcm);
    var sumSquares = 0.0;
    for (var i = 0; i < samples; i++) {
      final s = data.getInt16(i * bytesPerSample, Endian.little);
      sumSquares += s * s;
    }
    final rms = math.sqrt(sumSquares / samples);
    if (rms == 0) return -160.0;
    return 20 * math.log(rms / 32768) / math.ln10;
  }
}
