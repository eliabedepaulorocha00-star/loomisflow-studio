import 'dart:math' as math;
import 'dart:ui';
import 'dart:ui' as ui;

import 'figure_renderer.dart';
import 'loomis_guide.dart';
import 'models.dart';

/// Desenha a guia do projeto (rosto OU corpo) já com o ajuste manual aplicado.
/// [step] é contínuo: cada camada aparece com fade conforme a barra desliza.
void paintProjectGuide(
  Canvas canvas,
  Project pr,
  double step, {
  required Color color,
  double opacity = 1,
  double lineScale = 1,
  ui.Image? shading,
}) {
  // sombreamento: acompanha a FOTO (não o ajuste), recortado na região da guia
  final shadeAlpha = (step - pr.maxStep + 1).clamp(0.0, 1.0).toDouble() * opacity;
  if (shading != null && shadeAlpha > 0.01) {
    final clip = pr.figure != null
        ? (Path()..addRect(pr.figure!.bounds.inflate(pr.figure!.headH * 0.2)))
        : pr.guide.headPath();
    canvas.save();
    pr.applyAdjust(canvas);
    canvas.clipPath(clip);
    pr.undoAdjust(canvas);
    canvas.drawImageRect(
      shading,
      Rect.fromLTWH(0, 0, shading.width.toDouble(), shading.height.toDouble()),
      Offset.zero & pr.guide.imageSize,
      Paint()
        ..filterQuality = FilterQuality.medium
        ..color = const Color(0xFFFFFFFF).withValues(alpha: shadeAlpha * 0.9),
    );
    canvas.restore();
  }

  canvas.save();
  pr.applyAdjust(canvas);
  final ls = lineScale / pr.adjScale;
  final fig = pr.figure;
  if (fig != null) {
    paintFigure(canvas, fig, step,
        color: color, opacity: opacity, lineScale: ls);
  } else {
    paintGuide(canvas, pr.guide, step,
        color: color, opacity: opacity, lineScale: ls);
  }
  canvas.restore();
}

/// Guia Loomis do rosto, passos 0..9 (o 10 é o sombreamento, feito acima).
void paintGuide(
  Canvas canvas,
  LoomisGuide g,
  double step, {
  required Color color,
  double opacity = 1,
  double lineScale = 1,
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

  canvas.save();
  canvas.translate(g.origin.dx, g.origin.dy);
  canvas.rotate(g.roll);

  final cx = g.center.dx, cy = g.center.dy, r = g.radius;
  final yaw = g.yaw;
  final sinY = math.sin(yaw), cosY = math.cos(yaw);
  final u = g.unit;
  final ax = g.noseTip.dx;

  // 0 — esfera craniana
  final a0 = layer(0);
  if (a0 > 0.01) {
    canvas.drawCircle(g.center, r, stroke(a0, w: 1.3));
  }

  // 1 — corte dos planos laterais
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

  // 2 — linha central e linha das sobrancelhas
  final a2 = layer(2);
  if (a2 > 0.01) {
    final minor = r * sinY.abs();
    if (minor < r * 0.02) {
      canvas.drawLine(Offset(cx, cy - r), Offset(cx, cy + r), stroke(a2));
    } else {
      final rect =
          Rect.fromCenter(center: g.center, width: minor * 2, height: r * 2);
      canvas.drawArc(rect, yaw >= 0 ? -math.pi / 2 : math.pi / 2, math.pi, false,
          stroke(a2));
    }
    canvas.drawLine(Offset(cx, cy + r), Offset(ax, g.chinY), stroke(a2 * 0.8));
    canvas.drawLine(Offset(cx - r, cy), Offset(cx + r, cy), stroke(a2, w: 1.2));
  }

  // 3 — terços: linha do cabelo, do nariz e do queixo
  final a3 = layer(3);
  if (a3 > 0.01) {
    for (final y in [g.hairY, g.noseY, g.chinY]) {
      final (a, b) = g.lineAt(y);
      canvas.drawLine(a, b, stroke(a3));
    }
  }

  // 4 — mandíbula, queixo e orelhas
  final a4 = layer(4);
  if (a4 > 0.01) {
    const k = 0.78;
    final rc = r * math.sqrt(1 - k * k);
    final y2 = g.chinY - 0.25 * u;
    final (lo, hi) = g.lineAt(y2);
    final chinHalf = (hi.dx - lo.dx) * 0.22;

    for (final s in [-1.0, 1.0]) {
      final ccx = cx + s * k * r * cosY;
      canvas.drawLine(Offset(ccx, cy + rc), s < 0 ? lo : hi, stroke(a4));
    }
    final chin = Path()
      ..moveTo(lo.dx, lo.dy)
      ..lineTo(ax - chinHalf, g.chinY)
      ..lineTo(ax + chinHalf, g.chinY)
      ..lineTo(hi.dx, hi.dy);
    canvas.drawPath(chin, stroke(a4));

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

  // 5 — pescoço e ombros
  final a5 = layer(5);
  if (a5 > 0.01) {
    final (nlo, nhi) = g.lineAt(g.noseY);
    final w = (nhi.dx - nlo.dx).abs();
    final neckHalf = w * 0.27;
    final topY = g.noseY + 0.15 * u;
    final botY = g.chinY + 1.05 * u;
    for (final s in [-1.0, 1.0]) {
      canvas.drawLine(Offset(ax + s * neckHalf, topY),
          Offset(ax + s * neckHalf * 1.18, botY), stroke(a5));
      // trapézio: do pescoço até a ponta do ombro
      canvas.drawLine(Offset(ax + s * neckHalf * 1.18, botY - 0.2 * u),
          Offset(ax + s * w * 1.25, botY + 0.62 * u), stroke(a5 * 0.9));
    }
    canvas.drawLine(Offset(ax - w * 1.25, botY + 0.62 * u),
        Offset(ax + w * 1.25, botY + 0.62 * u), stroke(a5 * 0.45));
    canvas.drawCircle(Offset(ax, botY + 0.12 * u), u * 0.05, stroke(a5));
  }

  // 6 — olhos, sobrancelhas e regra dos cinco olhos
  final a6 = layer(6);
  if (a6 > 0.01) {
    final eyeY = (g.eyeL.dy + g.eyeR.dy) / 2;
    final (eLo, eHi) = g.lineAt(eyeY);
    canvas.drawLine(eLo, eHi, stroke(a6 * 0.55));

    final ew = g.eyeHalfW * 2.5;
    final eh = ew * 0.36;
    final midX = (g.eyeL.dx + g.eyeR.dx) / 2;
    final guideBottom = g.mouth.dy + u * 0.35;

    for (final e in [g.eyeL, g.eyeR]) {
      final dir = e.dx < midX ? -1.0 : 1.0; // para fora do rosto
      final inner = Offset(e.dx - dir * ew / 2, e.dy);
      final outer = Offset(e.dx + dir * ew / 2, e.dy);

      final eye = Path()
        ..moveTo(inner.dx, inner.dy)
        ..quadraticBezierTo(e.dx, e.dy - eh * 1.5, outer.dx, outer.dy)
        ..quadraticBezierTo(e.dx, e.dy + eh * 1.1, inner.dx, inner.dy);
      canvas.drawPath(eye, stroke(a6, w: 1.1));
      canvas.drawCircle(Offset(e.dx, e.dy - eh * 0.1), eh * 0.78, stroke(a6 * 0.9));

      final b0 = Offset(e.dx - dir * ew * 0.62, e.dy - eh * 2.3);
      final b1 = Offset(e.dx + dir * ew * 0.8, e.dy - eh * 1.9);
      final brow = Path()
        ..moveTo(b0.dx, b0.dy)
        ..cubicTo(b0.dx + dir * ew * 0.3, b0.dy - eh * 0.9, b1.dx - dir * ew * 0.35,
            b1.dy - eh * 1.0, b1.dx, b1.dy);
      canvas.drawPath(brow, stroke(a6 * 0.9, w: 1.1));

      // cantos dos olhos: dividem a largura do rosto em cinco olhos
      for (final x in [inner.dx, outer.dx]) {
        canvas.drawLine(Offset(x, e.dy - eh * 3), Offset(x, guideBottom), stroke(a6 * 0.22));
      }
    }
  }

  // 7 — nariz e boca
  final a7 = layer(7);
  if (a7 > 0.01) {
    final nh = g.noseHalfW;
    canvas.drawLine(Offset(ax - nh * 0.35, cy), Offset(ax - nh, g.noseY), stroke(a7));
    canvas.drawLine(Offset(ax + nh * 0.35, cy), Offset(ax + nh, g.noseY), stroke(a7));
    canvas.drawLine(Offset(ax - nh, g.noseY), Offset(ax + nh, g.noseY), stroke(a7 * 0.8));
    canvas.drawCircle(Offset(ax, g.noseY - u * 0.08), nh * 0.34, stroke(a7 * 0.9));

    final m = g.mouth;
    final mh = g.mouthHalfW;
    for (final s in [-1.0, 1.0]) {
      // asas e narinas
      canvas.drawOval(
        Rect.fromCenter(
            center: Offset(ax + s * nh * 0.92, g.noseY - u * 0.1),
            width: nh * 0.55,
            height: u * 0.3),
        stroke(a7 * 0.9),
      );
      canvas.drawOval(
        Rect.fromCenter(
            center: Offset(ax + s * nh * 0.38, g.noseY - u * 0.02),
            width: nh * 0.32,
            height: u * 0.12),
        stroke(a7 * 0.9),
      );
      // filtro (sulco entre nariz e lábio)
      canvas.drawLine(Offset(ax + s * nh * 0.2, g.noseY),
          Offset(m.dx + s * mh * 0.2, m.dy - u * 0.1), stroke(a7 * 0.5));
      // alinhamento: centro do olho -> canto da boca
      final eye = s < 0 ? g.eyeL : g.eyeR;
      canvas.drawLine(Offset(eye.dx, eye.dy), Offset(eye.dx, m.dy + u * 0.3), stroke(a7 * 0.22));
    }

    final upper = Path()
      ..moveTo(m.dx - mh, m.dy)
      ..quadraticBezierTo(m.dx - mh * 0.45, m.dy - u * 0.2, m.dx, m.dy - u * 0.1)
      ..quadraticBezierTo(m.dx + mh * 0.45, m.dy - u * 0.2, m.dx + mh, m.dy);
    final lower = Path()
      ..moveTo(m.dx - mh, m.dy)
      ..quadraticBezierTo(m.dx, m.dy + u * 0.34, m.dx + mh, m.dy);
    final center = Path()
      ..moveTo(m.dx - mh, m.dy)
      ..quadraticBezierTo(m.dx, m.dy + u * 0.06, m.dx + mh, m.dy);
    canvas.drawPath(upper, stroke(a7));
    canvas.drawPath(lower, stroke(a7));
    canvas.drawPath(center, stroke(a7, w: 1.2));
    final crease = Path()
      ..moveTo(m.dx - mh * 0.35, m.dy + u * 0.46)
      ..quadraticBezierTo(m.dx, m.dy + u * 0.5, m.dx + mh * 0.35, m.dy + u * 0.46);
    canvas.drawPath(crease, stroke(a7 * 0.5));
  }

  // 8 — massa do cabelo
  final a8 = layer(8);
  if (a8 > 0.01) {
    final hr = r * 1.16;
    canvas.drawArc(Rect.fromCircle(center: g.center, radius: hr), math.pi, math.pi,
        false, stroke(a8, w: 1.2));
    final earY = (cy + g.noseY) / 2;
    for (final s in [-1.0, 1.0]) {
      canvas.drawLine(
          Offset(cx + s * hr, cy), Offset(cx + s * r * 1.04, earY - 0.25 * u), stroke(a8 * 0.8));
    }
    final (hlo, hhi) = g.lineAt(g.hairY + 0.25 * u);
    final hairline = Path()
      ..moveTo(hlo.dx, hlo.dy)
      ..quadraticBezierTo(cx, g.hairY - 0.3 * u, hhi.dx, hhi.dy);
    canvas.drawPath(hairline, stroke(a8 * 0.8));
  }

  // 9 — contorno e detalhes
  final a9 = layer(9);
  if (a9 > 0.01) {
    canvas.drawPath(_smoothClosed(g.contour), stroke(a9, w: 1.4));
    for (final f in g.features) {
      final path = Path()..moveTo(f.first.dx, f.first.dy);
      for (final pt in f.skip(1)) {
        path.lineTo(pt.dx, pt.dy);
      }
      canvas.drawPath(path, stroke(a9 * 0.9));
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
