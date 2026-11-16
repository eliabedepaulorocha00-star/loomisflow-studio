import 'dart:io';
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:google_mlkit_pose_detection/google_mlkit_pose_detection.dart';

import 'figure_guide.dart';
import 'image_utils.dart';

/// Detecção de pose 100% no aparelho (Google ML Kit, gratuito, sem rede).
///
/// Tenta várias vezes antes de desistir: modelo preciso na foto original,
/// limiar de confiança mais baixo e a foto com margem em volta (ajuda quando o
/// corpo está colado nas bordas).
class PoseAnalyzer {
  String lastNote = '';

  static const _names = <String, PoseLandmarkType>{
    'nose': PoseLandmarkType.nose,
    'lEar': PoseLandmarkType.leftEar,
    'rEar': PoseLandmarkType.rightEar,
    'lSh': PoseLandmarkType.leftShoulder,
    'rSh': PoseLandmarkType.rightShoulder,
    'lEl': PoseLandmarkType.leftElbow,
    'rEl': PoseLandmarkType.rightElbow,
    'lWr': PoseLandmarkType.leftWrist,
    'rWr': PoseLandmarkType.rightWrist,
    'lHand': PoseLandmarkType.leftIndex,
    'rHand': PoseLandmarkType.rightIndex,
    'lHip': PoseLandmarkType.leftHip,
    'rHip': PoseLandmarkType.rightHip,
    'lKn': PoseLandmarkType.leftKnee,
    'rKn': PoseLandmarkType.rightKnee,
    'lAn': PoseLandmarkType.leftAnkle,
    'rAn': PoseLandmarkType.rightAnkle,
    'lFoot': PoseLandmarkType.leftFootIndex,
    'rFoot': PoseLandmarkType.rightFootIndex,
  };

  Future<FigureGuide?> analyze(String path, Size size) async {
    final notes = <String>[];

    // 1) foto original, 2) foto com margem
    for (final padded in [false, true]) {
      String usePath = path;
      double offX = 0, offY = 0;
      try {
        if (padded) {
          final bytes = await File(path).readAsBytes();
          final out = await compute(padForPose, bytes);
          usePath = '$path.pad.jpg';
          await File(usePath).writeAsBytes(out, flush: true);
          offX = size.width * 0.25;
          offY = size.height * 0.25;
        }
        for (final mode in [PoseDetectionMode.single]) {
          final r = await _run(usePath, size, offX, offY, mode, padded, notes);
          if (r != null) {
            lastNote = '';
            return r;
          }
        }
      } catch (e) {
        notes.add('pose${padded ? " (margem)" : ""}: $e');
      }
    }
    lastNote = notes.isEmpty ? 'pose: não foi possível montar o corpo' : notes.last;
    return null;
  }

  Future<FigureGuide?> _run(String path, Size size, double offX, double offY,
      PoseDetectionMode mode, bool padded, List<String> notes) async {
    final detector = PoseDetector(
      options: PoseDetectorOptions(mode: mode, model: PoseDetectionModel.accurate),
    );
    try {
      final poses = await detector.processImage(InputImage.fromFilePath(path));
      if (poses.isEmpty) {
        notes.add('pose: nenhuma pessoa encontrada');
        return null;
      }
      // várias pessoas: usa a que tem mais pontos confiáveis
      Map<String, Offset>? best;
      for (final pose in poses) {
        for (final minLike in [0.45, 0.25]) {
          final pts = <String, Offset>{};
          _names.forEach((key, type) {
            final l = pose.landmarks[type];
            if (l == null || l.likelihood < minLike) return;
            final x = l.x - offX, y = l.y - offY;
            // pontos "chutados" bem fora da foto não contam
            if (x < -size.width * 0.02 || x > size.width * 1.02) return;
            if (y < -size.height * 0.02 || y > size.height * 1.02) return;
            pts[key] = Offset(x, y);
          });
          if (FigureGuide.canBuild(pts) && (best == null || pts.length > best.length)) {
            best = pts;
          }
          if (best != null && minLike == 0.45) break;
        }
      }
      if (best == null) {
        notes.add('pose: ombros e quadris não estão visíveis');
        return null;
      }
      return FigureGuide(size, best);
    } finally {
      await detector.close();
    }
  }
}
