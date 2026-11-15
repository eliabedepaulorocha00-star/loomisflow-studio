import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';

/// Mola padrão do app: levemente subamortecida (um "respiro" no final).
const SpringDescription kSpring =
    SpringDescription(mass: 1, stiffness: 220, damping: 22);

/// Mola mais firme, para toques e menus.
const SpringDescription kSnappy =
    SpringDescription(mass: 1, stiffness: 420, damping: 30);

/// Anima um [AnimationController] (preferencialmente `.unbounded`) até [target]
/// usando física de mola, preservando a velocidade atual.
void springTo(
  AnimationController c,
  double target, {
  double velocity = 0,
  SpringDescription spring = kSpring,
}) {
  c.animateWith(SpringSimulation(spring, c.value, target, velocity));
}

/// Curva baseada em mola, para usar em transições/rotas e animações implícitas.
class SpringCurve extends Curve {
  SpringCurve({SpringDescription spring = kSpring, this.seconds = 0.8})
      : _sim = SpringSimulation(spring, 0, 1, 0);

  final SpringSimulation _sim;
  final double seconds;

  @override
  double transformInternal(double t) => _sim.x(t * seconds);
}

final SpringCurve kSpringCurve = SpringCurve();
const Duration kSpringDuration = Duration(milliseconds: 650);

/// Rota com entrada por mola (deslize + fade).
Route<T> springRoute<T>(Widget page) {
  return PageRouteBuilder<T>(
    transitionDuration: kSpringDuration,
    reverseTransitionDuration: const Duration(milliseconds: 380),
    pageBuilder: (_, __, ___) => page,
    transitionsBuilder: (context, anim, sec, child) {
      final curved = CurvedAnimation(
        parent: anim,
        curve: kSpringCurve,
        reverseCurve: Curves.easeInCubic,
      );
      return FadeTransition(
        opacity: CurvedAnimation(parent: anim, curve: Curves.easeOut),
        child: SlideTransition(
          position: Tween(begin: const Offset(0, 0.08), end: Offset.zero)
              .animate(curved),
          child: ScaleTransition(
            scale: Tween(begin: 0.96, end: 1.0).animate(curved),
            child: child,
          ),
        ),
      );
    },
  );
}

/// Widget que "afunda" com mola ao ser pressionado.
class PressableScale extends StatefulWidget {
  const PressableScale({
    super.key,
    required this.child,
    this.onTap,
    this.onLongPress,
    this.pressedScale = 0.92,
  });

  final Widget child;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final double pressedScale;

  @override
  State<PressableScale> createState() => _PressableScaleState();
}

class _PressableScaleState extends State<PressableScale>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c =
      AnimationController.unbounded(vsync: this, value: 1);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: (_) => springTo(_c, widget.pressedScale, spring: kSnappy),
      onTapUp: (_) => springTo(_c, 1, spring: kSnappy),
      onTapCancel: () => springTo(_c, 1, spring: kSnappy),
      onTap: widget.onTap,
      onLongPress: widget.onLongPress,
      child: AnimatedBuilder(
        animation: _c,
        builder: (_, child) => Transform.scale(scale: _c.value, child: child),
        child: widget.child,
      ),
    );
  }
}
