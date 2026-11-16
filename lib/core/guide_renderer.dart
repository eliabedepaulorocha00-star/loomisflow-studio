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

/// Guia Loomis do rosto, passos 0..15 (o 16 é o sombreamento, feito acima).
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
      canvas.drawOval(
        Rect.fromCenter(
            center: Offset(ex - s * earW * 0.3, earY), width: earW * 0.5, height: earH * 0.62),
        stroke(a4 * (visible ? 0.5 : 0.15)),
      );
    }
  }

  // ---- medidas compartilhadas pelos passos 5..14 ----
  final eyeY = (g.eyeL.dy + g.eyeR.dy) / 2;
  final midX = (g.eyeL.dx + g.eyeR.dx) / 2;
  final ew = g.eyeHalfW * 2.5;
  final eh = ew * 0.36;
  final (nlo0, nhi0) = g.lineAt(g.noseY);
  final nw = (nhi0.dx - nlo0.dx).abs();
  final neckHalf = nw * 0.27;
  final neckTop = g.noseY + 0.15 * u;
  final neckBot = g.chinY + 1.05 * u;
  final earLineY = (cy + g.noseY) / 2;
  final nh = g.noseHalfW;
  final m = g.mouth;
  final mh = g.mouthHalfW;

  // 5 — planos do rosto (blocos: testa, meio do rosto, maxilar)
  final a5 = layer(5);
  if (a5 > 0.01) {
    final (hLo, hHi) = g.lineAt(g.hairY + 0.35 * u);
    final (bLo, bHi) = g.lineAt(cy);
    final (nLo, nHi) = g.lineAt(g.noseY);
    Offset inset(Offset lo, Offset hi, double t, bool left) => left
        ? Offset(lo.dx + (hi.dx - lo.dx) * t, lo.dy)
        : Offset(hi.dx - (hi.dx - lo.dx) * t, hi.dy);
    final fl = inset(hLo, hHi, 0.2, true), fr = inset(hLo, hHi, 0.2, false);
    final bl = inset(bLo, bHi, 0.16, true), br = inset(bLo, bHi, 0.16, false);
    final nl = inset(nLo, nHi, 0.3, true), nr = inset(nLo, nHi, 0.3, false);
    final chinL = Offset(ax - u * 0.4, g.chinY), chinR = Offset(ax + u * 0.4, g.chinY);
    Path poly(List<Offset> p) {
      final path = Path()..moveTo(p.first.dx, p.first.dy);
      for (final q in p.skip(1)) {
        path.lineTo(q.dx, q.dy);
      }
      return path..close();
    }

    for (final p in [
      poly([fl, fr, br, bl]),
      poly([bl, br, nr, nl]),
      poly([nl, nr, chinR, chinL]),
    ]) {
      canvas.drawPath(p, fill(a5 * 0.05));
      canvas.drawPath(p, stroke(a5 * 0.85, w: 0.9));
    }
    for (final s in [-1.0, 1.0]) {
      final start = s < 0 ? bLo : bHi;
      final cheek = Path()
        ..moveTo(start.dx, start.dy + 0.3 * u)
        ..quadraticBezierTo(ax + s * nw * 0.95, g.noseY - 0.55 * u,
            ax + s * nw * 0.55, g.noseY + 0.1 * u);
      canvas.drawPath(cheek, stroke(a5 * 0.7));
    }
  }

  // 6 — pescoço (cilindro e esternocleidomastoideo)
  final a6 = layer(6);
  if (a6 > 0.01) {
    final (eLo, eHi) = g.lineAt(earLineY + 0.3 * u);
    for (final s in [-1.0, 1.0]) {
      canvas.drawLine(Offset(ax + s * neckHalf, neckTop),
          Offset(ax + s * neckHalf * 1.18, neckBot), stroke(a6));
      final from = s < 0 ? eLo : eHi;
      canvas.drawLine(Offset(from.dx, earLineY + 0.3 * u),
          Offset(ax + s * neckHalf * 0.12, neckBot + 0.08 * u), stroke(a6 * 0.75));
    }
    canvas.drawCircle(Offset(ax, neckBot + 0.1 * u), u * 0.06, stroke(a6));
    canvas.drawLine(Offset(ax, g.chinY), Offset(ax, neckBot + 0.1 * u), stroke(a6 * 0.3));
    final shadow = Path()
      ..moveTo(ax - neckHalf, g.chinY + 0.12 * u)
      ..quadraticBezierTo(ax, g.chinY + 0.4 * u, ax + neckHalf, g.chinY + 0.12 * u);
    canvas.drawPath(shadow, stroke(a6 * 0.6));
  }

  // 7 — ombros, trapézio e clavículas
  final a7 = layer(7);
  if (a7 > 0.01) {
    final tipY = neckBot + 0.62 * u;
    final tipX = nw * 1.25;
    for (final s in [-1.0, 1.0]) {
      canvas.drawLine(Offset(ax + s * neckHalf * 1.18, neckBot - 0.2 * u),
          Offset(ax + s * tipX, tipY), stroke(a7 * 0.9));
      final clav = Path()
        ..moveTo(ax + s * neckHalf * 0.15, neckBot + 0.1 * u)
        ..quadraticBezierTo(ax + s * tipX * 0.5, neckBot + 0.02 * u,
            ax + s * tipX * 0.95, tipY + 0.02 * u);
      canvas.drawPath(clav, stroke(a7 * 0.8));
      canvas.drawCircle(Offset(ax + s * tipX, tipY + 0.1 * u), u * 0.3, stroke(a7 * 0.6));
    }
    canvas.drawLine(Offset(ax - tipX, tipY), Offset(ax + tipX, tipY), stroke(a7 * 0.45));
    canvas.drawLine(
        Offset(ax, neckBot + 0.1 * u), Offset(ax, neckBot + 1.0 * u), stroke(a7 * 0.5));
  }

  // 8 — regra dos cinco olhos e alinhamentos
  final a8 = layer(8);
  if (a8 > 0.01) {
    final (eLo, eHi) = g.lineAt(eyeY);
    final span = eHi.dx - eLo.dx;
    for (var i = 0; i <= 5; i++) {
      final x = eLo.dx + span * i / 5;
      canvas.drawLine(Offset(x, g.hairY + 0.4 * u), Offset(x, g.chinY - 0.2 * u),
          stroke(a8 * (i == 0 || i == 5 ? 0.18 : 0.35)));
    }
    canvas.drawLine(eLo, eHi, stroke(a8 * 0.6));
    final (mLo, mHi) = g.lineAt(m.dy);
    canvas.drawLine(mLo, mHi, stroke(a8 * 0.45));
    final lipY = m.dy + (g.chinY - m.dy) * 0.45;
    final (lLo, lHi) = g.lineAt(lipY);
    canvas.drawLine(lLo, lHi, stroke(a8 * 0.3));
    for (final e in [g.eyeL, g.eyeR]) {
      canvas.drawLine(Offset(e.dx, e.dy), Offset(e.dx, m.dy + u * 0.3), stroke(a8 * 0.3));
    }
  }

  // 9 — olhos (pálpebras, íris, pupila, brilho)
  final a9 = layer(9);
  if (a9 > 0.01) {
    for (final e in [g.eyeL, g.eyeR]) {
      final dir = e.dx < midX ? -1.0 : 1.0; // para fora do rosto
      final inner = Offset(e.dx - dir * ew / 2, e.dy);
      final outer = Offset(e.dx + dir * ew / 2, e.dy);
      final eye = Path()
        ..moveTo(inner.dx, inner.dy)
        ..quadraticBezierTo(e.dx, e.dy - eh * 1.5, outer.dx, outer.dy)
        ..quadraticBezierTo(e.dx, e.dy + eh * 1.1, inner.dx, inner.dy);
      canvas.drawPath(eye, stroke(a9, w: 1.1));
      final crease = Path()
        ..moveTo(inner.dx + dir * ew * 0.12, inner.dy - eh * 0.9)
        ..quadraticBezierTo(
            e.dx, e.dy - eh * 2.3, outer.dx - dir * ew * 0.05, outer.dy - eh * 0.6);
      canvas.drawPath(crease, stroke(a9 * 0.6));
      final iris = Offset(e.dx, e.dy - eh * 0.1);
      canvas.drawCircle(iris, eh * 0.82, stroke(a9 * 0.95));
      canvas.drawCircle(iris, eh * 0.34, fill(a9 * 0.55));
      canvas.drawCircle(iris + Offset(-eh * 0.25, -eh * 0.28), eh * 0.12, fill(a9 * 0.9));
      canvas.drawCircle(
          Offset(inner.dx + dir * ew * 0.04, inner.dy + eh * 0.05), eh * 0.14, stroke(a9 * 0.7));
      final lower = Path()
        ..moveTo(inner.dx + dir * ew * 0.1, inner.dy + eh * 0.55)
        ..quadraticBezierTo(
            e.dx, e.dy + eh * 1.6, outer.dx - dir * ew * 0.08, outer.dy + eh * 0.25);
      canvas.drawPath(lower, stroke(a9 * 0.45));
    }
  }

  // 10 — sobrancelhas (cabeça, arco e cauda)
  final a10 = layer(10);
  if (a10 > 0.01) {
    for (final e in [g.eyeL, g.eyeR]) {
      final dir = e.dx < midX ? -1.0 : 1.0;
      final b0 = Offset(e.dx - dir * ew * 0.62, e.dy - eh * 2.3);
      final b1 = Offset(e.dx + dir * ew * 0.8, e.dy - eh * 1.9);
      Path curve(double lift) => Path()
        ..moveTo(b0.dx, b0.dy + lift)
        ..cubicTo(b0.dx + dir * ew * 0.3, b0.dy - eh * 0.9 + lift,
            b1.dx - dir * ew * 0.35, b1.dy - eh * 1.0 + lift * 0.4, b1.dx, b1.dy + lift * 0.1);
      canvas.drawPath(curve(0), stroke(a10, w: 1.1));
      canvas.drawPath(curve(eh * 0.55), stroke(a10 * 0.7));
      canvas.drawPath(curve(-eh * 0.25), stroke(a10 * 0.4));
    }
  }

  // 11 — nariz (ponte, bola, asas e narinas)
  final a11 = layer(11);
  if (a11 > 0.01) {
    canvas.drawLine(Offset(ax - nh * 0.35, cy), Offset(ax - nh, g.noseY), stroke(a11));
    canvas.drawLine(Offset(ax + nh * 0.35, cy), Offset(ax + nh, g.noseY), stroke(a11));
    canvas.drawLine(Offset(ax - nh, g.noseY), Offset(ax + nh, g.noseY), stroke(a11 * 0.8));
    canvas.drawCircle(Offset(ax, g.noseY - u * 0.08), nh * 0.34, stroke(a11 * 0.9));
    canvas.drawCircle(
        Offset(ax - nh * 0.1, g.noseY - u * 0.12), nh * 0.08, fill(a11 * 0.8));
    for (final s in [-1.0, 1.0]) {
      canvas.drawOval(
        Rect.fromCenter(
            center: Offset(ax + s * nh * 0.92, g.noseY - u * 0.1),
            width: nh * 0.55,
            height: u * 0.3),
        stroke(a11 * 0.9),
      );
      canvas.drawOval(
        Rect.fromCenter(
            center: Offset(ax + s * nh * 0.38, g.noseY - u * 0.02),
            width: nh * 0.32,
            height: u * 0.12),
        stroke(a11 * 0.9),
      );
      final wing = Path()
        ..moveTo(ax + s * nh * 0.45, g.noseY - u * 0.28)
        ..quadraticBezierTo(
            ax + s * nh * 1.25, g.noseY - u * 0.3, ax + s * nh * 1.05, g.noseY + u * 0.02);
      canvas.drawPath(wing, stroke(a11 * 0.7));
    }
  }

  // 12 — boca (lábios, comissuras, filtro e sulco do queixo)
  final a12 = layer(12);
  if (a12 > 0.01) {
    for (final s in [-1.0, 1.0]) {
      canvas.drawLine(Offset(ax + s * nh * 0.2, g.noseY),
          Offset(m.dx + s * mh * 0.2, m.dy - u * 0.1), stroke(a12 * 0.5));
      canvas.drawCircle(Offset(m.dx + s * mh, m.dy), u * 0.025, fill(a12 * 0.8));
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
    final lowerOuter = Path()
      ..moveTo(m.dx - mh * 0.8, m.dy + u * 0.08)
      ..quadraticBezierTo(m.dx, m.dy + u * 0.46, m.dx + mh * 0.8, m.dy + u * 0.08);
    canvas.drawPath(upper, stroke(a12));
    canvas.drawPath(lower, stroke(a12));
    canvas.drawPath(center, stroke(a12, w: 1.2));
    canvas.drawPath(lowerOuter, stroke(a12 * 0.5));
    final crease = Path()
      ..moveTo(m.dx - mh * 0.35, m.dy + u * 0.58)
      ..quadraticBezierTo(m.dx, m.dy + u * 0.64, m.dx + mh * 0.35, m.dy + u * 0.58);
    canvas.drawPath(crease, stroke(a12 * 0.5));
  }

  // 13 — cabelo (massa, risca e direção dos fios)
  final a13 = layer(13);
  if (a13 > 0.01) {
    final hr = r * 1.16;
    canvas.drawArc(Rect.fromCircle(center: g.center, radius: hr), math.pi, math.pi,
        false, stroke(a13, w: 1.2));
    for (final s in [-1.0, 1.0]) {
      canvas.drawLine(Offset(cx + s * hr, cy),
          Offset(cx + s * r * 1.04, earLineY - 0.25 * u), stroke(a13 * 0.8));
      for (var k = 0; k < 4; k++) {
        final start = Offset(cx + s * r * 0.12 * k, cy - hr * 0.97);
        final end = Offset(cx + s * hr * (0.78 + 0.06 * k), cy - hr * 0.12 + k * u * 0.12);
        final ctrl = Offset(cx + s * hr * (0.35 + 0.12 * k), cy - hr * 1.02);
        final strand = Path()
          ..moveTo(start.dx, start.dy)
          ..quadraticBezierTo(ctrl.dx, ctrl.dy, end.dx, end.dy);
        canvas.drawPath(strand, stroke(a13 * 0.4));
      }
    }
    final (hlo, hhi) = g.lineAt(g.hairY + 0.25 * u);
    final hairline = Path()
      ..moveTo(hlo.dx, hlo.dy)
      ..quadraticBezierTo(cx, g.hairY - 0.3 * u, hhi.dx, hhi.dy);
    canvas.drawPath(hairline, stroke(a13 * 0.8));
  }

  // 14 — expressão e detalhes finos (sulcos, olheiras, rugas, covinha)
  final a14 = layer(14);
  if (a14 > 0.01) {
    for (final s in [-1.0, 1.0]) {
      final fold = Path()
        ..moveTo(ax + s * nh * 1.35, g.noseY - u * 0.05)
        ..quadraticBezierTo(ax + s * nh * 2.0, (g.noseY + m.dy) / 2,
            m.dx + s * mh * 1.25, m.dy + u * 0.05);
      canvas.drawPath(fold, stroke(a14 * 0.5));
      final e = s < 0 ? g.eyeL : g.eyeR;
      final bag = Path()
        ..moveTo(e.dx - ew * 0.45, e.dy + eh * 1.7)
        ..quadraticBezierTo(e.dx, e.dy + eh * 2.5, e.dx + ew * 0.45, e.dy + eh * 1.7);
      canvas.drawPath(bag, stroke(a14 * 0.4));
      canvas.drawCircle(Offset(e.dx, g.noseY - u * 0.35), u * 0.28, stroke(a14 * 0.3));
    }
    for (var i = 1; i <= 3; i++) {
      final y = g.hairY + (cy - u * 0.45 - g.hairY) * i / 4;
      final (lo, hi) = g.lineAt(y);
      final w = (hi.dx - lo.dx) * 0.28;
      final line = Path()
        ..moveTo(ax - w, y)
        ..quadraticBezierTo(ax, y - u * 0.06, ax + w, y);
      canvas.drawPath(line, stroke(a14 * 0.3));
    }
    final dimple = Path()
      ..moveTo(ax - u * 0.1, g.chinY - u * 0.28)
      ..quadraticBezierTo(ax, g.chinY - u * 0.22, ax + u * 0.1, g.chinY - u * 0.28);
    canvas.drawPath(dimple, stroke(a14 * 0.4));
  }

  // 15 — contorno e detalhes (do detector)
  final a15 = layer(15);
  if (a15 > 0.01) {
    canvas.drawPath(_smoothClosed(g.contour), stroke(a15, w: 1.4));
    for (final f in g.features) {
      final path = Path()..moveTo(f.first.dx, f.first.dy);
      for (final pt in f.skip(1)) {
        path.lineTo(pt.dx, pt.dy);
      }
      canvas.drawPath(path, stroke(a15 * 0.9));
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
