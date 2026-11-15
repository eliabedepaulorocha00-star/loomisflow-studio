import 'dart:ui';

import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';

import 'loomis_guide.dart';

/// Detecção facial 100% no aparelho (Google ML Kit, gratuito, sem rede).
///
/// Tenta primeiro o modo preciso (com contornos) e depois um modo simples.
/// Quando nada é detectado, [lastNote] guarda o motivo (para diagnóstico).
class FaceAnalyzer {
  String lastNote = '';

  Future<FaceMeasurements?> analyze(String path) async {
    final attempts = <(String, FaceDetectorOptions)>[
      (
        'preciso',
        FaceDetectorOptions(
          enableContours: true,
          enableLandmarks: true,
          performanceMode: FaceDetectorMode.accurate,
          minFaceSize: 0.05,
        ),
      ),
      (
        'simples',
        FaceDetectorOptions(
          enableLandmarks: true,
          performanceMode: FaceDetectorMode.fast,
          minFaceSize: 0.05,
        ),
      ),
    ];

    final notes = <String>[];
    for (final (name, options) in attempts) {
      final detector = FaceDetector(options: options);
      try {
        final faces =
            await detector.processImage(InputImage.fromFilePath(path));
        if (faces.isEmpty) {
          notes.add('$name: 0 rostos');
          continue;
        }
        final list = [...faces]..sort((a, b) =>
            (b.boundingBox.width * b.boundingBox.height)
                .compareTo(a.boundingBox.width * a.boundingBox.height));
        try {
          final m = _measure(list.first);
          lastNote = '';
          return m;
        } catch (e) {
          notes.add('$name: erro ao medir ($e)');
        }
      } catch (e) {
        notes.add('$name: $e');
      } finally {
        await detector.close();
      }
    }
    lastNote = notes.join(' | ');
    return null;
  }

  Offset? _lm(Face f, FaceLandmarkType t) {
    final p = f.landmarks[t]?.position;
    return p == null ? null : Offset(p.x.toDouble(), p.y.toDouble());
  }

  List<Offset> _ct(Face f, FaceContourType t) {
    final pts = f.contours[t]?.points;
    if (pts == null) return const [];
    return [for (final p in pts) Offset(p.x.toDouble(), p.y.toDouble())];
  }

  FaceMeasurements _measure(Face f) {
    final box = f.boundingBox;
    final eyeA = _lm(f, FaceLandmarkType.leftEye) ??
        Offset(box.center.dx - box.width * 0.2, box.top + box.height * 0.4);
    final eyeB = _lm(f, FaceLandmarkType.rightEye) ??
        Offset(box.center.dx + box.width * 0.2, box.top + box.height * 0.4);

    final brows = [
      ..._ct(f, FaceContourType.leftEyebrowBottom),
      ..._ct(f, FaceContourType.rightEyebrowBottom),
    ];

    final features = <List<Offset>>[
      _ct(f, FaceContourType.leftEyebrowTop),
      _ct(f, FaceContourType.rightEyebrowTop),
      _ct(f, FaceContourType.leftEye),
      _ct(f, FaceContourType.rightEye),
      _ct(f, FaceContourType.noseBridge),
      _ct(f, FaceContourType.noseBottom),
      _ct(f, FaceContourType.upperLipTop),
      _ct(f, FaceContourType.lowerLipBottom),
    ].where((l) => l.length >= 2).toList();

    return FaceMeasurements(
      eyeA: eyeA,
      eyeB: eyeB,
      nose: _lm(f, FaceLandmarkType.noseBase),
      mouthLeft: _lm(f, FaceLandmarkType.leftMouth),
      mouthRight: _lm(f, FaceLandmarkType.rightMouth),
      mouthBottom: _lm(f, FaceLandmarkType.bottomMouth),
      face: _ct(f, FaceContourType.face),
      brows: brows,
      features: features,
    );
  }
}
