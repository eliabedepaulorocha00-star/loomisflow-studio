import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import 'face_analyzer.dart';
import 'figure_guide.dart';
import 'image_utils.dart';
import 'loomis_guide.dart';
import 'models.dart';
import 'pose_analyzer.dart';
import 'storage.dart';

enum GuideKind { face, body }

class _Analysis {
  _Analysis(this.guide, this.figure, this.note);
  final LoomisGuide guide;
  final FigureGuide? figure;
  final String note;
}

/// Estado global simples (sem pacotes extras): lista de projetos + projeto atual.
class AppState extends ChangeNotifier {
  final ProjectStore store = ProjectStore.instance;
  final FaceAnalyzer _faces = FaceAnalyzer();
  final PoseAnalyzer _pose = PoseAnalyzer();

  List<Project> projects = [];
  Project? current;
  ui.Image? currentReference;
  ui.Image? currentShading;

  bool busy = false;
  String busyLabel = '';
  String detectionNote = '';
  String? detectionProjectId;

  Future<void> load() async {
    projects = await store.list();
    notifyListeners();
  }

  /// Foto (bytes) → normaliza → detecta rosto/corpo → monta guia → sombreamento → salva.
  Future<void> createFromBytes(Uint8List raw) async {
    busy = true;
    busyLabel = 'Preparando a imagem…';
    notifyListeners();
    try {
      final jpeg = await compute(normalizeImage, raw);
      final decoded = await _decode(jpeg);
      final size = Size(decoded.width.toDouble(), decoded.height.toDouble());

      busyLabel = 'Analisando a imagem no aparelho…';
      notifyListeners();
      final tmp = File('${(await store.exportDir()).path}/_analyze.jpg');
      await tmp.writeAsBytes(jpeg, flush: true);
      final a = await _analyze(tmp.path, size);

      busyLabel = 'Gerando mapa de luz e sombra…';
      notifyListeners();
      final shading = await compute(buildShadingPng, jpeg);

      final pr = await store.create(
        jpeg: jpeg,
        shadingPng: shading,
        guide: a.guide,
        figure: a.figure,
      );
      projects.insert(0, pr);
      _setNote(pr, a.note);
      await open(pr);
    } finally {
      busy = false;
      notifyListeners();
    }
  }

  /// Refaz a análise de um projeto já salvo. [force] escolhe rosto ou corpo.
  Future<void> reanalyze(Project pr, {GuideKind? force}) async {
    busy = true;
    busyLabel = 'Reanalisando…';
    notifyListeners();
    try {
      final a = await _analyze(pr.referencePath, pr.guide.imageSize, force: force);
      pr.guide = a.guide;
      pr.figure = a.figure;
      pr.resetAdjust();
      pr.step = math.min(pr.step, pr.maxStep);
      await store.saveMeta(pr);
      _setNote(pr, a.note);
      await open(pr);
    } finally {
      busy = false;
      notifyListeners();
    }
  }

  void _setNote(Project pr, String note) {
    detectionNote = note.length > 360 ? '${note.substring(0, 360)}…' : note;
    detectionProjectId = pr.id;
  }

  Future<_Analysis> _analyze(String path, Size size, {GuideKind? force}) async {
    // rosto
    FaceMeasurements? m;
    var note = '';
    if (force != GuideKind.body) {
      try {
        m = await _faces.analyze(path);
        if (m == null) note = _faces.lastNote;
      } catch (e) {
        m = null;
        note = 'erro: $e';
      }
    }
    LoomisGuide guide;
    try {
      guide = m == null
          ? LoomisGuide.fallback(size)
          : LoomisGuide.fromMeasurements(m, size);
    } catch (e) {
      guide = LoomisGuide.fallback(size);
      note = 'erro ao montar a guia: $e';
    }

    // corpo (só se for pedido ou se a foto parecer um corpo)
    FigureGuide? figure;
    if (force != GuideKind.face) {
      try {
        final f = await _pose.analyze(path, size);
        final wantBody = force == GuideKind.body ? f != null : (f != null && f.looksLikeBody);
        if (wantBody) {
          figure = f;
          note = '';
        } else if (force == GuideKind.body) {
          note = _pose.lastNote.isEmpty ? 'pose: não foi possível montar o corpo' : _pose.lastNote;
        }
      } catch (e) {
        if (force == GuideKind.body) note = 'pose: $e';
      }
    }
    return _Analysis(guide, figure, note);
  }

  Future<void> open(Project pr) async {
    current = pr;
    currentReference = await _decode(await File(pr.referencePath).readAsBytes());
    final sf = File(pr.shadingPath);
    currentShading = await sf.exists() ? await _decode(await sf.readAsBytes()) : null;
    notifyListeners();
  }

  Future<void> saveStep(Project pr) => store.saveMeta(pr);

  Future<void> delete(Project pr) async {
    await store.delete(pr);
    projects.removeWhere((e) => e.id == pr.id);
    if (current?.id == pr.id) {
      current = null;
      currentReference = null;
      currentShading = null;
    }
    notifyListeners();
  }

  void touch() => notifyListeners();

  static Future<ui.Image> _decode(Uint8List bytes) async {
    final codec = await ui.instantiateImageCodec(bytes);
    return (await codec.getNextFrame()).image;
  }
}

class AppScope extends InheritedNotifier<AppState> {
  const AppScope({super.key, required AppState state, required super.child})
      : super(notifier: state);

  static AppState of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<AppScope>()!.notifier!;
}
