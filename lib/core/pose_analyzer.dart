import 'dart:ui';

import 'package:google_mlkit_pose_detection/google_mlkit_pose_detection.dart';

import 'figure_guide.dart';

/// Detecção de pose 100% no aparelho (Google ML Kit, gratuito, sem rede).
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
    final detector = PoseDetector(
      options: PoseDetectorOptions(
        mode: PoseDetectionMode.single,
        model: PoseDetectionModel.accurate,
      ),
    );
    try {
      final poses = await detector.processImage(InputImage.fromFilePath(path));
      if (poses.isEmpty) {
        lastNote = 'pose: nenhuma pessoa encontrada';
        return null;
      }
      final lm = poses.first.landmarks;
      final pts = <String, Offset>{};
      _names.forEach((key, type) {
        final l = lm[type];
        if (l == null || l.likelihood < 0.45) return;
        final x = l.x, y = l.y;
        // pontos "chutados" fora da foto não contam
        if (x < -size.width * 0.02 || x > size.width * 1.02) return;
        if (y < -size.height * 0.02 || y > size.height * 1.02) return;
        pts[key] = Offset(x, y);
      });
      if (!FigureGuide.canBuild(pts)) {
        lastNote = 'pose: ombros e quadris não estão visíveis (${pts.length} pontos)';
        return null;
      }
      lastNote = '';
      return FigureGuide(size, pts);
    } catch (e) {
      lastNote = 'pose: $e';
      return null;
    } finally {
      await detector.close();
    }
  }
}
