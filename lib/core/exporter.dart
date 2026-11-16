import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'dart:ui' show Offset, Rect;

import 'package:flutter/foundation.dart';
import 'package:flutter_quick_video_encoder/flutter_quick_video_encoder.dart';
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;

import 'guide_renderer.dart';
import 'models.dart';
import 'storage.dart';

/// Exportação 100% local, sem marca d'água.
class Exporter {
  static Future<ui.Image> _decode(Uint8List bytes) async {
    final codec = await ui.instantiateImageCodec(bytes);
    final frame = await codec.getNextFrame();
    return frame.image;
  }

  /// Renderiza o esboço (papel + os primeiros [count] traços) na escala [scale].
  static Future<ui.Image> renderSketch(Project pr,
      {int? count, double scale = 1}) {
    final size = pr.guide.imageSize;
    final w = (size.width * scale).round();
    final h = (size.height * scale).round();
    final rec = ui.PictureRecorder();
    final canvas = ui.Canvas(rec);
    canvas.scale(scale);
    canvas.drawRect(Offset.zero & size, ui.Paint()..color = ui.Color(pr.paper));
    final list = count == null ? pr.strokes : pr.strokes.take(count).toList();
    paintStrokes(canvas, list);
    return rec.endRecording().toImage(w, h);
  }

  static Future<Uint8List> _png(ui.Image image) async {
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    return data!.buffer.asUint8List();
  }

  /// Imagem final comparativa: referência | esboço, lado a lado.
  static Future<File> comparisonPng(Project pr) async {
    if (pr.strokes.isEmpty) {
      throw StateError('Desenhe algo no decalque antes de exportar.');
    }
    final ref = await _decode(await File(pr.referencePath).readAsBytes());
    const targetH = 1080.0;
    final iw = pr.guide.imageSize.width, ih = pr.guide.imageSize.height;
    final s = targetH / ih;
    final w = iw * s;
    const gap = 24.0, pad = 24.0;
    final totalW = pad * 2 + w * 2 + gap;
    final totalH = targetH + pad * 2;

    final sketch = await renderSketch(pr, scale: s);
    final rec = ui.PictureRecorder();
    final c = ui.Canvas(rec);
    c.drawRect(Rect.fromLTWH(0, 0, totalW, totalH),
        ui.Paint()..color = const ui.Color(0xFF0B0C10));
    final paint = ui.Paint()..filterQuality = ui.FilterQuality.high;
    c.drawImageRect(
      ref,
      Rect.fromLTWH(0, 0, ref.width.toDouble(), ref.height.toDouble()),
      Rect.fromLTWH(pad, pad, w, targetH),
      paint,
    );
    c.drawImage(sketch, Offset(pad + w + gap, pad), paint);
    final out =
        await rec.endRecording().toImage(totalW.round(), totalH.round());
    final bytes = await _png(out);

    final dir = await ProjectStore.instance.exportDir();
    final file = File(p.join(dir.path, 'loomisflow_${pr.id}_comparativo.png'));
    return file.writeAsBytes(bytes, flush: true);
  }

  /// Time-lapse do desenho como GIF animado (compartilha em qualquer app).
  /// [onProgress] recebe 0..1.
  static Future<File> timelapseGif(Project pr,
      {int maxFrames = 48, int width = 480, void Function(double)? onProgress}) async {
    if (pr.strokes.isEmpty) {
      throw StateError('Desenhe algo no decalque antes de exportar.');
    }
    final scale = width / pr.guide.imageSize.width;
    final n = pr.strokes.length;
    final frames = n < maxFrames ? n : maxFrames;
    final raw = <Uint8List>[];
    int fw = 0, fh = 0;
    for (var i = 1; i <= frames; i++) {
      final count = (n * i / frames).ceil();
      final im = await renderSketch(pr, count: count, scale: scale);
      final data = await im.toByteData(format: ui.ImageByteFormat.rawRgba);
      fw = im.width;
      fh = im.height;
      raw.add(data!.buffer.asUint8List());
      onProgress?.call(i / frames * 0.6);
    }
    final gif = await compute(_encodeGif, _GifJob(raw, fw, fh));
    onProgress?.call(1);
    final dir = await ProjectStore.instance.exportDir();
    final file = File(p.join(dir.path, 'loomisflow_${pr.id}_timelapse.gif'));
    return file.writeAsBytes(gif, flush: true);
  }

  /// Time-lapse em MP4 (H.264) pelo codificador nativo do aparelho.
  /// Se o aparelho recusar o codificador, cai para GIF animado.
  static Future<File> timelapse(Project pr,
      {void Function(double)? onProgress}) async {
    try {
      return await timelapseMp4(pr, onProgress: onProgress);
    } on StateError {
      rethrow;
    } catch (_) {
      return timelapseGif(pr, onProgress: onProgress);
    }
  }

  static Future<File> timelapseMp4(Project pr,
      {int maxFrames = 90,
      int width = 720,
      int fps = 12,
      void Function(double)? onProgress}) async {
    if (pr.strokes.isEmpty) {
      throw StateError('Desenhe algo no decalque antes de exportar.');
    }
    final imgW = pr.guide.imageSize.width, imgH = pr.guide.imageSize.height;
    // dimensões múltiplas de 16: os codificadores de hardware exigem isso
    final w = math.max(16, (width ~/ 16) * 16);
    final h = math.max(16, ((w * imgH / imgW) ~/ 16) * 16);
    final dir = await ProjectStore.instance.exportDir();
    final path = p.join(dir.path, 'loomisflow_${pr.id}_timelapse.mp4');
    final out = File(path);
    if (await out.exists()) await out.delete();

    await FlutterQuickVideoEncoder.setup(
      width: w,
      height: h,
      fps: fps,
      videoBitrate: 2500000,
      profileLevel: ProfileLevel.values.firstWhere(
        (v) => v.name == 'any',
        orElse: () => ProfileLevel.values.first,
      ),
      audioChannels: 0,
      audioBitrate: 0,
      sampleRate: 0,
      filepath: path,
    );
    try {
      final n = pr.strokes.length;
      final frames = math.min(n, maxFrames);
      for (var i = 1; i <= frames; i++) {
        final count = (n * i / frames).ceil();
        final im = await _frame(pr, count, w, h);
        final data = await im.toByteData(format: ui.ImageByteFormat.rawRgba);
        final bytes = data!.buffer.asUint8List();
        await FlutterQuickVideoEncoder.appendVideoFrame(bytes);
        if (i == frames) {
          // segura o último quadro por ~1,5 s
          for (var k = 0; k < (fps * 1.5).round(); k++) {
            await FlutterQuickVideoEncoder.appendVideoFrame(bytes);
          }
        }
        onProgress?.call(i / frames * 0.95);
      }
    } finally {
      await FlutterQuickVideoEncoder.finish();
    }
    onProgress?.call(1);
    return out;
  }

  static Future<ui.Image> _frame(Project pr, int count, int w, int h) {
    final size = pr.guide.imageSize;
    final rec = ui.PictureRecorder();
    final canvas = ui.Canvas(rec);
    canvas.scale(w / size.width, h / size.height);
    canvas.drawRect(Offset.zero & size, ui.Paint()..color = ui.Color(pr.paper));
    paintStrokes(canvas, pr.strokes.take(count).toList());
    return rec.endRecording().toImage(w, h);
  }
}

class _GifJob {
  _GifJob(this.frames, this.w, this.h);
  final List<Uint8List> frames;
  final int w, h;
}

Uint8List _encodeGif(_GifJob job) {
  final enc = img.GifEncoder(repeat: 0);
  for (var i = 0; i < job.frames.length; i++) {
    final frame = img.Image.fromBytes(
      width: job.w,
      height: job.h,
      bytes: job.frames[i].buffer,
      numChannels: 4,
    );
    final last = i == job.frames.length - 1;
    enc.addFrame(frame, duration: last ? 200 : 10); // centésimos de segundo
  }
  return enc.finish()!;
}
