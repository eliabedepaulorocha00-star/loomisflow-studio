import 'dart:math' as math;
import 'dart:ui';

/// Passos da construção de figura (corpo), no espírito do Loomis para figura humana.
const List<String> kBodyStepNames = [
  'Linha de ação e proporções',
  'Eixos de equilíbrio e gravidade',
  'Cabeça e proporções do rosto',
  'Pescoço, ombros e clavículas',
  'Caixa torácica e coluna',
  'Pelve, cintura e abdômen',
  'Articulações e eixos dos membros',
  'Volumes dos membros',
  'Músculos principais',
  'Mãos',
  'Pés',
  'Marcos anatômicos',
  'Guia de sombreamento',
];

/// Pontos do corpo (pixels da imagem) vindos do detector de pose do ML Kit.
/// Chaves: nose, lEar, rEar, lSh, rSh, lEl, rEl, lWr, rWr, lHand, rHand,
/// lHip, rHip, lKn, rKn, lAn, rAn, lFoot, rFoot. Só entram os pontos visíveis.
class FigureGuide {
  FigureGuide(this.imageSize, Map<String, Offset> points)
      : pts = Map<String, Offset>.unmodifiable(points);

  final Size imageSize;
  final Map<String, Offset> pts;

  static bool canBuild(Map<String, Offset> p) =>
      p.containsKey('lSh') &&
      p.containsKey('rSh') &&
      p.containsKey('lHip') &&
      p.containsKey('rHip');

  /// Parece uma foto de corpo (não só busto): quadris e ao menos um joelho visíveis.
  bool get looksLikeBody => pts.containsKey('lKn') || pts.containsKey('rKn');

  Offset get shoulderMid => (pts['lSh']! + pts['rSh']!) / 2;
  Offset get hipMid => (pts['lHip']! + pts['rHip']!) / 2;
  double get shoulderWidth => math.max((pts['lSh']! - pts['rSh']!).distance, 1.0);
  double get hipWidth => math.max((pts['lHip']! - pts['rHip']!).distance, 1.0);
  double get torsoLen => math.max((hipMid - shoulderMid).distance, 1.0);

  /// Direção do tronco, dos quadris para os ombros (unitária).
  Offset get up => (shoulderMid - hipMid) / torsoLen;

  double get headW {
    final l = pts['lEar'], r = pts['rEar'];
    if (l != null && r != null) {
      final d = (l - r).distance;
      if (d > shoulderWidth * 0.18) return d * 1.15;
    }
    return shoulderWidth * 0.46;
  }

  double get headH => headW * 1.3;

  Offset get headCenter {
    final l = pts['lEar'], r = pts['rEar'], n = pts['nose'];
    if (l != null && r != null) return (l + r) / 2;
    if (n != null) return n - Offset(0, headH * 0.12);
    return shoulderMid + up * (headH * 0.95);
  }

  /// Inclinação da cabeça (radianos), pela linha das orelhas; senão, dos ombros.
  double get headTilt {
    final l = pts['lEar'], r = pts['rEar'];
    final a = (l != null && r != null)
        ? math.atan2(l.dy - r.dy, l.dx - r.dx)
        : math.atan2(pts['lSh']!.dy - pts['rSh']!.dy, pts['lSh']!.dx - pts['rSh']!.dx) * 0.5;
    return _norm(a);
  }

  double get shoulderTilt => _norm(
      math.atan2(pts['lSh']!.dy - pts['rSh']!.dy, pts['lSh']!.dx - pts['rSh']!.dx));
  double get hipTilt => _norm(
      math.atan2(pts['lHip']!.dy - pts['rHip']!.dy, pts['lHip']!.dx - pts['rHip']!.dx));

  static double _norm(double a) {
    while (a > math.pi / 2) {
      a -= math.pi;
    }
    while (a < -math.pi / 2) {
      a += math.pi;
    }
    return a;
  }

  Rect get bounds {
    var r = Rect.fromCircle(center: headCenter, radius: headH * 0.6);
    for (final p in pts.values) {
      r = r.expandToInclude(Rect.fromCircle(center: p, radius: headH * 0.25));
    }
    return r;
  }

  Offset get center => bounds.center;

  /// Modelo padrão de corpo inteiro (8 cabeças), centralizado na imagem.
  /// Serve quando a pose não é detectada: o usuário ajusta com os gestos.
  factory FigureGuide.template(Size size) {
    final hh = size.height * 0.88 / 7.75;
    final top = size.height * 0.06;
    final cx = size.width / 2;
    Offset o(double dx, double y) => Offset(cx + dx * hh, top + y * hh);
    return FigureGuide(size, {
      'nose': o(0, 0.58),
      'lEar': o(0.334, 0.5),
      'rEar': o(-0.334, 0.5),
      'lSh': o(0.95, 1.55), 'rSh': o(-0.95, 1.55),
      'lEl': o(1.15, 3.0), 'rEl': o(-1.15, 3.0),
      'lWr': o(1.3, 4.1), 'rWr': o(-1.3, 4.1),
      'lHand': o(1.38, 4.8), 'rHand': o(-1.38, 4.8),
      'lHip': o(0.55, 4.0), 'rHip': o(-0.55, 4.0),
      'lKn': o(0.6, 5.75), 'rKn': o(-0.6, 5.75),
      'lAn': o(0.58, 7.3), 'rAn': o(-0.58, 7.3),
      'lFoot': o(0.75, 7.65), 'rFoot': o(-0.75, 7.65),
    });
  }

  /// Completa pontos que o detector não viu (braços, pernas, mãos) usando
  /// proporções médias a partir de ombros e quadris.
  FigureGuide completed() {
    final p = Map<String, Offset>.from(pts);
    final down = -up;
    final t = torsoLen;
    for (final s in ['l', 'r']) {
      final sh = p['${s}Sh']!, hip = p['${s}Hip']!;
      p['${s}El'] ??= sh + down * (t * 0.6);
      p['${s}Wr'] ??= p['${s}El']! + down * (t * 0.46);
      p['${s}Hand'] ??= p['${s}Wr']! + down * (t * 0.28);
      p['${s}Kn'] ??= hip + down * (t * 0.7);
      p['${s}An'] ??= p['${s}Kn']! + down * (t * 0.62);
    }
    return FigureGuide(imageSize, p);
  }

  Map<String, dynamic> toJson() => {
        'w': imageSize.width,
        'h': imageSize.height,
        'pts': {
          for (final e in pts.entries) e.key: [e.value.dx, e.value.dy],
        },
      };

  factory FigureGuide.fromJson(Map<String, dynamic> j) {
    final raw = (j['pts'] as Map).cast<String, dynamic>();
    return FigureGuide(
      Size((j['w'] as num).toDouble(), (j['h'] as num).toDouble()),
      {
        for (final e in raw.entries)
          e.key: Offset(
            ((e.value as List)[0] as num).toDouble(),
            ((e.value as List)[1] as num).toDouble(),
          ),
      },
    );
  }
}
