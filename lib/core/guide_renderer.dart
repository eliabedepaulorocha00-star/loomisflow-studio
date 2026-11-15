import 'dart:math' as math;
import 'dart:ui';
import 'dart:ui' as ui;

import 'loomis_guide.dart';
import 'models.dart';

/// Desenha o guia Loomis em coordenadas da IMAGEM (pixels da foto).
/// Quem chama aplica a transformação (ajuste à tela, zoom, rotação...).
///
/// [step] é contínuo (0..7): camadas aparecem com fade conforme a barra desliza.
/// [lineScale] converte espessura de tela em espessura de imagem (1/zoom).
void paintGuide(
  Canvas canvas,
  LoomisGuide g,
  double step, {
  required Color color,
  double opacity = 1,
  double lineScale = 1,
  ui.Image? shading,
}) {
  final base = math.max(g.imageSize.width, g.imageSize.height);
  final lw = math.max(1.4, base / 520) * lineScale;

  double layer(int i) => (step - i + 1).clamp(0.0, 1.0).toDouble() * opacity;

  Paint stroke(double alpha, {double w = 1}) => Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = lw * w
    ..strokeCap = StrokeCap.round
    ..strokeJoin = StrokeJoin.round
    ..isAntiAlias = true
    ..color = color.withValues(alpha: alpha.clamp(0.0, 1.0));

  Paint fill(double alpha) => Paint()
    ..style = PaintingStyle.fill
    ..color = color.withValues(alpha: alpha.clamp(0.0, 1.0));

  // --- Passo 7: sombreamento (em espaço da imagem, recortado na cabeça) ---
  final a7 = layer(7);
  if (shading != null && a7 > 0.01) {
    canvas.save();
    canvas.clipPath(g.headPath());
    final src = Rect.fromLTWH(
        0, 0, shading.width.toDouble(), shading.height.toDouble());
    final dst = Rect.fromLTWH(0, 0, g.imageSize.width, g.imageSize.height);
    canvas.drawImageRect(
      shading,
      src,
      dst,
      Paint()
        ..filterQuality = FilterQuality.medium
        ..color = const Color(0xFFFFFFFF).withValues(alpha: a7 * 0.9),
    );
    canvas.restore();
  }

  // --- Referencial da cabeça ---
  canvas.save();
  canvas.translate(g.origin.dx, g.origin.dy);
  canvas.rotate(g.roll);

  final cx = g.center.dx, cy = g.center.dy, r = g.radius;
  final yaw = g.yaw;
  final sinY = math.sin(yaw), cosY = math.cos(yaw);
  final u = g.unit;

  // Passo 0 — esfera craniana
  final a0 = layer(0);
  if (a0 > 0.01) {
    canvas.drawCircle(g.center, r, stroke(a0, w: 1.3));
  }

  // Passo 1 — corte dos planos laterais
  final a1 = layer(1);
  if (a1 > 0.01) {
    const k = 0.78;
    final rc = r * math.sqrt(1 - k * k);
    for (final s in [-1.0, 1.0]) {
      final visible = (-s * sinY) > 0;
      final minor = math.max(rc * sinY.abs(), r * 0.04);
      final ccx = cx + s * k * r * cosY;
      final rect =
          Rect.fromCenter(center: Offset(ccx, cy), width: minor * 2, height: rc * 2);
      if (visible) canvas.drawOval(rect, fill(a1 * 0.14));
      canvas.drawOval(rect, stroke(a1 * (visible ? 1 : 0.35)));
    }
  }

  // Passo 2 — linha central (meridiano) e linha das sobrancelhas (equador)
  final a2 = layer(2);
  if (a2 > 0.01) {
    final minor = r * sinY.abs();
    if (minor < r * 0.02) {
      canvas.drawLine(Offset(cx, cy - r), Offset(cx, cy + r), stroke(a2));
    } else {
      final rect =
          Rect.fromCenter(center: g.center, width: minor * 2, height: r * 2);
      canvas.drawArc(
        rect,
        yaw >= 0 ? -math.pi / 2 : math.pi / 2,
        math.pi,
        false,
        stroke(a2),
      );
    }
    // continuação do eixo central até o queixo
    canvas.drawLine(
        Offset(cx, cy + r), Offset(g.noseTip.dx, g.chinY), stroke(a2 * 0.8));
    // linha das sobrancelhas
    canvas.drawLine(Offset(cx - r, cy), Offset(cx + r, cy), stroke(a2, w: 1.2));
  }

  // Passo 3 — terços: linha do cabelo, linha do nariz, linha do queixo
  final a3 = layer(3);
  if (a3 > 0.01) {
    for (final y in [g.hairY, g.noseY, g.chinY]) {
      final (a, b) = g.lineAt(y);
      canvas.drawLine(a, b, stroke(a3));
    }
  }

  // Passo 4 — mandíbula, queixo e orelhas
  final a4 = layer(4);
  if (a4 > 0.01) {
    const k = 0.78;
    final rc = r * math.sqrt(1 - k * k);
    final y2 = g.chinY - 0.25 * u;
    final (lo, hi) = g.lineAt(y2);
    final ax = g.noseTip.dx;
    final chinHalf = (hi.dx - lo.dx) * 0.22;

    for (final s in [-1.0, 1.0]) {
      final ccx = cx + s * k * r * cosY;
      final start = Offset(ccx, cy + rc);
      final end = s < 0 ? lo : hi;
      canvas.drawLine(start, end, stroke(a4));
    }
    final chin = Path()
      ..moveTo(lo.dx, lo.dy)
      ..lineTo(ax - chinHalf, g.chinY)
      ..lineTo(ax + chinHalf, g.chinY)
      ..lineTo(hi.dx, hi.dy);
    canvas.drawPath(chin, stroke(a4));

    // orelhas: entre a linha das sobrancelhas e a do nariz
    final earY = (cy + g.noseY) / 2;
    final (eLo, eHi) = g.lineAt(earY);
    final earH = (g.noseY - cy) * 0.95;
    final earW = u * 0.3;
    for (final s in [-1.0, 1.0]) {
      final visible = (-s * sinY) > -0.2;
      final ex = s < 0 ? eLo.dx : eHi.dx;
      canvas.drawOval(
        Rect.fromCenter(
            center: Offset(ex - s * earW * 0.3, earY), width: earW, height: earH),
        stroke(a4 * (visible ? 1 : 0.3)),
      );
    }
  }

  // Passo 5 — posicionamento dos traços
  final a5 = layer(5);
  if (a5 > 0.01) {
    final eyeY = (g.eyeL.dy + g.eyeR.dy) / 2;
    final (eLo, eHi) = g.lineAt(eyeY);
    canvas.drawLine(eLo, eHi, stroke(a5 * 0.6));

    for (final e in [g.eyeL, g.eyeR]) {
      final w = g.eyeHalfW * 2.3, h = g.eyeHalfW * 1.0;
      canvas.drawRRect(
        RRect.fromRectAndRadius(
            Rect.fromCenter(center: e, width: w, height: h),
            Radius.circular(h / 2)),
        stroke(a5),
      );
      // sobrancelha em bloco
      canvas.drawLine(Offset(e.dx - w / 2, e.dy - h * 1.2),
          Offset(e.dx + w / 2, e.dy - h * 1.5), stroke(a5 * 0.8));
    }

    final ax = g.noseTip.dx;
    final bridge = Offset(ax, cy);
    final nl = Offset(ax - g.noseHalfW, g.noseY);
    final nr = Offset(ax + g.noseHalfW, g.noseY);
    canvas.drawLine(Offset(bridge.dx - g.noseHalfW * 0.35, bridge.dy), nl, stroke(a5));
    canvas.drawLine(Offset(bridge.dx + g.noseHalfW * 0.35, bridge.dy), nr, stroke(a5));
    canvas.drawLine(nl, nr, stroke(a5));

    final m = g.mouth;
    final mouth = Path()
      ..moveTo(m.dx - g.mouthHalfW, m.dy)
      ..quadraticBezierTo(m.dx, m.dy + u * 0.08, m.dx + g.mouthHalfW, m.dy);
    canvas.drawPath(mouth, stroke(a5, w: 1.2));
  }

  // Passo 6 — contorno e detalhes
  final a6 = layer(6);
  if (a6 > 0.01) {
    canvas.drawPath(_smoothClosed(g.contour), stroke(a6, w: 1.4));
    for (final f in g.features) {
      final path = Path()..moveTo(f.first.dx, f.first.dy);
      for (final pt in f.skip(1)) {
        path.lineTo(pt.dx, pt.dy);
      }
      canvas.drawPath(path, stroke(a6 * 0.9));
    }
  }

  canvas.restore();
}

Path _smoothClosed(List<Offset> pts) {
  final path = Path();
  if (pts.length < 3) return path;
  Offset mid(Offset a, Offset b) => Offset((a.dx + b.dx) / 2, (a.dy + b.dy) / 2);
  final start = mid(pts.last, pts.first);
  path.moveTo(start.dx, start.dy);
  for (var i = 0; i < pts.length; i++) {
    final cur = pts[i];
    final next = pts[(i + 1) % pts.length];
    final m = mid(cur, next);
    path.quadraticBezierTo(cur.dx, cur.dy, m.dx, m.dy);
  }
  return path..close();
}

/// Grade 8×8 sobre a imagem (para quadricular / checar proporções).
void paintGrid(Canvas canvas, Size size,
    {required Color color, double opacity = 0.5, double lineScale = 1}) {
  final paint = Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = math.max(1.0, size.longestSide / 900) * lineScale
    ..color = color.withValues(alpha: opacity);
  final cell = size.longestSide / 8;
  for (double x = 0; x <= size.width + 0.1; x += cell) {
    canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
  }
  for (double y = 0; y <= size.height + 0.1; y += cell) {
    canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
  }
  canvas.drawRect(Offset.zero & size, paint..strokeWidth *= 1.6);
}

/// Desenha os traços do usuário (coordenadas da imagem).
void paintStrokes(Canvas canvas, List<StrokeData> strokes, [StrokeData? live]) {
  void one(StrokeData s) {
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..isAntiAlias = true
      ..strokeWidth = s.width
      ..color = Color(s.color);
    if (s.points.length == 1) {
      canvas.drawCircle(s.points.first, s.width / 2, paint..style = PaintingStyle.fill);
      return;
    }
    final path = Path()..moveTo(s.points.first.dx, s.points.first.dy);
    for (var i = 1; i < s.points.length - 1; i++) {
      final a = s.points[i], b = s.points[i + 1];
      path.quadraticBezierTo(a.dx, a.dy, (a.dx + b.dx) / 2, (a.dy + b.dy) / 2);
    }
    path.lineTo(s.points.last.dx, s.points.last.dy);
    canvas.drawPath(path, paint);
  }

  for (final s in strokes) {
    if (s.points.isNotEmpty) one(s);
  }
  if (live != null && live.points.isNotEmpty) one(live);
}
