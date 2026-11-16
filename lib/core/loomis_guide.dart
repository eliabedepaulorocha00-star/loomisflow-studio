import 'dart:math' as math;
import 'dart:ui';

/// Nomes dos passos do Método Loomis (índice = posição da barra deslizante).
const List<String> kStepNames = [
  'Esfera craniana',
  'Corte do plano lateral',
  'Linhas central e das sobrancelhas',
  'Terços: cabelo, nariz e queixo',
  'Mandíbula, queixo e orelhas',
  'Planos do rosto (blocos)',
  'Pescoço e músculos',
  'Ombros, trapézio e clavículas',
  'Regra dos cinco olhos',
  'Olhos: pálpebras e íris',
  'Sobrancelhas',
  'Nariz: ponte, bola e narinas',
  'Boca e lábios',
  'Cabelo: massa e direção',
  'Expressão e detalhes finos',
  'Contorno final',
  'Guia de sombreamento',
];

const int kStepCount = 17;
const double kMaxStep = 16;

/// Medidas cruas do rosto (em pixels da imagem), independentes do ML Kit.
class FaceMeasurements {
  const FaceMeasurements({
    required this.eyeA,
    required this.eyeB,
    this.nose,
    this.mouthLeft,
    this.mouthRight,
    this.mouthBottom,
    this.face = const [],
    this.brows = const [],
    this.features = const [],
  });

  final Offset eyeA;
  final Offset eyeB;
  final Offset? nose;
  final Offset? mouthLeft;
  final Offset? mouthRight;
  final Offset? mouthBottom;

  /// Oval do rosto (contorno fechado).
  final List<Offset> face;

  /// Pontos da parte de baixo das sobrancelhas.
  final List<Offset> brows;

  /// Polilinhas de detalhe: sobrancelhas, olhos, nariz, lábios.
  final List<List<Offset>> features;
}

Offset _rot(Offset p, double a) {
  final c = math.cos(a), s = math.sin(a);
  return Offset(p.dx * c - p.dy * s, p.dx * s + p.dy * c);
}

double _lerp(double a, double b, double t) => a + (b - a) * t;

/// Guia de construção Loomis de UMA imagem.
///
/// Tudo é guardado num "referencial da cabeça": origem no meio dos olhos,
/// eixo X ao longo da linha dos olhos (já corrigida da inclinação [roll]),
/// eixo Y para baixo. Assim as linhas ficam sempre alinhadas à cabeça.
class LoomisGuide {
  const LoomisGuide({
    required this.imageSize,
    required this.origin,
    required this.roll,
    required this.center,
    required this.radius,
    required this.yaw,
    required this.hairY,
    required this.noseY,
    required this.chinY,
    required this.eyeL,
    required this.eyeR,
    required this.eyeHalfW,
    required this.noseTip,
    required this.noseHalfW,
    required this.mouth,
    required this.mouthHalfW,
    required this.contour,
    required this.features,
    required this.detected,
  });

  final Size imageSize;
  final Offset origin; // pixels da imagem
  final double roll; // radianos
  final Offset center; // centro da esfera (local); center.dy == linha das sobrancelhas
  final double radius;
  final double yaw; // radianos; >0 = rosto virado para a direita da imagem
  final double hairY, noseY, chinY; // local
  final Offset eyeL, eyeR; // local
  final double eyeHalfW;
  final Offset noseTip; // local
  final double noseHalfW;
  final Offset mouth; // local
  final double mouthHalfW;
  final List<Offset> contour; // local
  final List<List<Offset>> features; // local
  final bool detected;

  double get browY => center.dy;
  double get unit => (chinY - browY) / 2;

  Offset toImage(Offset local) => origin + _rot(local, roll);

  /// Extremos da linha horizontal na altura [y] (local), seguindo o contorno.
  (Offset, Offset) lineAt(double y) {
    final s = spanAt(y);
    double lo, hi;
    if (s != null) {
      lo = s.$1;
      hi = s.$2;
    } else {
      final d = (y - center.dy).abs().clamp(0.0, radius * 0.98).toDouble();
      final w = math.sqrt(radius * radius - d * d) * 0.85;
      lo = center.dx - w;
      hi = center.dx + w;
    }
    return (Offset(lo, y), Offset(hi, y));
  }

  (double, double)? spanAt(double y) {
    double? lo, hi;
    for (var i = 0; i < contour.length; i++) {
      final a = contour[i], b = contour[(i + 1) % contour.length];
      if (a.dy != b.dy && (a.dy - y) * (b.dy - y) <= 0) {
        final t = (y - a.dy) / (b.dy - a.dy);
        final x = a.dx + t * (b.dx - a.dx);
        lo = lo == null ? x : math.min(lo, x);
        hi = hi == null ? x : math.max(hi, x);
      }
    }
    if (lo == null || hi == null) return null;
    return (lo, hi);
  }

  /// Região da cabeça em coordenadas da imagem (usada para recortar o sombreamento).
  Path headPath({double grow = 1.12}) {
    final cy = (hairY + chinY) / 2;
    final path = Path();
    for (var i = 0; i < contour.length; i++) {
      final p = contour[i];
      final q = Offset(
        center.dx + (p.dx - center.dx) * grow,
        cy + (p.dy - cy) * grow,
      );
      final im = toImage(q);
      if (i == 0) {
        path.moveTo(im.dx, im.dy);
      } else {
        path.lineTo(im.dx, im.dy);
      }
    }
    return path..close();
  }

  // ------------------------------------------------------------------
  // Construção
  // ------------------------------------------------------------------

  static LoomisGuide fromMeasurements(FaceMeasurements m, Size size) {
    final left = m.eyeA.dx <= m.eyeB.dx ? m.eyeA : m.eyeB;
    final right = m.eyeA.dx <= m.eyeB.dx ? m.eyeB : m.eyeA;
    final roll = math.atan2(right.dy - left.dy, right.dx - left.dx);
    final origin = (left + right) / 2;
    Offset loc(Offset p) => _rot(p - origin, -roll);

    final eL = loc(left), eR = loc(right);
    final eyeDist = math.max((eR.dx - eL.dx).abs(), 1.0);

    final contour = m.face.map(loc).toList();
    final feats = [for (final f in m.features) f.map(loc).toList()];

    double chinY, topY, minX, maxX;
    if (contour.length >= 8) {
      chinY = contour.map((p) => p.dy).reduce(math.max);
      topY = contour.map((p) => p.dy).reduce(math.min);
      minX = contour.map((p) => p.dx).reduce(math.min);
      maxX = contour.map((p) => p.dx).reduce(math.max);
    } else {
      final r = eyeDist * 1.17;
      chinY = eL.dy + eyeDist * 1.75;
      topY = eL.dy - eyeDist * 1.2;
      minX = -r;
      maxX = r;
    }

    final browY = m.brows.isEmpty
        ? eL.dy - eyeDist * 0.28
        : m.brows.map((p) => loc(p).dy).reduce((a, b) => a + b) /
            m.brows.length;

    final unit = math.max((chinY - browY) / 2, 1.0);
    final hairY = _lerp(topY, browY - unit, 0.5);

    final noseLocal = m.nose == null ? null : loc(m.nose!);
    final noseY = _lerp(noseLocal?.dy ?? browY + unit, browY + unit, 0.5);

    final radius = (maxX - minX) / 2 * 1.05;
    final cx = (minX + maxX) / 2;

    var ratio = noseLocal == null ? 0.0 : (noseLocal.dx - 0) / eyeDist;
    if (ratio.abs() < 0.03) ratio = 0;
    final yaw = math.asin((ratio * 2.0).clamp(-0.9, 0.9).toDouble());

    Offset mouth;
    double mouthHalf;
    if (m.mouthLeft != null && m.mouthRight != null) {
      final a = loc(m.mouthLeft!), b = loc(m.mouthRight!);
      var y = (a.dy + b.dy) / 2;
      if (m.mouthBottom != null) y = _lerp(y, loc(m.mouthBottom!).dy, 0.25);
      mouth = Offset((a.dx + b.dx) / 2, y);
      mouthHalf = (b.dx - a.dx).abs() / 2;
    } else {
      mouth = Offset(0, noseY + (chinY - noseY) * 0.33);
      mouthHalf = eyeDist * 0.32;
    }

    final outContour = contour.length >= 8
        ? contour
        : _ellipse(Offset(cx, (hairY + chinY) / 2), radius * 0.95,
            (chinY - hairY) / 2 * 1.02);

    return LoomisGuide(
      imageSize: size,
      origin: origin,
      roll: roll,
      center: Offset(cx, browY),
      radius: radius,
      yaw: yaw,
      hairY: hairY,
      noseY: noseY,
      chinY: chinY,
      eyeL: eL,
      eyeR: eR,
      eyeHalfW: eyeDist * 0.2,
      noseTip: Offset(noseLocal?.dx ?? 0, noseLocal?.dy ?? noseY),
      noseHalfW: eyeDist * 0.3,
      mouth: mouth,
      mouthHalfW: mouthHalf,
      contour: outContour,
      features: feats,
      detected: true,
    );
  }

  /// Guia padrão (sem rosto detectado): proporções clássicas centradas na imagem.
  /// O usuário ainda pode usar todo o estúdio; só não "gruda" no rosto da foto.
  static LoomisGuide fallback(Size size) {
    final r = math.min(size.width, size.height) * 0.28;
    final u = r * 0.855;
    final browY = 0.0;
    final hairY = -u, noseY = u, chinY = 2 * u;
    return LoomisGuide(
      imageSize: size,
      origin: Offset(size.width / 2, size.height * 0.42),
      roll: 0,
      center: Offset(0, browY),
      radius: r,
      yaw: 0,
      hairY: hairY,
      noseY: noseY,
      chinY: chinY,
      eyeL: Offset(-r * 0.43, r * 0.3),
      eyeR: Offset(r * 0.43, r * 0.3),
      eyeHalfW: r * 0.17,
      noseTip: Offset(0, noseY),
      noseHalfW: r * 0.26,
      mouth: Offset(0, noseY + (chinY - noseY) * 0.33),
      mouthHalfW: r * 0.28,
      contour: _ellipse(Offset(0, (hairY + chinY) / 2), r * 0.95,
          (chinY - hairY) / 2 * 1.02),
      features: const [],
      detected: false,
    );
  }

  static List<Offset> _ellipse(Offset c, double rx, double ry, [int n = 36]) {
    return [
      for (var i = 0; i < n; i++)
        Offset(c.dx + rx * math.cos(2 * math.pi * i / n),
            c.dy + ry * math.sin(2 * math.pi * i / n)),
    ];
  }

  // ------------------------------------------------------------------
  // JSON
  // ------------------------------------------------------------------

  static List<double> _flat(List<Offset> l) =>
      [for (final o in l) ...[o.dx, o.dy]];
  static List<Offset> _unflat(List<dynamic> l) {
    final n = l.cast<num>();
    return [
      for (var i = 0; i + 1 < n.length; i += 2)
        Offset(n[i].toDouble(), n[i + 1].toDouble()),
    ];
  }

  Map<String, dynamic> toJson() => {
        'w': imageSize.width,
        'h': imageSize.height,
        'origin': [origin.dx, origin.dy],
        'roll': roll,
        'center': [center.dx, center.dy],
        'radius': radius,
        'yaw': yaw,
        'hairY': hairY,
        'noseY': noseY,
        'chinY': chinY,
        'eyeL': [eyeL.dx, eyeL.dy],
        'eyeR': [eyeR.dx, eyeR.dy],
        'eyeHalfW': eyeHalfW,
        'noseTip': [noseTip.dx, noseTip.dy],
        'noseHalfW': noseHalfW,
        'mouth': [mouth.dx, mouth.dy],
        'mouthHalfW': mouthHalfW,
        'contour': _flat(contour),
        'features': [for (final f in features) _flat(f)],
        'detected': detected,
      };

  factory LoomisGuide.fromJson(Map<String, dynamic> j) {
    Offset o(String k) {
      final l = (j[k] as List).cast<num>();
      return Offset(l[0].toDouble(), l[1].toDouble());
    }

    double d(String k) => (j[k] as num).toDouble();
    return LoomisGuide(
      imageSize: Size(d('w'), d('h')),
      origin: o('origin'),
      roll: d('roll'),
      center: o('center'),
      radius: d('radius'),
      yaw: d('yaw'),
      hairY: d('hairY'),
      noseY: d('noseY'),
      chinY: d('chinY'),
      eyeL: o('eyeL'),
      eyeR: o('eyeR'),
      eyeHalfW: d('eyeHalfW'),
      noseTip: o('noseTip'),
      noseHalfW: d('noseHalfW'),
      mouth: o('mouth'),
      mouthHalfW: d('mouthHalfW'),
      contour: _unflat(j['contour'] as List),
      features: [for (final f in (j['features'] as List)) _unflat(f as List)],
      detected: j['detected'] as bool,
    );
  }
}
