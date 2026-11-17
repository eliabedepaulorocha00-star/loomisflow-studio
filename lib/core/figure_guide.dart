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

/// Estilo do corpo: muda proporções, volumes e detalhes da guia.
enum BodyStyle { male, female, animeMale, animeFemale }

extension BodyStyleInfo on BodyStyle {
  String get label => switch (this) {
        BodyStyle.male => 'Masculino',
        BodyStyle.female => 'Feminino',
        BodyStyle.animeMale => 'Anime masculino',
        BodyStyle.animeFemale => 'Anime feminino',
      };

  bool get isAnime => this == BodyStyle.animeMale || this == BodyStyle.animeFemale;

  StyleSpec get spec => switch (this) {
        BodyStyle.male => const StyleSpec(),
        BodyStyle.female => const StyleSpec(
            ribW: 0.68, ribH: 0.6, pelW: 1.55, waist: 0.24, arm: 0.33, fore: 0.26,
            thigh: 0.64, calf: 0.4, hand: 0.9, foot: 0.9, muscle: 0.55, bust: true,
            eyeY: 0.02, eyeW: 0.22, eyeH: 0.08, jaw: 0.3, total: 7.6),
        BodyStyle.animeMale => const StyleSpec(
            ribW: 0.66, ribH: 0.58, pelW: 1.25, waist: 0.26, arm: 0.27, fore: 0.22,
            thigh: 0.5, calf: 0.34, hand: 0.8, foot: 0.8, muscle: 0.3,
            eyeY: 0.1, eyeW: 0.26, eyeH: 0.12, jaw: 0.85, total: 8.0),
        BodyStyle.animeFemale => const StyleSpec(
            ribW: 0.6, ribH: 0.56, pelW: 1.4, waist: 0.2, arm: 0.24, fore: 0.2,
            thigh: 0.5, calf: 0.32, hand: 0.75, foot: 0.75, muscle: 0.15, bust: true,
            eyeY: 0.12, eyeW: 0.28, eyeH: 0.13, jaw: 0.9, total: 8.0),
      };
}

/// Proporções de cada estilo (tudo relativo ao tamanho da cabeça ou do tronco).
class StyleSpec {
  const StyleSpec({
    this.ribW = 0.78,
    this.ribH = 0.62,
    this.pelW = 1.35,
    this.waist = 0.3,
    this.arm = 0.40,
    this.fore = 0.32,
    this.thigh = 0.62,
    this.calf = 0.46,
    this.hand = 1.0,
    this.foot = 1.0,
    this.muscle = 1.0,
    this.bust = false,
    this.eyeY = 0.0,
    this.eyeW = 0.2,
    this.eyeH = 0.07,
    this.jaw = 0.0,
    this.total = 7.75,
  });

  final double ribW, ribH, pelW, waist, arm, fore, thigh, calf, hand, foot, muscle;
  final bool bust;
  final double eyeY, eyeW, eyeH, jaw;

  /// Altura total do modelo em "cabeças".
  final double total;
}

/// Pontos do corpo (pixels da imagem) vindos do detector de pose do ML Kit.
/// Chaves: nose, lEar, rEar, lSh, rSh, lEl, rEl, lWr, rWr, lHand, rHand,
/// lHip, rHip, lKn, rKn, lAn, rAn, lFoot, rFoot. Só entram os pontos visíveis.
class FigureGuide {
  FigureGuide(
    this.imageSize,
    Map<String, Offset> points, {
    this.style = BodyStyle.male,
    this.isTemplate = false,
  }) : pts = Map<String, Offset>.unmodifiable(points);

  final Size imageSize;
  final Map<String, Offset> pts;
  final BodyStyle style;

  /// Verdadeiro quando os pontos vêm de um modelo (não de uma pose detectada).
  final bool isTemplate;

  static bool canBuild(Map<String, Offset> p) =>
      p.containsKey('lSh') &&
      p.containsKey('rSh') &&
      p.containsKey('lHip') &&
      p.containsKey('rHip');

  /// Parece uma foto de corpo (não só busto): quadris e joelho ou tornozelo visíveis.
  bool get looksLikeBody =>
      pts.containsKey('lKn') ||
      pts.containsKey('rKn') ||
      pts.containsKey('lAn') ||
      pts.containsKey('rAn');

  FigureGuide withStyle(BodyStyle s) =>
      FigureGuide(imageSize, pts, style: s, isTemplate: isTemplate);

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

  /// Modelo de corpo inteiro. Sem [headCenter]/[headH], ocupa a imagem toda
  /// (88% da altura); com eles, nasce da cabeça (útil quando só o rosto foi achado).
  factory FigureGuide.template(
    Size size, {
    BodyStyle style = BodyStyle.male,
    Offset? headCenter,
    double? headH,
    Rect? fit,
  }) {
    final sp = style.spec;
    final hh = headH ?? (fit != null ? fit.height / sp.total : size.height * 0.88 / sp.total);
    final top = headCenter != null
        ? headCenter.dy - hh * 0.5
        : (fit != null ? fit.top : size.height * 0.06);
    final cx = headCenter?.dx ?? (fit != null ? fit.center.dx : size.width / 2);
    Offset o(double dx, double y) => Offset(cx + dx * hh, top + y * hh);

    // [ombro x, ombro y, quadril x, quadril y, cotovelo x/y, punho x/y, mão y,
    //  joelho x/y, tornozelo x/y, pé x/y]
    final v = switch (style) {
      BodyStyle.male => const [0.95, 1.55, 0.55, 4.0, 1.15, 3.0, 1.3, 4.1, 4.8, 0.6, 5.75, 0.58, 7.3, 0.75, 7.65],
      BodyStyle.female => const [0.78, 1.5, 0.62, 3.95, 0.98, 2.95, 1.12, 4.0, 4.65, 0.52, 5.7, 0.45, 7.25, 0.62, 7.6],
      BodyStyle.animeMale => const [0.8, 1.45, 0.48, 3.85, 0.95, 2.85, 1.05, 3.9, 4.5, 0.5, 5.9, 0.42, 7.6, 0.6, 7.95],
      BodyStyle.animeFemale => const [0.68, 1.4, 0.5, 3.75, 0.82, 2.75, 0.92, 3.75, 4.35, 0.46, 5.8, 0.38, 7.55, 0.52, 7.9],
    };
    return FigureGuide(
      size,
      {
        'nose': o(0, 0.58),
        'lEar': o(0.334, 0.5),
        'rEar': o(-0.334, 0.5),
        'lSh': o(v[0], v[1]), 'rSh': o(-v[0], v[1]),
        'lEl': o(v[4], v[5]), 'rEl': o(-v[4], v[5]),
        'lWr': o(v[6], v[7]), 'rWr': o(-v[6], v[7]),
        'lHand': o(v[6] + 0.08, v[8]), 'rHand': o(-v[6] - 0.08, v[8]),
        'lHip': o(v[2], v[3]), 'rHip': o(-v[2], v[3]),
        'lKn': o(v[9], v[10]), 'rKn': o(-v[9], v[10]),
        'lAn': o(v[11], v[12]), 'rAn': o(-v[11], v[12]),
        'lFoot': o(v[13], v[14]), 'rFoot': o(-v[13], v[14]),
      },
      style: style,
      isTemplate: true,
    );
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
    return FigureGuide(imageSize, p, style: style, isTemplate: isTemplate);
  }

  Map<String, dynamic> toJson() => {
        'w': imageSize.width,
        'h': imageSize.height,
        'style': style.index,
        'tpl': isTemplate,
        'pts': {
          for (final e in pts.entries) e.key: [e.value.dx, e.value.dy],
        },
      };

  factory FigureGuide.fromJson(Map<String, dynamic> j) {
    final raw = (j['pts'] as Map).cast<String, dynamic>();
    final si = (j['style'] as num?)?.toInt() ?? 0;
    return FigureGuide(
      Size((j['w'] as num).toDouble(), (j['h'] as num).toDouble()),
      {
        for (final e in raw.entries)
          e.key: Offset(
            ((e.value as List)[0] as num).toDouble(),
            ((e.value as List)[1] as num).toDouble(),
          ),
      },
      style: BodyStyle.values[si.clamp(0, BodyStyle.values.length - 1)],
      isTemplate: (j['tpl'] as bool?) ?? false,
    );
  }
}
