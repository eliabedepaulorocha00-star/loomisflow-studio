import 'dart:ui';

import 'package:path/path.dart' as p;

import 'loomis_guide.dart';

/// Um traço desenhado pelo usuário (em coordenadas da imagem).
class StrokeData {
  StrokeData({required this.points, required this.color, required this.width});

  final List<Offset> points;
  final int color; // ARGB
  final double width;

  static double _r(double v) => (v * 10).roundToDouble() / 10;

  Map<String, dynamic> toJson() => {
        'c': color,
        'w': width,
        'p': [
          for (final o in points) ...[_r(o.dx), _r(o.dy)],
        ],
      };

  factory StrokeData.fromJson(Map<String, dynamic> j) {
    final raw = (j['p'] as List).cast<num>();
    return StrokeData(
      color: j['c'] as int,
      width: (j['w'] as num).toDouble(),
      points: [
        for (var i = 0; i + 1 < raw.length; i += 2)
          Offset(raw[i].toDouble(), raw[i + 1].toDouble()),
      ],
    );
  }
}

/// Um projeto = uma foto de referência + guia Loomis + esboço do usuário.
class Project {
  Project({
    required this.id,
    required this.title,
    required this.createdAt,
    required this.updatedAt,
    required this.guide,
    required this.dir,
    this.step = 0,
    this.paper = 0xFFF5F2EA,
    List<StrokeData>? strokes,
  }) : strokes = strokes ?? [];

  final String id;
  String title;
  final DateTime createdAt;
  DateTime updatedAt;
  LoomisGuide guide;
  final String dir;
  double step;
  int paper; // cor do papel (ARGB) do esboço
  final List<StrokeData> strokes;

  String get referencePath => p.join(dir, 'reference.jpg');
  String get shadingPath => p.join(dir, 'shading.png');
  String get metaPath => p.join(dir, 'meta.json');
  String get strokesPath => p.join(dir, 'strokes.json');

  Map<String, dynamic> toMetaJson() => {
        'id': id,
        'title': title,
        'created': createdAt.toIso8601String(),
        'updated': updatedAt.toIso8601String(),
        'step': step,
        'paper': paper,
        'guide': guide.toJson(),
      };
}
