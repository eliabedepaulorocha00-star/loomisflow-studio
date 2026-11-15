import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/foundation.dart';

import '../../core/models.dart';

/// Estado visual do estúdio de decalque. O painter escuta este objeto
/// (repaint: model), então gestos não precisam reconstruir a árvore de widgets.
class TraceModel extends ChangeNotifier {
  TraceModel(this.project) : step = project.step;

  final Project project;

  // Vista (zoom/arrasto da tela inteira): tela = t + k * pontoDaImagem
  double k = 1;
  Offset t = Offset.zero;
  double baseK = 1;
  Size viewSize = Size.zero;
  bool fitted = false;

  // Decalque (foto + guia) em espaço da imagem, em torno do centro da imagem.
  double ovScale = 1;
  double ovRot = 0; // radianos
  Offset ovOff = Offset.zero;

  double refOpacity = 0.5;
  double guideOpacity = 0.9;
  double step;
  bool grid = false;

  // Pincel
  int color = 0xFF1B1C22;
  double brushPx = 3; // espessura na tela (px) no momento do traço

  StrokeData? live;
  final List<StrokeData> redo = [];

  void changed() => notifyListeners();

  Offset toImage(Offset screen) => (screen - t) / k;

  void fit(Size s) {
    viewSize = s;
    final img = project.guide.imageSize;
    baseK = math.min(s.width / img.width, s.height / img.height) * 0.94;
    k = baseK;
    t = Offset((s.width - img.width * k) / 2, (s.height - img.height * k) / 2);
    fitted = true;
  }

  void refitView() {
    if (viewSize == Size.zero) return;
    fit(viewSize);
    notifyListeners();
  }

  void resetOverlay() {
    ovScale = 1;
    ovRot = 0;
    ovOff = Offset.zero;
    notifyListeners();
  }

  /// Zoom em torno do ponto focal (mantém o conteúdo sob os dedos).
  void zoomAbout({
    required Offset oldFocal,
    required Offset newFocal,
    required double ratio,
  }) {
    final newK = (k * ratio).clamp(baseK * 0.4, baseK * 14).toDouble();
    final r = newK / k;
    t = newFocal - (oldFocal - t) * r;
    k = newK;
    notifyListeners();
  }
}
