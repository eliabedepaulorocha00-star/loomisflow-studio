import 'dart:typed_data';

import 'package:image/image.dart' as img;

/// Corrige a orientação EXIF, limita o lado maior a 1600 px e devolve JPEG.
/// Função de topo (sem estado) para poder rodar com `compute`.
Uint8List normalizeImage(Uint8List raw) {
  var im = img.decodeImage(raw);
  if (im == null) throw const FormatException('Imagem inválida');
  im = img.bakeOrientation(im);
  const maxSide = 1600;
  if (im.width > maxSide || im.height > maxSide) {
    im = im.width >= im.height
        ? img.copyResize(im, width: maxSide)
        : img.copyResize(im, height: maxSide);
  }
  return Uint8List.fromList(img.encodeJpg(im, quality: 90));
}

/// Mapa de valores (luz/sombra) 100% local: posteriza a luminância em 3 níveis.
/// Devolve um PNG RGBA 256 px de largura (sombra forte, meio-tom, luz = transparente).
Uint8List buildShadingPng(Uint8List jpeg) {
  var im = img.decodeImage(jpeg);
  if (im == null) throw const FormatException('Imagem inválida');
  im = img.copyResize(im, width: 256);
  im = img.grayscale(im);
  im = img.gaussianBlur(im, radius: 3);

  final hist = List<int>.filled(256, 0);
  for (final px in im) {
    hist[px.luminance.round().clamp(0, 255)]++;
  }
  final total = im.width * im.height;
  int percentile(double q) {
    var acc = 0;
    for (var i = 0; i < 256; i++) {
      acc += hist[i];
      if (acc >= total * q) return i;
    }
    return 255;
  }

  final t1 = percentile(0.28);
  final t2 = percentile(0.58);

  final out = img.Image(width: im.width, height: im.height, numChannels: 4);
  for (var y = 0; y < im.height; y++) {
    for (var x = 0; x < im.width; x++) {
      final l = im.getPixel(x, y).luminance;
      if (l <= t1) {
        out.setPixelRgba(x, y, 110, 140, 255, 150); // sombra
      } else if (l <= t2) {
        out.setPixelRgba(x, y, 110, 140, 255, 70); // meio-tom
      } else {
        out.setPixelRgba(x, y, 0, 0, 0, 0); // luz
      }
    }
  }
  return Uint8List.fromList(img.encodePng(out));
}

/// Devolve a imagem com 25% de margem cinza em cada lado (JPEG). O detector de
/// pose acha melhor corpos cortados nas bordas quando há espaço em volta.
Uint8List padForPose(Uint8List jpeg) {
  final src = img.decodeImage(jpeg);
  if (src == null) throw const FormatException('Imagem inválida');
  final padX = (src.width * 0.25).round();
  final padY = (src.height * 0.25).round();
  final out = img.Image(width: src.width + padX * 2, height: src.height + padY * 2);
  img.fill(out, color: img.ColorRgb8(128, 128, 128));
  img.compositeImage(out, src, dstX: padX, dstY: padY);
  return Uint8List.fromList(img.encodeJpg(out, quality: 90));
}

/// Acha onde está o "assunto" da imagem comparando com a cor do fundo (borda).
/// Devolve [esq, topo, dir, base] em frações 0..1, ou null se não houver
/// contraste claro (foto cheia, fundo complexo demais).
List<double>? subjectBounds(Uint8List jpeg) {
  var im = img.decodeImage(jpeg);
  if (im == null) return null;
  im = img.copyResize(im, width: 96);
  final w = im.width, h = im.height;
  var r = 0.0, g = 0.0, b = 0.0, n = 0;
  void acc(int x, int y) {
    final p = im!.getPixel(x, y);
    r += p.r;
    g += p.g;
    b += p.b;
    n++;
  }

  for (var x = 0; x < w; x++) {
    acc(x, 0);
    acc(x, 1);
    acc(x, h - 1);
    acc(x, h - 2);
  }
  for (var y = 0; y < h; y++) {
    acc(0, y);
    acc(1, y);
    acc(w - 1, y);
    acc(w - 2, y);
  }
  r /= n;
  g /= n;
  b /= n;
  final rows = List<int>.filled(h, 0);
  final cols = List<int>.filled(w, 0);
  var total = 0;
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      final p = im.getPixel(x, y);
      final d = (p.r - r).abs() + (p.g - g).abs() + (p.b - b).abs();
      if (d > 70) {
        rows[y]++;
        cols[x]++;
        total++;
      }
    }
  }
  final cover = total / (w * h);
  if (cover < 0.02 || cover > 0.85) return null;
  int first(List<int> a, int min) {
    for (var i = 0; i < a.length; i++) {
      if (a[i] >= min) return i;
    }
    return 0;
  }

  int last(List<int> a, int min) {
    for (var i = a.length - 1; i >= 0; i--) {
      if (a[i] >= min) return i;
    }
    return a.length - 1;
  }

  final top = first(rows, 2), bottom = last(rows, 2);
  final left = first(cols, 2), right = last(cols, 2);
  if (bottom - top < h * 0.2) return null;
  return [left / w, top / h, (right + 1) / w, (bottom + 1) / h];
}
