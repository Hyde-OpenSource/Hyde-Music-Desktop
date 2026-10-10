import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

/// Shazam audio fingerprint in pure Dart (replaces the native `shazam.so`).
///
/// Input: 16 kHz mono signed 16-bit PCM. Output: the `data:` URI the
/// recognition endpoint expects. The algorithm is the public one documented
/// by the SongRec project: 2048-point Hann FFT every 128 samples, peak
/// spreading in frequency and time, peaks kept per frequency band.
class ShazamSignature {
  static const sampleRate = 16000;
  static const _fftSize = 2048;
  static const _bins = 1025;
  static const _ring = 256;

  final _samples = Float64List(_fftSize);
  int _samplePos = 0;

  final _fft = List.generate(_ring, (_) => Float64List(_bins));
  int _fftPos = 0;
  final _spread = List.generate(_ring, (_) => Float64List(_bins));
  int _spreadPos = 0;
  int _spreadWritten = 0;

  int _numberSamples = 0;

  /// Peaks per band (0: 250–520 Hz, 1: 520–1450, 2: 1450–3500, 3: 3500–5500).
  final _peaks = List.generate(4, (_) => <(int pass, int magnitude, int bin)>[]);

  // numpy.hanning(2050)[1:-1]
  static final Float64List _hann = () {
    final w = Float64List(_fftSize);
    for (var i = 0; i < _fftSize; i++) {
      w[i] = 0.5 - 0.5 * math.cos(2 * math.pi * (i + 1) / 2049);
    }
    return w;
  }();

  // Scratch buffers for the FFT.
  final _re = Float64List(_fftSize);
  final _im = Float64List(_fftSize);
  static final Float64List _cos = () {
    final t = Float64List(_fftSize ~/ 2);
    for (var i = 0; i < t.length; i++) {
      t[i] = math.cos(-2 * math.pi * i / _fftSize);
    }
    return t;
  }();
  static final Float64List _sin = () {
    final t = Float64List(_fftSize ~/ 2);
    for (var i = 0; i < t.length; i++) {
      t[i] = math.sin(-2 * math.pi * i / _fftSize);
    }
    return t;
  }();
  static final Uint16List _reverse = () {
    final r = Uint16List(_fftSize);
    const bits = 11; // log2(2048)
    for (var i = 0; i < _fftSize; i++) {
      var x = i, y = 0;
      for (var b = 0; b < bits; b++) {
        y = (y << 1) | (x & 1);
        x >>= 1;
      }
      r[i] = y;
    }
    return r;
  }();

  /// Feeds PCM samples; call [encode] when done.
  void process(Int16List pcm) {
    _numberSamples += pcm.length;
    for (var at = 0; at + 128 <= pcm.length; at += 128) {
      for (var i = 0; i < 128; i++) {
        _samples[_samplePos] = pcm[at + i].toDouble();
        _samplePos = (_samplePos + 1) & (_fftSize - 1);
      }
      _doFft();
      _doPeakSpreading();
      if (_spreadWritten >= 46) _doPeakRecognition();
    }
  }

  void _doFft() {
    // Oldest sample first, windowed, in bit-reversed order.
    for (var i = 0; i < _fftSize; i++) {
      final v = _samples[(_samplePos + i) & (_fftSize - 1)] * _hann[i];
      _re[_reverse[i]] = v;
    }
    _im.fillRange(0, _fftSize, 0);
    for (var size = 2; size <= _fftSize; size <<= 1) {
      final half = size >> 1;
      final step = _fftSize ~/ size;
      for (var start = 0; start < _fftSize; start += size) {
        for (var k = 0; k < half; k++) {
          final wr = _cos[k * step], wi = _sin[k * step];
          final a = start + k, b = a + half;
          final tr = _re[b] * wr - _im[b] * wi;
          final ti = _re[b] * wi + _im[b] * wr;
          _re[b] = _re[a] - tr;
          _im[b] = _im[a] - ti;
          _re[a] += tr;
          _im[a] += ti;
        }
      }
    }
    final out = _fft[_fftPos];
    for (var i = 0; i < _bins; i++) {
      final m = (_re[i] * _re[i] + _im[i] * _im[i]) / (1 << 17);
      out[i] = m < 0.0000000001 ? 0.0000000001 : m;
    }
    _fftPos = (_fftPos + 1) & (_ring - 1);
  }

  void _doPeakSpreading() {
    final origin = _fft[(_fftPos - 1) & (_ring - 1)];
    final spread = _spread[_spreadPos]..setAll(0, origin);
    for (var pos = 0; pos < _bins; pos++) {
      // Frequency-domain spreading.
      if (pos < 1023) {
        final a = spread[pos], b = spread[pos + 1], c = spread[pos + 2];
        spread[pos] = a > b ? (a > c ? a : c) : (b > c ? b : c);
      }
      // Time-domain spreading into the three earlier frames.
      var maxValue = spread[pos];
      for (final former in const [1, 3, 6]) {
        final f = _spread[(_spreadPos - former) & (_ring - 1)];
        if (f[pos] > maxValue) {
          maxValue = f[pos];
        } else {
          f[pos] = maxValue;
        }
      }
    }
    _spreadPos = (_spreadPos + 1) & (_ring - 1);
    _spreadWritten++;
  }

  static const _neighbours = [-10, -7, -4, -3, 1, 2, 5, 8];
  static const _otherFrames = [-53, -45, 165, 172, 179, 186, 193, 200, 214, 221, 228, 235, 242, 249];

  static double _mag(double v) => math.log(v < 1 / 64 ? 1 / 64 : v) * 1477.3 + 6144;

  void _doPeakRecognition() {
    final fft46 = _fft[(_fftPos - 46) & (_ring - 1)];
    final spread49 = _spread[(_spreadPos - 49) & (_ring - 1)];
    for (var bin = 10; bin < 1015; bin++) {
      final v = fft46[bin];
      if (v < 1 / 64 || v < spread49[bin - 1]) continue;
      var maxNeighbour = 0.0;
      for (final o in _neighbours) {
        final n = spread49[bin + o];
        if (n > maxNeighbour) maxNeighbour = n;
      }
      if (v <= maxNeighbour) continue;
      var maxOther = maxNeighbour;
      for (final o in _otherFrames) {
        final n = _spread[(_spreadPos + o) & (_ring - 1)][bin - 1];
        if (n > maxOther) maxOther = n;
      }
      if (v <= maxOther) continue;

      final pass = _spreadWritten - 46;
      final magnitude = _mag(v);
      final before = _mag(fft46[bin - 1]);
      final after = _mag(fft46[bin + 1]);
      final variation1 = magnitude * 2 - before - after;
      if (variation1 <= 0) continue;
      final variation2 = (after - before) * 32 / variation1;
      final corrected = bin * 64 + variation2;
      final hz = corrected * (sampleRate / 2 / 1024 / 64);
      final int band;
      if (hz < 250) {
        continue;
      } else if (hz < 520) {
        band = 0;
      } else if (hz < 1450) {
        band = 1;
      } else if (hz < 3500) {
        band = 2;
      } else if (hz <= 5500) {
        band = 3;
      } else {
        continue;
      }
      _peaks[band].add((pass, magnitude.toInt(), corrected.toInt()));
    }
  }

  int get peakCount => _peaks.fold(0, (a, b) => a + b.length);

  /// Milliseconds of audio processed.
  int get sampleMs => (_numberSamples * 1000) ~/ sampleRate;

  Uint8List encodeBinary() {
    final contents = BytesBuilder();
    for (var band = 0; band < 4; band++) {
      final peaks = _peaks[band];
      if (peaks.isEmpty) continue;
      final buf = BytesBuilder();
      var pass = 0;
      for (final (p, magnitude, bin) in peaks) {
        if (p - pass >= 255) {
          buf.addByte(0xff);
          buf.add(_u32(p));
          pass = p;
        }
        buf.addByte(p - pass);
        buf.add(_u16(magnitude));
        buf.add(_u16(bin));
        pass = p;
      }
      final bytes = buf.takeBytes();
      contents.add(_u32(0x60030040 + band));
      contents.add(_u32(bytes.length));
      contents.add(bytes);
      contents.add(Uint8List((4 - bytes.length % 4) % 4));
    }
    final body = contents.takeBytes();
    final sizeMinusHeader = body.length + 8;

    final out = BytesBuilder();
    out.add(_u32(0xcafe2580)); // magic1
    out.add(_u32(0)); // crc32 (patched below)
    out.add(_u32(sizeMinusHeader));
    out.add(_u32(0x94119c00)); // magic2
    out.add(Uint8List(12));
    out.add(_u32(3 << 27)); // sample rate id 3 = 16 kHz
    out.add(Uint8List(8));
    out.add(_u32((_numberSamples + sampleRate * 0.24).toInt()));
    out.add(_u32((15 << 19) + 0x40000));
    out.add(_u32(0x40000000));
    out.add(_u32(sizeMinusHeader));
    out.add(body);
    final bytes = out.takeBytes();
    ByteData.sublistView(bytes).setUint32(4, crc32(Uint8List.sublistView(bytes, 8)), Endian.little);
    return bytes;
  }

  String encodeUri() => 'data:audio/vnd.shazam.sig;base64,${base64.encode(encodeBinary())}';

  static Uint8List _u32(int v) => Uint8List(4)..buffer.asByteData().setUint32(0, v & 0xffffffff, Endian.little);
  static Uint8List _u16(int v) => Uint8List(2)..buffer.asByteData().setUint16(0, v & 0xffff, Endian.little);

  static final Uint32List _crcTable = () {
    final t = Uint32List(256);
    for (var n = 0; n < 256; n++) {
      var c = n;
      for (var k = 0; k < 8; k++) {
        c = (c & 1) != 0 ? 0xedb88320 ^ (c >>> 1) : c >>> 1;
      }
      t[n] = c;
    }
    return t;
  }();

  static int crc32(Uint8List data) {
    var c = 0xffffffff;
    for (final b in data) {
      c = _crcTable[(c ^ b) & 0xff] ^ (c >>> 8);
    }
    return (c ^ 0xffffffff) & 0xffffffff;
  }
}
