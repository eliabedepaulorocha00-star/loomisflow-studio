import 'dart:ui';

import 'package:path/path.dart' as p;

import 'figure_guide.dart';
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

/// Um projeto = uma foto de referência + guia (rosto ou corpo) + esboço do usuário.
class Project {
  Project({
    required this.id,
    required this.title,
    required this.createdAt,
    required this.updatedAt,
    required this.guide,
    required this.dir,
    this.figure,
    this.step = 0,
    this.paper = 0xFFF5F2EA,
    this.adjDx = 0,
    this.adjDy = 0,
    this.adjScale = 1,
    this.adjRot = 0,
    List<StrokeData>? strokes,
  }) : strokes = strokes ?? [];

  final String id;
  String title;
  final DateTime createdAt;
  DateTime updatedAt;
  LoomisGuide guide; // guia do rosto (sempre existe; no modo corpo fica de reserva)
  FigureGuide? figure; // se não for nulo, o projeto usa a guia de corpo
  final String dir;
  double step;
  int paper; // cor do papel (ARGB) do esboço
  final List<StrokeData> strokes;

  // ajuste manual da guia (mover / escalar / girar em torno do pivô)
  double adjDx, adjDy, adjScale, adjRot;

  List<String> get stepNames => figure != null ? kBodyStepNames : kStepNames;
  double get maxStep => stepNames.length - 1.0;

  Offset get pivot => figure?.center ?? guide.origin;

  bool get hasAdjust =>
      adjDx != 0 || adjDy != 0 || adjScale != 1 || adjRot != 0;

  void resetAdjust() {
    adjDx = 0;
    adjDy = 0;
    adjScale = 1;
    adjRot = 0;
  }

  /// Usado pelos painters para saber se precisam redesenhar.
  int get adjSig => Object.hash(adjDx, adjDy, adjScale, adjRot, figure != null);

  /// Aplica o ajuste manual ao canvas (translada, gira e escala em torno do pivô).
  void applyAdjust(Canvas canvas) {
    final pv = pivot;
    canvas.translate(pv.dx + adjDx, pv.dy + adjDy);
    canvas.rotate(adjRot);
    canvas.scale(adjScale);
    canvas.translate(-pv.dx, -pv.dy);
  }

  /// Desfaz exatamente o que [applyAdjust] fez (para desenhar a foto sem ajuste).
  void undoAdjust(Canvas canvas) {
    final pv = pivot;
    canvas.translate(pv.dx, pv.dy);
    canvas.scale(1 / adjScale);
    canvas.rotate(-adjRot);
    canvas.translate(-(pv.dx + adjDx), -(pv.dy + adjDy));
  }

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
        'figure': figure?.toJson(),
        'adj': [adjDx, adjDy, adjScale, adjRot],
      };
}
