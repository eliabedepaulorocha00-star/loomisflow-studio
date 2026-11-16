import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:loomisflow_studio/core/figure_guide.dart';
import 'package:loomisflow_studio/core/loomis_guide.dart';

void main() {
  const size = Size(1000, 1600);
  final pts = <String, Offset>{
    'lSh': const Offset(600, 400),
    'rSh': const Offset(400, 400),
    'lHip': const Offset(570, 800),
    'rHip': const Offset(430, 800),
    'nose': const Offset(500, 250),
  };

  test('guia de corpo exige ombros e quadris', () {
    expect(FigureGuide.canBuild(pts), isTrue);
    expect(FigureGuide.canBuild({'lSh': const Offset(1, 1)}), isFalse);
  });

  test('proporções básicas', () {
    final f = FigureGuide(size, pts);
    expect(f.shoulderWidth, closeTo(200, 1e-9));
    expect(f.torsoLen, closeTo(400, 1e-9));
    expect(f.headH, greaterThan(0));
    expect(f.looksLikeBody, isFalse); // sem joelhos: só tronco
  });

  test('JSON ida e volta', () {
    final f = FigureGuide(size, pts);
    expect(FigureGuide.fromJson(f.toJson()).toJson(), equals(f.toJson()));
  });

  test('quantidade de passos', () {
    expect(kStepNames.length, 11);
    expect(kStepCount, 11);
    expect(kMaxStep, 10);
    expect(kBodyStepNames.length, 7);
  });
}
