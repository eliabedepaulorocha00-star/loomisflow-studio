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
