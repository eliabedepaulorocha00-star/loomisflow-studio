import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import 'face_analyzer.dart';
import 'image_utils.dart';
import 'loomis_guide.dart';
import 'models.dart';
import 'storage.dart';

/// Estado global simples (sem pacotes extras): lista de projetos + projeto atual.
class AppState extends ChangeNotifier {
  final ProjectStore store = ProjectStore.instance;
  final FaceAnalyzer _faces = FaceAnalyzer();

  List<Project> projects = [];
  Project? current;
  ui.Image? currentReference;
  ui.Image? currentShading;

  bool busy = false;
  String detectionNote = '';
  String? detectionProjectId;
  String busyLabel = '';

  Future<void> load() async {
    projects = await store.list();
    notifyListeners();
  }

  /// Foto (bytes) → normaliza → detecta rosto → monta guia → sombreamento → salva.
  Future<void> createFromBytes(Uint8List raw) async {
    busy = true;
    busyLabel = 'Preparando a imagem…';
    notifyListeners();
    try {
      final jpeg = await compute(normalizeImage, raw);
      final decoded = await _decode(jpeg);
      final size = Size(decoded.width.toDouble(), decoded.height.toDouble());

      busyLabel = 'Analisando o rosto no aparelho…';
      notifyListeners();
      final tmp = File('${(await store.exportDir()).path}/_analyze.jpg');
      await tmp.writeAsBytes(jpeg, flush: true);
      FaceMeasurements? m;
      var note = '';
      try {
        m = await _faces.analyze(tmp.path);
        if (m == null) note = _faces.lastNote;
      } catch (e) {
        m = null; // sem ML Kit disponível: cai no guia padrão
        note = 'erro: $e';
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

      busyLabel = 'Gerando mapa de luz e sombra…';
      notifyListeners();
      final shading = await compute(buildShadingPng, jpeg);

      final pr = await store.create(jpeg: jpeg, shadingPng: shading, guide: guide);
      projects.insert(0, pr);
      detectionNote = note.length > 360 ? '${note.substring(0, 360)}…' : note;
      detectionProjectId = pr.id;
      await open(pr);
    } finally {
      busy = false;
      notifyListeners();
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
