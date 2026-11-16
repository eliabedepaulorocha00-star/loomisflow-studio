import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'figure_guide.dart';
import 'loomis_guide.dart';
import 'models.dart';

/// Armazenamento local (nada sai do aparelho). Cada projeto é uma pasta:
/// reference.jpg, shading.png, meta.json, strokes.json.
class ProjectStore {
  ProjectStore._();
  static final ProjectStore instance = ProjectStore._();

  late Directory _root;

  Future<void> init() async {
    final docs = await getApplicationDocumentsDirectory();
    _root = Directory(p.join(docs.path, 'projects'));
    await _root.create(recursive: true);
  }

  Future<List<Project>> list() async {
    final out = <Project>[];
    await for (final e in _root.list()) {
      if (e is! Directory) continue;
      final pr = await _load(e.path);
      if (pr != null) out.add(pr);
    }
    out.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    return out;
  }

  Future<Project?> _load(String dir) async {
    try {
      final metaFile = File(p.join(dir, 'meta.json'));
      if (!await metaFile.exists()) return null;
      final j = jsonDecode(await metaFile.readAsString()) as Map<String, dynamic>;
      final adj = ((j['adj'] as List?) ?? const [0, 0, 1, 0]).cast<num>();
      final fig = j['figure'];
      final pr = Project(
        id: j['id'] as String,
        title: j['title'] as String,
        createdAt: DateTime.parse(j['created'] as String),
        updatedAt: DateTime.parse(j['updated'] as String),
        guide: LoomisGuide.fromJson(j['guide'] as Map<String, dynamic>),
        figure: fig == null ? null : FigureGuide.fromJson(fig as Map<String, dynamic>),
        dir: dir,
        step: (j['step'] as num?)?.toDouble() ?? 0,
        paper: (j['paper'] as int?) ?? 0xFFF5F2EA,
        adjDx: adj[0].toDouble(),
        adjDy: adj[1].toDouble(),
        adjScale: adj[2].toDouble(),
        adjRot: adj[3].toDouble(),
      );
      if (pr.step > pr.maxStep) pr.step = pr.maxStep;
      final sf = File(pr.strokesPath);
      if (await sf.exists()) {
        final list = jsonDecode(await sf.readAsString()) as List;
        pr.strokes.addAll(
          list.map((e) => StrokeData.fromJson(e as Map<String, dynamic>)),
        );
      }
      return pr;
    } catch (_) {
      return null; // projeto corrompido: ignora em vez de travar o app
    }
  }

  Future<Project> create({
    required Uint8List jpeg,
    required Uint8List shadingPng,
    required LoomisGuide guide,
    FigureGuide? figure,
    String? title,
  }) async {
    final now = DateTime.now();
    final id = now.microsecondsSinceEpoch.toString();
    final dir = p.join(_root.path, id);
    await Directory(dir).create(recursive: true);
    final pr = Project(
      id: id,
      title: title ??
          'Retrato ${now.day.toString().padLeft(2, '0')}/${now.month.toString().padLeft(2, '0')} '
              '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}',
      createdAt: now,
      updatedAt: now,
      guide: guide,
      figure: figure,
      dir: dir,
    );
    await File(pr.referencePath).writeAsBytes(jpeg, flush: true);
    await File(pr.shadingPath).writeAsBytes(shadingPng, flush: true);
    await saveMeta(pr);
    await saveStrokes(pr);
    return pr;
  }

  Future<void> saveMeta(Project pr) async {
    pr.updatedAt = DateTime.now();
    await _atomicWrite(pr.metaPath, jsonEncode(pr.toMetaJson()));
  }

  Future<void> saveStrokes(Project pr) async {
    await _atomicWrite(
      pr.strokesPath,
      jsonEncode([for (final s in pr.strokes) s.toJson()]),
    );
    await saveMeta(pr);
  }

  Future<void> delete(Project pr) async {
    final d = Directory(pr.dir);
    if (await d.exists()) await d.delete(recursive: true);
  }

  /// Pasta temporária para arquivos de exportação.
  Future<Directory> exportDir() async {
    final tmp = await getTemporaryDirectory();
    final d = Directory(p.join(tmp.path, 'exports'));
    await d.create(recursive: true);
    return d;
  }

  Future<void> _atomicWrite(String path, String content) async {
    final tmp = File('$path.tmp');
    await tmp.writeAsString(content, flush: true);
    await tmp.rename(path);
  }
}
