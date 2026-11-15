import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:loomisflow_studio/core/loomis_guide.dart';
import 'package:loomisflow_studio/core/models.dart';

List<Offset> ellipse(Offset c, double rx, double ry, [int n = 36]) => [
      for (var i = 0; i < n; i++)
        Offset(c.dx + rx * math.cos(2 * math.pi * i / n),
            c.dy + ry * math.sin(2 * math.pi * i / n)),
    ];

void main() {
  const size = Size(1000, 1400);

  test('guia padrão respeita os terços de Loomis', () {
    final g = LoomisGuide.fallback(size);
    expect(g.detected, isFalse);
    expect(g.noseY - g.browY, closeTo(g.chinY - g.noseY, 1e-9));
    expect(g.hairY, lessThan(g.browY));
  });

  test('JSON ida e volta preserva a guia', () {
    final g = LoomisGuide.fallback(size);
    final g2 = LoomisGuide.fromJson(g.toJson());
    expect(g2.toJson(), equals(g.toJson()));
  });

  test('medidas de um rosto frontal viram linhas na ordem certa', () {
    final m = FaceMeasurements(
      eyeA: const Offset(400, 500),
      eyeB: const Offset(600, 500),
      nose: const Offset(500, 640),
      mouthLeft: const Offset(440, 720),
      mouthRight: const Offset(560, 720),
      mouthBottom: const Offset(500, 740),
      face: ellipse(const Offset(500, 600), 220, 330),
      brows: const [Offset(430, 450), Offset(570, 450)],
    );
    final g = LoomisGuide.fromMeasurements(m, size);
    expect(g.detected, isTrue);
    expect(g.roll, closeTo(0, 1e-9));
    expect(g.yaw, closeTo(0, 1e-9));
    expect(g.browY, closeTo(-50, 1e-6));
    expect(g.chinY, closeTo(430, 1e-6));
    expect(g.hairY, lessThan(g.browY));
    expect(g.noseY, greaterThan(g.browY));
    expect(g.noseY, lessThan(g.chinY));

    final (lo, hi) = g.lineAt(g.noseY);
    expect(hi.dx, greaterThan(lo.dx));
  });

  test('cabeça inclinada: referencial local volta para a imagem', () {
    final m = FaceMeasurements(
      eyeA: const Offset(400, 500),
      eyeB: const Offset(600, 600),
    );
    final g = LoomisGuide.fromMeasurements(m, size);
    expect(g.roll, closeTo(math.atan2(100, 200), 1e-9));
    final o = g.toImage(Offset.zero);
    expect(o.dx, closeTo(500, 1e-6));
    expect(o.dy, closeTo(550, 1e-6));
    final r = g.toImage(g.eyeR);
    expect(r.dx, closeTo(600, 1e-6));
    expect(r.dy, closeTo(600, 1e-6));
  });

  test('traço serializa com 1 casa decimal', () {
    final s = StrokeData(
      points: const [Offset(1.04, 2.06), Offset(3, 4)],
      color: 0xFF000000,
      width: 2,
    );
    final back = StrokeData.fromJson(s.toJson());
    expect(back.points.first.dx, closeTo(1.0, 1e-9));
    expect(back.points.first.dy, closeTo(2.1, 1e-9));
    expect(back.points.length, 2);
  });
}
