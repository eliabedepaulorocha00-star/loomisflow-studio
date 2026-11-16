import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../../core/guide_renderer.dart';
import '../../core/theme.dart';
import 'trace_model.dart';

class TracePainter extends CustomPainter {
  TracePainter(this.m, this.reference, this.shading) : super(repaint: m);

  final TraceModel m;
  final ui.Image? reference;
  final ui.Image? shading;

  @override
  void paint(Canvas canvas, Size size) {
    final g = m.project.guide;
    final img = g.imageSize;
    final rect = Offset.zero & img;

    canvas.save();
    canvas.translate(m.t.dx, m.t.dy);
    canvas.scale(m.k);

    // papel
    canvas.drawRect(rect, Paint()..color = Color(m.project.paper));
    canvas.save();
    canvas.clipRect(rect);

    // decalque: foto + guia (+ grade) com transformação própria
    final c = img.center(Offset.zero);
    canvas.save();
    canvas.translate(c.dx + m.ovOff.dx, c.dy + m.ovOff.dy);
    canvas.rotate(m.ovRot);
    canvas.scale(m.ovScale);
    canvas.translate(-c.dx, -c.dy);

    if (reference != null && m.refOpacity > 0.01) {
      canvas.drawImageRect(
        reference!,
        Rect.fromLTWH(
            0, 0, reference!.width.toDouble(), reference!.height.toDouble()),
        rect,
        Paint()
          ..filterQuality = FilterQuality.medium
          ..color = Color.fromRGBO(255, 255, 255, m.refOpacity),
      );
    }
    final screenLine = 1 / (m.k * m.ovScale);
    if (m.grid) {
      paintGrid(canvas, img,
          color: const Color(0xFF3A6BFF), opacity: 0.45, lineScale: screenLine);
    }
    if (m.guideOpacity > 0.01) {
      paintProjectGuide(
        canvas,
        m.project,
        m.step,
        color: const Color(0xFF00B88A),
        opacity: m.guideOpacity,
        lineScale: screenLine * 0.7,
        shading: shading,
      );
    }
    canvas.restore();

    // esboço do usuário (por cima, fixo no papel)
    paintStrokes(canvas, m.project.strokes, m.live);
    canvas.restore(); // clip

    canvas.drawRect(
      rect,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5 / m.k
        ..color = Palette.line,
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant TracePainter old) =>
      old.reference != reference || old.shading != shading;
}
