import 'dart:math' as math;
import 'dart:ui' hide TextStyle;

import 'package:flutter/painting.dart';

import 'figure_guide.dart';

/// Desenha a construção do corpo inteiro (passos 0..11; o 12 é o sombreamento,
/// feito fora). Coordenadas da IMAGEM; quem chama aplica transformações.
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
  final axis = hMid - sMid; // do ombro ao quadril
  final sLat = (lSh - rSh) / f.shoulderWidth; // lateral dos ombros
  final hLat = (lHip - rHip) / f.hipWidth; // lateral dos quadris
  final b = f.bounds;
  final sp = f.style.spec;

  double bottomY() {
    var y = b.bottom;
    for (final k in ['lAn', 'rAn', 'lFoot', 'rFoot']) {
      final p = pts[k];
      if (p != null) y = math.max(y, p.dy);
    }
    return y;
  }

  // --- 0: linha de ação + régua de proporções em "cabeças" ---
  final a0 = layer(0);
  if (a0 > 0.01) {
    final spine = <Offset>[f.headCenter, sMid, (sMid + hMid) / 2, hMid];
    final knees = [pts['lKn'], pts['rKn']].whereType<Offset>().toList();
    final ankles = [pts['lAn'], pts['rAn']].whereType<Offset>().toList();
    if (knees.isNotEmpty) spine.add(_avg(knees));
    if (ankles.isNotEmpty) spine.add(_avg(ankles));
    canvas.drawPath(_smoothOpen(spine), stroke(a0, w: 1.7));

    final top = f.headCenter.dy - hh / 2;
    final bottom = bottomY();
    final x = b.left - hh * 0.3;
    canvas.drawLine(Offset(x, top), Offset(x, bottom), stroke(a0 * 0.7));
    final n = ((bottom - top) / hh).floor() + 1;
    for (var i = 0; i <= n; i++) {
      final y = top + i * hh;
      if (y > bottom + hh * 0.2) break;
      canvas.drawLine(Offset(x - hh * 0.12, y), Offset(x + hh * 0.12, y), stroke(a0 * 0.8));
      canvas.drawLine(Offset(b.left - hh * 0.2, y), Offset(b.right + hh * 0.2, y),
          stroke(a0 * 0.16, w: 0.8));
      if (i < n) _label(canvas, '${i + 1}', Offset(x - hh * 0.3, y + hh * 0.5), color, a0 * 0.9, hh);
    }
    // metade do corpo: costuma cair na região da virilha
    final half = top + (bottom - top) / 2;
    final dash = stroke(a0 * 0.5, w: 0.9);
    _dash(canvas, Offset(b.left - hh * 0.2, half), Offset(b.right + hh * 0.2, half), dash, hh);
  }

  // --- 1: eixos de equilíbrio e linha de gravidade ---
  final a1 = layer(1);
  if (a1 > 0.01) {
    final bottom = bottomY();
    final pit = sMid - axis / f.torsoLen * (f.shoulderWidth * 0.1);
    _dash(canvas, pit, Offset(pit.dx, bottom), stroke(a1 * 0.9, w: 1.2), hh);
    void across(Offset a, Offset c, double alpha) {
      final d = c - a;
      final len = d.distance;
      if (len < 1) return;
      final ext = d / len * (hh * 0.7);
      canvas.drawLine(a - ext, c + ext, stroke(alpha, w: 1.0));
    }

    across(lSh, rSh, a1);
    across(lHip, rHip, a1);
    final lk = pts['lKn'], rk = pts['rKn'], la = pts['lAn'], ra = pts['rAn'];
    if (lk != null && rk != null) across(lk, rk, a1 * 0.7);
    if (la != null && ra != null) across(la, ra, a1 * 0.7);
    // ponto de apoio: o pé mais carregado fica sob a linha de gravidade
    for (final p in [la, ra].whereType<Offset>()) {
      canvas.drawCircle(p, hh * 0.1, stroke(a1 * 0.8));
    }
  }

  // --- 2: cabeça e proporções do rosto ---
  final a2 = layer(2);
  if (a2 > 0.01) {
    final tilt = f.headTilt;
    canvas.save();
    canvas.translate(f.headCenter.dx, f.headCenter.dy);
    canvas.rotate(tilt);
    canvas.drawCircle(Offset(0, -hh * 0.08), hw / 2, stroke(a2 * 0.7));
    final head = Rect.fromCenter(center: Offset.zero, width: hw, height: hh);
    canvas.drawOval(head, fill(a2 * 0.06));
    canvas.drawOval(head, stroke(a2, w: 1.3));
    canvas.drawLine(Offset(0, -hh / 2), Offset(0, hh / 2), stroke(a2 * 0.7));
    for (final y in [0.0, 0.2, 0.31]) {
      // olhos, base do nariz, boca
      canvas.drawLine(Offset(-hw / 2, y * hh), Offset(hw / 2, y * hh), stroke(a2 * (y == 0 ? 0.7 : 0.45)));
    }
    canvas.drawLine(Offset(-hw / 2, -hh * 0.2), Offset(hw / 2, -hh * 0.2), stroke(a2 * 0.3));
    // olhos (maiores e mais baixos no anime) e queixo pontudo
    for (final s in [-1.0, 1.0]) {
      canvas.drawOval(
        Rect.fromCenter(
            center: Offset(s * hw * 0.22, sp.eyeY * hh),
            width: sp.eyeW * hh,
            height: sp.eyeH * hh * 1.6),
        stroke(a2 * 0.55, w: 0.9),
      );
    }
    if (sp.jaw > 0.5) {
      final jawPath = Path()
        ..moveTo(-hw * 0.5, hh * 0.05)
        ..lineTo(0, hh * 0.5)
        ..lineTo(hw * 0.5, hh * 0.05);
      canvas.drawPath(jawPath, stroke(a2 * 0.6));
    }
    canvas.restore();
  }

  // --- 3: pescoço, ombros e clavículas ---
  final a3 = layer(3);
  if (a3 > 0.01) {
    final tilt = f.headTilt;
    final hDir = Offset(math.cos(tilt), math.sin(tilt));
    final hDown = Offset(-math.sin(tilt), math.cos(tilt));
    final chinBase = f.headCenter + hDown * (hh * 0.45);
    final pit = sMid - axis / f.torsoLen * (f.shoulderWidth * 0.1);
    for (final s in [-1.0, 1.0]) {
      final top = chinBase + hDir * (s * hw * 0.27);
      final bot = pit + sLat * (s * f.shoulderWidth * 0.1);
      canvas.drawLine(top, bot, stroke(a3));
      final tip = s < 0 ? rSh : lSh;
      canvas.drawLine(bot, tip, stroke(a3 * 0.85)); // trapézio
      final mid = (pit + tip) / 2 - axis / f.torsoLen * (f.shoulderWidth * 0.05);
      final clav = Path()
        ..moveTo(pit.dx, pit.dy + hh * 0.05)
        ..quadraticBezierTo(mid.dx, mid.dy + hh * 0.1, tip.dx, tip.dy + hh * 0.05);
      canvas.drawPath(clav, stroke(a3 * 0.7));
      canvas.drawCircle(tip, hh * 0.2, stroke(a3 * 0.8));
    }
    canvas.drawLine(lSh, rSh, stroke(a3 * 0.6));
    canvas.drawCircle(pit, hh * 0.05, stroke(a3));
  }

  // --- 4: caixa torácica e coluna ---
  final a4 = layer(4);
  if (a4 > 0.01) {
    final rot = math.atan2(axis.dy, axis.dx) - math.pi / 2;
    final ribC = sMid + axis * 0.34;
    final rw = f.shoulderWidth * sp.ribW, rh = f.torsoLen * sp.ribH;
    canvas.save();
    canvas.translate(ribC.dx, ribC.dy);
    canvas.rotate(rot);
    final rib = Rect.fromCenter(center: Offset.zero, width: rw, height: rh);
    canvas.drawOval(rib, fill(a4 * 0.07));
    canvas.drawOval(rib, stroke(a4, w: 1.2));
    for (var i = 1; i <= 4; i++) {
      final y = -rh / 2 + rh * (i / 5.5);
      final k = math.sqrt(math.max(0.0, 1 - math.pow(2 * y / rh, 2).toDouble()));
      final arc = Path()
        ..moveTo(-rw / 2 * k * 0.92, y)
        ..quadraticBezierTo(0, y + rh * 0.1, rw / 2 * k * 0.92, y);
      canvas.drawPath(arc, stroke(a4 * 0.35, w: 0.9));
    }
    canvas.drawLine(Offset(0, -rh / 2), Offset(0, rh * 0.25), stroke(a4 * 0.55));
    canvas.restore();
    final spine = Path()
      ..moveTo(sMid.dx, sMid.dy)
      ..quadraticBezierTo(ribC.dx - sLat.dx * 0, ribC.dy, hMid.dx, hMid.dy);
    canvas.drawPath(spine, stroke(a4 * 0.8, w: 1.1));
  }

  // --- 5: pelve, cintura e abdômen ---
  final a5 = layer(5);
  if (a5 > 0.01) {
    canvas.drawLine(lHip, rHip, stroke(a5));
    final pelC = hMid - axis * 0.02;
    canvas.save();
    canvas.translate(pelC.dx, pelC.dy);
    canvas.rotate(f.hipTilt);
    final pel = RRect.fromRectAndRadius(
      Rect.fromCenter(center: Offset.zero, width: f.hipWidth * sp.pelW, height: f.torsoLen * 0.28),
      Radius.circular(f.torsoLen * 0.1),
    );
    canvas.drawRRect(pel, fill(a5 * 0.07));
    canvas.drawRRect(pel, stroke(a5, w: 1.2));
    final w = f.hipWidth * sp.pelW;
    for (final s in [-1.0, 1.0]) {
      // crista ilíaca
      final crest = Path()
        ..moveTo(s * w * 0.5, -f.torsoLen * 0.12)
        ..quadraticBezierTo(s * w * 0.22, -f.torsoLen * 0.2, 0, -f.torsoLen * 0.1);
      canvas.drawPath(crest, stroke(a5 * 0.6));
    }
    canvas.restore();
    // cintura / abdômen: une a base da caixa torácica ao topo da pelve
    final ribB = sMid + axis * 0.62;
    final pelT = hMid - axis * 0.12;
    for (final s in [-1.0, 1.0]) {
      canvas.drawLine(ribB + sLat * (s * f.shoulderWidth * sp.waist),
          pelT + hLat * (s * f.hipWidth * 0.55), stroke(a5 * 0.8));
      // silhueta do tronco: ombro → cintura → quadril (V no masculino, ampulheta no feminino)
      final tip = s < 0 ? rSh : lSh;
      final hp = (s < 0 ? rHip : lHip) + hLat * (s * f.hipWidth * (sp.pelW - 1) * 0.5);
      final waistPt = ribB + sLat * (s * f.shoulderWidth * sp.waist * 1.15);
      final sil = Path()
        ..moveTo(tip.dx, tip.dy)
        ..quadraticBezierTo(waistPt.dx, waistPt.dy, hp.dx, hp.dy);
      canvas.drawPath(sil, stroke(a5 * 0.5, w: 0.9));
    }
    canvas.drawLine(ribB + sLat * (-f.shoulderWidth * sp.waist), ribB + sLat * (f.shoulderWidth * sp.waist),
        stroke(a5 * 0.4));
  }

  // segmentos dos membros: [a, b, largura relativa à cabeça, posição do volume]
  final segs = <(String, String, double, double)>[
    ('lSh', 'lEl', sp.arm, 0.3), ('lEl', 'lWr', sp.fore, 0.25),
    ('rSh', 'rEl', sp.arm, 0.3), ('rEl', 'rWr', sp.fore, 0.25),
    ('lHip', 'lKn', sp.thigh, 0.38), ('lKn', 'lAn', sp.calf, 0.3),
    ('rHip', 'rKn', sp.thigh, 0.38), ('rKn', 'rAn', sp.calf, 0.3),
  ];

  // --- 6: articulações e eixos dos membros ---
  final a6 = layer(6);
  if (a6 > 0.01) {
    for (final s in segs) {
      final a = pts[s.$1], c = pts[s.$2];
      if (a != null && c != null) canvas.drawLine(a, c, stroke(a6, w: 1.2));
    }
    for (final p in pts.entries) {
      if (p.key == 'nose' || p.key == 'lEar' || p.key == 'rEar') continue;
      canvas.drawCircle(p.value, hh * 0.08, stroke(a6));
    }
  }

  // --- 7: volumes dos membros (cilindros) ---
  final a7 = layer(7);
  if (a7 > 0.01) {
    for (final s in segs) {
      final a = pts[s.$1], c = pts[s.$2];
      if (a != null && c != null) {
        _capsule(canvas, a, c, hh * s.$3, stroke(a7), fill(a7 * 0.07));
      }
    }
    for (final p in [lSh, rSh]) {
      canvas.drawCircle(p, hh * 0.27, stroke(a7 * 0.8));
    }
    for (final p in [lHip, rHip]) {
      canvas.drawCircle(p, hh * 0.32, stroke(a7 * 0.8));
    }
  }

  // --- 8: músculos principais ---
  final a8 = layer(8);
  if (a8 > 0.01) {
    for (final s in segs) {
      final a = pts[s.$1], c = pts[s.$2];
      if (a != null && c != null) {
        _spindle(canvas, a, c, hh * s.$3 * (1.0 + 0.1 * sp.muscle), s.$4,
            stroke(a8 * (0.5 + 0.4 * sp.muscle)), fill(a8 * 0.06));
      }
    }
    // peitorais e deltoides
    for (final s in [-1.0, 1.0]) {
      final tip = s < 0 ? rSh : lSh;
      final sternum = sMid + axis * 0.12;
      final low = sMid + axis * 0.3 + sLat * (s * f.shoulderWidth * 0.22);
      final pec = Path()
        ..moveTo(sternum.dx, sternum.dy)
        ..quadraticBezierTo(low.dx, low.dy, tip.dx - axis.dx * 0.0 + sLat.dx * s * -hh * 0.2,
            tip.dy + axis.dy * 0.18);
      if (sp.muscle >= 0.5 && !sp.bust) canvas.drawPath(pec, stroke(a8 * 0.6));
      canvas.drawCircle(tip, hh * 0.34 * (0.6 + 0.4 * sp.muscle), stroke(a8 * 0.5));
      if (sp.bust) {
        // seios: círculos de volume sobre a caixa torácica
        final bc = sMid + axis * 0.24 + sLat * (s * f.shoulderWidth * 0.2);
        canvas.drawCircle(bc, f.shoulderWidth * 0.17, stroke(a8 * 0.75));
        canvas.drawCircle(bc, f.shoulderWidth * 0.17, fill(a8 * 0.05));
      }
    }
    // linha do esterno ao umbigo (linha alba)
    canvas.drawLine(sMid + axis * 0.1, sMid + axis * 0.64, stroke(a8 * 0.3));
  }

  // --- 9: mãos ---
  final a9 = layer(9);
  if (a9 > 0.01) {
    for (final side in ['l', 'r']) {
      final wr = pts['${side}Wr'];
      if (wr == null) continue;
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
      _hand(canvas, wr, dir, len, hh * sp.hand, sMid, stroke(a9), fill(a9 * 0.1), a9);
    }
  }

  // --- 10: pés ---
  final a10 = layer(10);
  if (a10 > 0.01) {
    for (final side in ['l', 'r']) {
      final an = pts['${side}An'];
      if (an == null) continue;
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
      _foot(canvas, an, dir, len, hh * sp.foot, stroke(a10), fill(a10 * 0.1), a10);
    }
  }

  // --- 11: marcos anatômicos ---
  final a11 = layer(11);
  if (a11 > 0.01) {
    final navel = sMid + axis * 0.62;
    canvas.drawCircle(navel, hh * 0.05, stroke(a11));
    for (final s in [-1.0, 1.0]) {
      canvas.drawCircle(sMid + axis * 0.2 + sLat * (s * f.shoulderWidth * 0.22), hh * 0.05,
          stroke(a11 * 0.9));
    }
    final dash = stroke(a11 * 0.35, w: 0.9);
    final ext = f.shoulderWidth * 0.8;
    for (final p in [sMid + axis * 0.2, navel, hMid + axis * 0.1]) {
      _dash(canvas, p - sLat * ext, p + sLat * ext, dash, hh);
    }
    for (final k in ['lKn', 'rKn']) {
      final p = pts[k];
      if (p != null) canvas.drawCircle(p, hh * 0.15, stroke(a11 * 0.8)); // patela
    }
    for (final k in ['lEl', 'rEl']) {
      final p = pts[k];
      if (p != null) canvas.drawCircle(p, hh * 0.12, stroke(a11 * 0.6)); // cotovelo
    }
    for (final k in ['lWr', 'rWr', 'lAn', 'rAn']) {
      final p = pts[k];
      if (p != null) canvas.drawCircle(p, hh * 0.1, stroke(a11 * 0.6)); // ossos do punho/tornozelo
    }
    for (final s in [-1.0, 1.0]) {
      final hp = s < 0 ? rHip : lHip;
      canvas.drawCircle(hp + hLat * (s * f.hipWidth * 0.22), hh * 0.1, stroke(a11 * 0.6)); // trocânter
    }
  }
}

Offset _avg(List<Offset> l) => l.reduce((a, b) => a + b) / l.length.toDouble();

void _dash(Canvas c, Offset a, Offset b, Paint p, double hh) {
  final d = b - a;
  final len = d.distance;
  if (len < 1) return;
  final u = d / len;
  final dash = hh * 0.14, gap = hh * 0.1;
  var t = 0.0;
  while (t < len) {
    final e = math.min(t + dash, len);
    c.drawLine(a + u * t, a + u * e, p);
    t += dash + gap;
  }
}

void _label(Canvas c, String text, Offset at, Color color, double alpha, double hh) {
  final tp = TextPainter(
    text: TextSpan(
      text: text,
      style: TextStyle(
        color: color.withValues(alpha: alpha.clamp(0.0, 1.0)),
        fontSize: (hh * 0.2).clamp(8.0, 40.0).toDouble(),
        fontWeight: FontWeight.w600,
      ),
    ),
    textDirection: TextDirection.ltr,
  )..layout();
  tp.paint(c, at - Offset(tp.width / 2, tp.height / 2));
}

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

/// Forma de músculo: fuso que engrossa na posição [bulge] (0..1) do segmento.
void _spindle(Canvas c, Offset a, Offset b, double w, double bulge, Paint stroke, Paint fill) {
  final d = b - a;
  final len = d.distance;
  if (len < 1) return;
  c.save();
  c.translate(a.dx, a.dy);
  c.rotate(math.atan2(d.dy, d.dx));
  final bx = len * bulge;
  final path = Path()
    ..moveTo(0, 0)
    ..quadraticBezierTo(bx, -w * 0.62, len, -w * 0.08)
    ..quadraticBezierTo(len * (bulge + 0.45).clamp(0.0, 1.0), w * 0.3, len, w * 0.08)
    ..quadraticBezierTo(bx, w * 0.62, 0, 0)
    ..close();
  c.drawPath(path, fill);
  c.drawPath(path, stroke);
  c.restore();
}

/// Mão: palma + quatro dedos em leque + polegar (do lado do corpo).
void _hand(Canvas c, Offset wr, Offset dir, double len, double hh, Offset bodyCenter,
    Paint stroke, Paint fill, double alpha) {
  final perp0 = Offset(-dir.dy, dir.dx);
  final toBody = bodyCenter - wr;
  final perp = (perp0.dx * toBody.dx + perp0.dy * toBody.dy) >= 0 ? perp0 : -perp0;
  final palmL = len * 0.55;
  _capsule(c, wr, wr + dir * palmL, hh * 0.38, stroke, fill);
  final base = wr + dir * palmL;
  const fan = [-0.16, -0.05, 0.06, 0.17]; // da ponta do dedo mínimo ao indicador
  const lens = [0.55, 0.7, 0.66, 0.58];
  for (var i = 0; i < 4; i++) {
    final start = base + perp * (hh * (-0.13 + 0.09 * i) * -1.0);
    final end = start + dir * (len * lens[i]) + perp * (hh * fan[i] * -0.6);
    c.drawLine(start, end, stroke);
  }
  final thumbStart = wr + dir * (palmL * 0.35) + perp * (hh * 0.17);
  final thumbEnd = thumbStart + dir * (len * 0.3) + perp * (hh * 0.2);
  c.drawLine(thumbStart, thumbEnd, stroke);
}

/// Pé: cunha do tornozelo à ponta, arco e cinco dedos.
void _foot(Canvas c, Offset an, Offset dir, double len, double hh, Paint stroke, Paint fill,
    double alpha) {
  final perp = Offset(-dir.dy, dir.dx);
  final toe = an + dir * len;
  final w1 = hh * 0.17, w2 = hh * 0.12;
  final path = Path()
    ..moveTo((an + perp * w1).dx, (an + perp * w1).dy)
    ..lineTo((toe + perp * w2).dx, (toe + perp * w2).dy)
    ..lineTo((toe - perp * w2).dx, (toe - perp * w2).dy)
    ..lineTo((an - perp * w1).dx, (an - perp * w1).dy)
    ..close();
  c.drawPath(path, fill);
  c.drawPath(path, stroke);
  final arch = Path()
    ..moveTo((an - perp * w1 * 0.4).dx, (an - perp * w1 * 0.4).dy)
    ..quadraticBezierTo((an + dir * len * 0.45 - perp * w1 * 0.1).dx,
        (an + dir * len * 0.45 - perp * w1 * 0.1).dy, (toe - perp * w2 * 0.5).dx,
        (toe - perp * w2 * 0.5).dy);
  c.drawPath(arch, stroke);
  for (var i = 0; i < 5; i++) {
    final t = -0.8 + 0.4 * i;
    final p = toe + perp * (w2 * t);
    c.drawLine(p - dir * (hh * 0.08), p, stroke);
  }
  c.drawCircle(an - dir * (hh * 0.05), hh * 0.08, stroke); // calcanhar
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
