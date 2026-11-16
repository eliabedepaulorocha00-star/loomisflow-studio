import 'dart:math' as math;
import 'dart:ui';

import 'figure_guide.dart';

/// Desenha a construção do corpo (passos 0..5; o sombreamento é feito fora).
/// Coordenadas da IMAGEM; quem chama aplica transformações.
void paintFigure(
  Canvas canvas,
  FigureGuide f,
  double step, {
  required Color color,
  double opacity = 1,
  double lineScale = 1,
}) {
  final base = math.max(f.imageSize.width, f.imageSize.height);
  final lw = math.max(1.4, base / 520) * lineScale;
  double layer(int i) => (step - i + 1).clamp(0.0, 1.0).toDouble() * opacity;

  Paint stroke(double a, {double w = 1}) => Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = lw * w
    ..strokeCap = StrokeCap.round
    ..strokeJoin = StrokeJoin.round
    ..isAntiAlias = true
    ..color = color.withValues(alpha: a.clamp(0.0, 1.0));
  Paint fill(double a) => Paint()
    ..style = PaintingStyle.fill
    ..color = color.withValues(alpha: a.clamp(0.0, 1.0));

  final hh = f.headH;
  final hw = f.headW;
  final pts = f.pts;
  final lSh = pts['lSh']!, rSh = pts['rSh']!, lHip = pts['lHip']!, rHip = pts['rHip']!;
  final sMid = f.shoulderMid, hMid = f.hipMid;

  // --- 0: linha de ação + proporções em "cabeças" ---
  final a0 = layer(0);
  if (a0 > 0.01) {
    final spine = <Offset>[f.headCenter, sMid, (sMid + hMid) / 2, hMid];
    final knees = [pts['lKn'], pts['rKn']].whereType<Offset>().toList();
    final ankles = [pts['lAn'], pts['rAn']].whereType<Offset>().toList();
    if (knees.isNotEmpty) spine.add(_avg(knees));
    if (ankles.isNotEmpty) spine.add(_avg(ankles));
    canvas.drawPath(_smoothOpen(spine), stroke(a0, w: 1.7));

    final b = f.bounds;
    final top = f.headCenter.dy - hh / 2;
    var bottom = b.bottom;
    for (final k in ['lAn', 'rAn', 'lFoot', 'rFoot']) {
      final p = pts[k];
      if (p != null) bottom = math.max(bottom - 0, p.dy);
    }
    final x = b.left - hh * 0.3;
    canvas.drawLine(Offset(x, top), Offset(x, bottom), stroke(a0 * 0.7));
    final n = ((bottom - top) / hh).floor() + 1;
    for (var i = 0; i <= n; i++) {
      final y = top + i * hh;
      if (y > bottom + hh * 0.2) break;
      canvas.drawLine(Offset(x - hh * 0.12, y), Offset(x + hh * 0.12, y), stroke(a0 * 0.8));
      canvas.drawLine(Offset(b.left - hh * 0.2, y), Offset(b.right + hh * 0.2, y),
          stroke(a0 * 0.16, w: 0.8));
    }
  }

  // --- 1: cabeça e pescoço ---
  final a1 = layer(1);
  if (a1 > 0.01) {
    final tilt = f.headTilt;
    canvas.save();
    canvas.translate(f.headCenter.dx, f.headCenter.dy);
    canvas.rotate(tilt);
    final head = Rect.fromCenter(center: Offset.zero, width: hw, height: hh);
    canvas.drawOval(head, fill(a1 * 0.08));
    canvas.drawOval(head, stroke(a1, w: 1.3));
    canvas.drawLine(Offset(0, -hh / 2), Offset(0, hh / 2), stroke(a1 * 0.7));
    canvas.drawLine(Offset(-hw / 2, 0), Offset(hw / 2, 0), stroke(a1 * 0.7));
    canvas.restore();

    final hDir = Offset(math.cos(tilt), math.sin(tilt));
    final hDown = Offset(-math.sin(tilt), math.cos(tilt));
    final chinBase = f.headCenter + hDown * (hh * 0.45);
    final sDir = (lSh - rSh) / f.shoulderWidth;
    for (final s in [-1.0, 1.0]) {
      final top = chinBase + hDir * (s * hw * 0.27);
      final bot = sMid + sDir * (s * f.shoulderWidth * 0.14);
      canvas.drawLine(top, bot, stroke(a1));
      canvas.drawLine(bot, s < 0 ? rSh : lSh, stroke(a1 * 0.8));
    }
  }

  // --- 2: caixa torácica e pelve ---
  final a2 = layer(2);
  if (a2 > 0.01) {
    canvas.drawLine(lSh, rSh, stroke(a2));
    canvas.drawLine(lHip, rHip, stroke(a2));
    canvas.drawLine(sMid, hMid, stroke(a2 * 0.8));

    final axis = math.atan2((hMid - sMid).dy, (hMid - sMid).dx);
    final ribC = sMid + (hMid - sMid) * 0.34;
    canvas.save();
    canvas.translate(ribC.dx, ribC.dy);
    canvas.rotate(axis - math.pi / 2);
    final rib = Rect.fromCenter(
        center: Offset.zero, width: f.shoulderWidth * 0.78, height: f.torsoLen * 0.62);
    canvas.drawOval(rib, fill(a2 * 0.07));
    canvas.drawOval(rib, stroke(a2, w: 1.2));
    canvas.restore();

    final pelC = hMid + f.up * (-f.torsoLen * 0.02);
    canvas.save();
    canvas.translate(pelC.dx, pelC.dy);
    canvas.rotate(f.hipTilt);
    final pel = RRect.fromRectAndRadius(
      Rect.fromCenter(
          center: Offset.zero, width: f.hipWidth * 1.35, height: f.torsoLen * 0.28),
      Radius.circular(f.torsoLen * 0.1),
    );
    canvas.drawRRect(pel, fill(a2 * 0.07));
    canvas.drawRRect(pel, stroke(a2, w: 1.2));
    canvas.restore();
  }

  // segmentos dos membros: [a, b, largura relativa à cabeça]
  final segs = <(String, String, double)>[
    ('lSh', 'lEl', 0.40), ('lEl', 'lWr', 0.32),
    ('rSh', 'rEl', 0.40), ('rEl', 'rWr', 0.32),
    ('lHip', 'lKn', 0.62), ('lKn', 'lAn', 0.46),
    ('rHip', 'rKn', 0.62), ('rKn', 'rAn', 0.46),
  ];

  // --- 3: eixos dos membros e articulações ---
  final a3 = layer(3);
  if (a3 > 0.01) {
    for (final s in segs) {
      final a = pts[s.$1], b = pts[s.$2];
      if (a != null && b != null) canvas.drawLine(a, b, stroke(a3, w: 1.2));
    }
    for (final p in pts.entries) {
      if (p.key == 'nose' || p.key == 'lEar' || p.key == 'rEar') continue;
      canvas.drawCircle(p.value, hh * 0.08, stroke(a3));
    }
  }

  // --- 4: volumes dos membros ---
  final a4 = layer(4);
  if (a4 > 0.01) {
    for (final s in segs) {
      final a = pts[s.$1], b = pts[s.$2];
      if (a != null && b != null) {
        _capsule(canvas, a, b, hh * s.$3, stroke(a4), fill(a4 * 0.07));
      }
    }
    for (final p in [lSh, rSh]) {
      canvas.drawCircle(p, hh * 0.27, stroke(a4 * 0.8));
    }
    for (final p in [lHip, rHip]) {
      canvas.drawCircle(p, hh * 0.32, stroke(a4 * 0.8));
    }
  }

  // --- 5: mãos e pés ---
  final a5 = layer(5);
  if (a5 > 0.01) {
    for (final side in ['l', 'r']) {
      final wr = pts['${side}Wr'];
      if (wr != null) {
        final el = pts['${side}El'];
        final hand = pts['${side}Hand'];
        Offset dir;
        if (hand != null && (hand - wr).distance > 1) {
          dir = (hand - wr) / (hand - wr).distance;
        } else if (el != null && (wr - el).distance > 1) {
          dir = (wr - el) / (wr - el).distance;
        } else {
          dir = const Offset(0, 1);
        }
        var len = hh * 0.72;
        if (hand != null) len = (hand - wr).distance.clamp(hh * 0.45, hh * 0.9).toDouble();
        _capsule(canvas, wr, wr + dir * len, hh * 0.38, stroke(a5), fill(a5 * 0.1));
      }
      final an = pts['${side}An'];
      if (an != null) {
        final foot = pts['${side}Foot'];
        Offset dir;
        if (foot != null && (foot - an).distance > 1) {
          dir = (foot - an) / (foot - an).distance;
        } else {
          final out = (pts['${side}Hip']!.dx - hMid.dx) >= 0 ? 1.0 : -1.0;
          final d = Offset(out * 0.35, 1);
          dir = d / d.distance;
        }
        var len = hh * 0.95;
        if (foot != null) len = (foot - an).distance.clamp(hh * 0.5, hh * 1.1).toDouble();
        _capsule(canvas, an, an + dir * len, hh * 0.34, stroke(a5), fill(a5 * 0.1));
      }
    }
  }
}

Offset _avg(List<Offset> l) =>
    l.reduce((a, b) => a + b) / l.length.toDouble();

void _capsule(Canvas c, Offset a, Offset b, double w, Paint stroke, Paint fill) {
  final d = b - a;
  final len = d.distance;
  if (len < 1) return;
  c.save();
  c.translate((a.dx + b.dx) / 2, (a.dy + b.dy) / 2);
  c.rotate(math.atan2(d.dy, d.dx));
  final rr = RRect.fromRectAndRadius(
    Rect.fromCenter(center: Offset.zero, width: len + w * 0.4, height: w),
    Radius.circular(w / 2),
  );
  c.drawRRect(rr, fill);
  c.drawRRect(rr, stroke);
  c.restore();
}

Path _smoothOpen(List<Offset> pts) {
  final path = Path();
  if (pts.isEmpty) return path;
  path.moveTo(pts.first.dx, pts.first.dy);
  if (pts.length == 2) {
    path.lineTo(pts.last.dx, pts.last.dy);
    return path;
  }
  Offset mid(Offset a, Offset b) => Offset((a.dx + b.dx) / 2, (a.dy + b.dy) / 2);
  for (var i = 1; i < pts.length - 1; i++) {
    final m = mid(pts[i], pts[i + 1]);
    path.quadraticBezierTo(pts[i].dx, pts[i].dy, m.dx, m.dy);
  }
  path.lineTo(pts.last.dx, pts.last.dy);
  return path;
}
