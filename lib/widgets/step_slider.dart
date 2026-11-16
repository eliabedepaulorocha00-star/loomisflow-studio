import 'package:flutter/material.dart';

import '../core/spring.dart';
import '../core/theme.dart';

/// Barra interativa dos passos: arraste livremente (as camadas aparecem com fade)
/// e, ao soltar, a barra "encaixa" no passo mais próximo com física de mola.
/// [names] define quantos passos existem (rosto: 11, corpo: 7).
class StepSlider extends StatefulWidget {
  const StepSlider({
    super.key,
    required this.value,
    required this.names,
    required this.onChanged,
    this.onEnd,
  });

  final double value;
  final List<String> names;
  final ValueChanged<double> onChanged;
  final ValueChanged<double>? onEnd;

  @override
  State<StepSlider> createState() => _StepSliderState();
}

class _StepSliderState extends State<StepSlider>
    with SingleTickerProviderStateMixin {
  late final AnimationController _snap =
      AnimationController.unbounded(vsync: this);
  bool _dragging = false;

  double get _max => (widget.names.length - 1).toDouble();

  @override
  void initState() {
    super.initState();
    _snap.addListener(() {
      if (!_dragging) widget.onChanged(_snap.value.clamp(0.0, _max).toDouble());
    });
  }

  @override
  void dispose() {
    _snap.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final n = widget.names.length;
    final idx = widget.value.round().clamp(0, n - 1);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: Palette.surfaceHi,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text('${idx + 1}/$n',
                  style: const TextStyle(
                      fontSize: 12, color: Palette.accent, fontWeight: FontWeight.w600)),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 220),
                child: Text(
                  widget.names[idx],
                  key: ValueKey('$n-$idx'),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                ),
              ),
            ),
          ],
        ),
        SliderTheme(
          data: SliderTheme.of(context).copyWith(
            tickMarkShape: SliderTickMarkShape.noTickMark,
          ),
          child: Slider(
            value: widget.value.clamp(0.0, _max).toDouble(),
            min: 0,
            max: _max,
            divisions: (n - 1) * 8,
            onChangeStart: (_) {
              _dragging = true;
              _snap.stop();
            },
            onChanged: widget.onChanged,
            onChangeEnd: (v) {
              _dragging = false;
              final target = v.roundToDouble();
              _snap.value = v;
              springTo(_snap, target, spring: kSnappy);
              widget.onEnd?.call(target);
            },
          ),
        ),
      ],
    );
  }
}
