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

enum GuideKind { face, body, bodyTemplate }

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

  /// Estilo de corpo usado ao criar guias de corpo (masculino, feminino, anime…).
  BodyStyle bodyStyle = BodyStyle.male;

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
  Future<void> reanalyze(Project pr, {GuideKind? force, BodyStyle? style}) async {
    busy = true;
    busyLabel = 'Reanalisando…';
    notifyListeners();
    try {
      final a = await _analyze(pr.referencePath, pr.guide.imageSize,
          force: force, style: style);
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

  /// Troca o estilo do corpo (masculino/feminino/anime). Se o projeto ainda não
  /// tem guia de corpo, cria uma.
  Future<void> setBodyStyle(Project pr, BodyStyle s) async {
    bodyStyle = s;
    final f = pr.figure;
    if (f != null && !f.isTemplate) {
      pr.figure = f.withStyle(s);
      await store.saveMeta(pr);
      notifyListeners();
      return;
    }
    await reanalyze(pr, force: GuideKind.body, style: s);
  }

  Future<_Analysis> _analyze(String path, Size size,
      {GuideKind? force, BodyStyle? style}) async {
    final st = style ?? bodyStyle;
    // rosto
    FaceMeasurements? m;
    var note = '';
    if (force != GuideKind.bodyTemplate) {
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
      FigureGuide? f;
      if (force != GuideKind.bodyTemplate) {
        try {
          f = await _pose.analyze(path, size);
        } catch (e) {
          if (force == GuideKind.body) note = 'pose: $e';
        }
      }
      final wantBody = force == GuideKind.body || force == GuideKind.bodyTemplate
          ? true
          : (f != null && f.looksLikeBody);
      if (wantBody) {
        if (f != null) {
          figure = f.completed().withStyle(st);
          note = '';
        } else {
          // sem pose: tenta o rosto (se o corpo coubrir na foto), depois o
          // contorno do personagem sobre o fundo, depois a foto inteira
          FigureGuide? built;
          var how = '';
          if (force != GuideKind.bodyTemplate && m != null && guide.detected) {
            final top = guide.center.dy - guide.radius;
            final hh = guide.chinY - top;
            final hc = guide.toImage(Offset(guide.center.dx, (guide.chinY + top) / 2));
            final bottom = hc.dy - hh * 0.5 + hh * st.spec.total;
            if (bottom <= size.height * 1.12 && hh > size.height * 0.05) {
              built = FigureGuide.template(size, style: st, headCenter: hc, headH: hh);
              how = 'a partir do rosto';
            }
          }
          if (built == null) {
            final sb = await _subject(path);
            if (sb != null) {
              built = FigureGuide.template(size, style: st, fit: sb);
              how = 'ajustado ao personagem';
            }
          }
          if (built == null) {
            built = FigureGuide.template(size, style: st);
            how = 'na foto inteira';
          }
          figure = built;
          note = force == GuideKind.bodyTemplate
              ? ''
              : 'Pose não detectada — montei o corpo $how. '
                  'Use "Ajustar guia" para encaixar melhor.';
        }
      }
    }
    return _Analysis(guide, figure, note);
  }

  /// Retângulo (em pixels da imagem) onde está o personagem, ou null.
  Future<Rect?> _subject(String path) async {
    try {
      final bytes = await File(path).readAsBytes();
      final dec = await _decode(bytes);
      final w = dec.width.toDouble(), h = dec.height.toDouble();
      final f = await compute(subjectBounds, bytes);
      if (f == null) return null;
      return Rect.fromLTRB(f[0] * w, f[1] * h, f[2] * w, f[3] * h);
    } catch (_) {
      return null;
    }
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
