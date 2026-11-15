import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../core/spring.dart';
import '../core/theme.dart';

class RadialItem {
  const RadialItem(this.icon, this.label, this.onTap, {this.active = false});
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool active;
}

/// Barra de ferramentas radial flutuante.
/// - O botão central pode ser ARRASTADO para qualquer canto (longe da mão que desenha).
/// - Toque abre/fecha o leque com física de mola; o leque abre em direção ao centro da tela.
class RadialMenu extends StatefulWidget {
  const RadialMenu({
    super.key,
    required this.items,
    this.initialAlignment = const Alignment(0.82, 0.55),
  });

  final List<RadialItem> items;
  final Alignment initialAlignment;

  @override
  State<RadialMenu> createState() => _RadialMenuState();
}

class _RadialMenuState extends State<RadialMenu>
    with SingleTickerProviderStateMixin {
  late final AnimationController _open =
      AnimationController.unbounded(vsync: this, value: 0);
  Offset? _pos; // centro do botão, em px
  bool _expanded = false;

  static const double _btn = 56;
  static const double _radius = 116;

  @override
  void dispose() {
    _open.dispose();
    super.dispose();
  }

  void _toggle() {
    _expanded = !_expanded;
    springTo(_open, _expanded ? 1 : 0, spring: kSnappy);
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, box) {
      final size = Size(box.maxWidth, box.maxHeight);
      _pos ??= Offset(
        size.width / 2 + widget.initialAlignment.x * (size.width / 2 - _btn),
        size.height / 2 + widget.initialAlignment.y * (size.height / 2 - _btn),
      );
      final pos = _pos!;
      final toCenter = math.atan2(size.height / 2 - pos.dy, size.width / 2 - pos.dx);
      const sweep = math.pi * 0.95;
      final n = widget.items.length;

      return AnimatedBuilder(
        animation: _open,
        builder: (context, _) {
          final t = _open.value;
          final children = <Widget>[];
          for (var i = 0; i < n; i++) {
            final f = n == 1 ? 0.5 : i / (n - 1);
            final ang = toCenter - sweep / 2 + sweep * f;
            final d = _radius * t;
            final c = pos + Offset(math.cos(ang), math.sin(ang)) * d;
            final item = widget.items[i];
            children.add(Positioned(
              left: c.dx - 24,
              top: c.dy - 24,
              child: Opacity(
                opacity: t.clamp(0.0, 1.0),
                child: Transform.scale(
                  scale: (0.4 + 0.6 * t).clamp(0.0, 1.3),
                  child: IgnorePointer(
                    ignoring: t < 0.6,
                    child: Tooltip(
                      message: item.label,
                      child: PressableScale(
                        onTap: () {
                          item.onTap();
                          if (_expanded) _toggle();
                        },
                        child: Container(
                          width: 48,
                          height: 48,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: item.active ? Palette.accent : Palette.surfaceHi,
                            border: Border.all(color: Palette.line),
                            boxShadow: const [
                              BoxShadow(color: Color(0x66000000), blurRadius: 12),
                            ],
                          ),
                          child: Icon(
                            item.icon,
                            size: 22,
                            color: item.active ? Palette.bg : Palette.text,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ));
          }

          children.add(Positioned(
            left: pos.dx - _btn / 2,
            top: pos.dy - _btn / 2,
            child: GestureDetector(
              onPanUpdate: (d) {
                final np = pos + d.delta;
                setState(() {
                  _pos = Offset(
                    np.dx.clamp(_btn / 2, size.width - _btn / 2),
                    np.dy.clamp(_btn / 2, size.height - _btn / 2),
                  );
                });
              },
              child: PressableScale(
                onTap: _toggle,
                child: Transform.rotate(
                  angle: t * math.pi / 4,
                  child: Container(
                    width: _btn,
                    height: _btn,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: Palette.accent,
                      boxShadow: [
                        BoxShadow(
                          color: Palette.accent.withValues(alpha: 0.35),
                          blurRadius: 18,
                        ),
                      ],
                    ),
                    child: const Icon(Icons.add_rounded, color: Palette.bg, size: 30),
                  ),
                ),
              ),
            ),
          ));

          return Stack(children: children);
        },
      );
    });
  }
}
