import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../../core/app_state.dart';
import '../../core/models.dart';
import '../../core/spring.dart';
import '../../core/storage.dart';
import '../../core/theme.dart';
import '../../widgets/radial_menu.dart';
import '../../widgets/step_slider.dart';
import 'trace_model.dart';
import 'trace_painter.dart';

/// Estúdio de decalque na tela.
///
/// Gestos (modo "Desenhar"):
///   1 dedo ........ desenha
///   2 dedos ....... pinça = zoom, arrastar = mover a vista
///   toque com 2 dedos = desfazer · toque com 3 dedos = refazer
/// Modo "Mover decalque": 1 dedo move a foto/guia; 2 dedos escalam e giram.
class TraceScreen extends StatefulWidget {
  const TraceScreen({super.key});

  @override
  State<TraceScreen> createState() => _TraceScreenState();
}

class _TraceScreenState extends State<TraceScreen> {
  TraceModel? _m;
  AppState? _app;
  TraceModel get m => _m!;

  final Map<int, Offset> _p = {};
  int _max = 0;
  DateTime _t0 = DateTime.now();
  double _moved = 0;
  Offset _prevC = Offset.zero;
  double _prevD = 1, _prevA = 0;

  bool _moveOverlay = false;
  bool _focus = false;
  bool _panel = false;

  Timer? _saveT;
  Timer? _toastT;
  String? _toast;

  static const _inks = [0xFF1B1C22, 0xFF8E2F2F, 0xFF23408E, 0xFF2F6B3A, 0xFFFFFFFF];

  @override
  void initState() {
    super.initState();
    WakelockPlus.enable();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _app = AppScope.of(context);
    _m ??= TraceModel(_app!.current!);
  }

  @override
  void dispose() {
    _saveT?.cancel();
    _toastT?.cancel();
    if (_m != null) {
      m.project.step = m.step;
      ProjectStore.instance.saveStrokes(m.project);
      m.dispose();
    }
    WakelockPlus.disable();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    super.dispose();
  }

  // ---------------------------------------------------------------- gestos

  void _down(PointerDownEvent e) {
    _p[e.pointer] = e.localPosition;
    if (_p.length == 1) {
      _t0 = DateTime.now();
      _moved = 0;
      _max = 1;
      if (!_moveOverlay) {
        m.live = StrokeData(
          points: [m.toImage(e.localPosition)],
          color: m.color,
          width: m.brushPx / m.k,
        );
        m.changed();
      }
    } else {
      _max = math.max(_max, _p.length);
      // segundo dedo: se já havia um traço de verdade, preserva; senão descarta
      final live = m.live;
      if (live != null && live.points.length > 8) {
        _commitLive();
      } else {
        m.live = null;
      }
      _baseline();
      m.changed();
    }
  }

  void _baseline() {
    final pts = _p.values.toList();
    if (pts.isEmpty) return;
    _prevC = pts.reduce((a, b) => a + b) / pts.length.toDouble();
    if (pts.length >= 2) {
      _prevD = math.max((pts[0] - pts[1]).distance, 1);
      _prevA = math.atan2(pts[1].dy - pts[0].dy, pts[1].dx - pts[0].dx);
    }
  }

  void _move(PointerMoveEvent e) {
    if (!_p.containsKey(e.pointer)) return;
    _p[e.pointer] = e.localPosition;

    if (_p.length == 1) {
      if (_moveOverlay) {
        m.ovOff += e.delta / m.k;
        m.changed();
      } else if (m.live != null) {
        final pt = m.toImage(e.localPosition);
        final last = m.live!.points.last;
        if ((pt - last).distance * m.k >= 1.2) {
          m.live!.points.add(pt);
          m.changed();
        }
      }
      return;
    }

    _moved += e.delta.distance;
    final pts = _p.values.toList();
    final c = pts.reduce((a, b) => a + b) / pts.length.toDouble();
    if (pts.length == 2) {
      final d = math.max((pts[0] - pts[1]).distance, 1.0);
      final a = math.atan2(pts[1].dy - pts[0].dy, pts[1].dx - pts[0].dx);
      final ratio = d / _prevD;
      if (_moveOverlay) {
        var da = a - _prevA;
        while (da > math.pi) {
          da -= 2 * math.pi;
        }
        while (da < -math.pi) {
          da += 2 * math.pi;
        }
        m.ovScale = (m.ovScale * ratio).clamp(0.2, 5.0).toDouble();
        m.ovRot += da;
        m.ovOff += (c - _prevC) / m.k;
        m.changed();
      } else {
        m.zoomAbout(oldFocal: _prevC, newFocal: c, ratio: ratio);
      }
      _prevD = d;
      _prevA = a;
    }
    _prevC = c;
  }

  void _up(PointerEvent e) {
    _p.remove(e.pointer);
    if (_p.isEmpty) {
      if (m.live != null) _commitLive();
      final quick = DateTime.now().difference(_t0).inMilliseconds < 320 &&
          _moved < 24;
      if (quick && _max == 2) {
        _undo();
      } else if (quick && _max >= 3) {
        _redo();
      }
      _max = 0;
    } else {
      _baseline();
    }
  }

  void _commitLive() {
    final s = m.live;
    m.live = null;
    if (s == null || s.points.isEmpty) return;
    m.project.strokes.add(s);
    m.redo.clear();
    _scheduleSave();
    m.changed();
  }

  void _undo() {
    final s = m.project.strokes;
    if (s.isEmpty) return _flash('Nada para desfazer');
    m.redo.add(s.removeLast());
    HapticFeedback.selectionClick();
    _scheduleSave();
    m.changed();
    _flash('Desfeito');
  }

  void _redo() {
    if (m.redo.isEmpty) return _flash('Nada para refazer');
    m.project.strokes.add(m.redo.removeLast());
    HapticFeedback.selectionClick();
    _scheduleSave();
    m.changed();
    _flash('Refeito');
  }

  void _scheduleSave() {
    _saveT?.cancel();
    _saveT = Timer(const Duration(milliseconds: 600), () {
      m.project.step = m.step;
      ProjectStore.instance.saveStrokes(m.project);
    });
  }

  void _flash(String text) {
    _toastT?.cancel();
    setState(() => _toast = text);
    _toastT = Timer(const Duration(milliseconds: 900), () {
      if (mounted) setState(() => _toast = null);
    });
  }

  void _setFocus(bool v) {
    setState(() {
      _focus = v;
      if (v) _panel = false;
    });
    SystemChrome.setEnabledSystemUIMode(
        v ? SystemUiMode.immersiveSticky : SystemUiMode.edgeToEdge);
  }

  // ------------------------------------------------------------------ UI

  @override
  Widget build(BuildContext context) {
    final app = _app!;
    return Scaffold(
      backgroundColor: Palette.bg,
      body: Stack(
        children: [
          Positioned.fill(
            child: LayoutBuilder(builder: (context, box) {
              final size = Size(box.maxWidth, box.maxHeight);
              if (!m.fitted) m.fit(size);
              return Listener(
                behavior: HitTestBehavior.opaque,
                onPointerDown: _down,
                onPointerMove: _move,
                onPointerUp: _up,
                onPointerCancel: _up,
                child: RepaintBoundary(
                  child: CustomPaint(
                    size: size,
                    painter: TracePainter(m, app.currentReference, app.currentShading),
                  ),
                ),
              );
            }),
          ),

          // barra superior
          Positioned(
            left: 0,
            right: 0,
            top: 0,
            child: _fade(
              visible: !_focus,
              child: SafeArea(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(8, 4, 16, 0),
                  child: Row(
                    children: [
                      IconButton(
                        icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20),
                        onPressed: () => Navigator.of(context).pop(),
                      ),
                      Expanded(
                        child: Text(
                          _moveOverlay ? 'Mover decalque' : 'Desenhar',
                          style: const TextStyle(
                              fontWeight: FontWeight.w700, fontSize: 16),
                        ),
                      ),
                      Text(
                        '${m.project.strokes.length} traços',
                        style: const TextStyle(color: Palette.textDim, fontSize: 12),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),

          // menu radial flutuante (arrastável)
          Positioned.fill(
            child: _fade(
              visible: !_focus,
              child: RadialMenu(items: [
                RadialItem(Icons.undo_rounded, 'Desfazer', _undo),
                RadialItem(Icons.redo_rounded, 'Refazer', _redo),
                RadialItem(Icons.center_focus_strong_outlined, 'Modo Foco',
                    () => _setFocus(true)),
                RadialItem(Icons.grid_4x4_rounded, 'Grade', () {
                  m.grid = !m.grid;
                  m.changed();
                  setState(() {});
                }, active: m.grid),
                RadialItem(Icons.open_with_rounded, 'Mover decalque', () {
                  setState(() => _moveOverlay = !_moveOverlay);
                }, active: _moveOverlay),
                RadialItem(Icons.tune_rounded, 'Ajustes', () {
                  setState(() => _panel = !_panel);
                }, active: _panel),
              ]),
            ),
          ),

          // painel de ajustes
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: IgnorePointer(
              ignoring: !_panel || _focus,
              child: AnimatedSlide(
                duration: kSpringDuration,
                curve: kSpringCurve,
                offset: _panel && !_focus ? Offset.zero : const Offset(0, 1.05),
                child: _buildPanel(),
              ),
            ),
          ),

          // saída do Modo Foco: alça discreta no canto
          if (_focus)
            Positioned(
              top: 0,
              right: 0,
              child: SafeArea(
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => _setFocus(false),
                  child: const Padding(
                    padding: EdgeInsets.all(14),
                    child: Opacity(
                      opacity: 0.22,
                      child: Icon(Icons.fullscreen_exit_rounded, size: 26),
                    ),
                  ),
                ),
              ),
            ),

          // aviso rápido (Desfeito/Refeito)
          Positioned(
            left: 0,
            right: 0,
            top: 96,
            child: IgnorePointer(
              child: AnimatedOpacity(
                duration: const Duration(milliseconds: 180),
                opacity: _toast == null ? 0 : 1,
                child: Center(
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                    decoration: BoxDecoration(
                      color: Palette.surfaceHi.withValues(alpha: 0.92),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(_toast ?? '',
                        style: const TextStyle(fontWeight: FontWeight.w600)),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _fade({required bool visible, required Widget child}) {
    return IgnorePointer(
      ignoring: !visible,
      child: AnimatedOpacity(
        duration: const Duration(milliseconds: 260),
        opacity: visible ? 1 : 0,
        child: child,
      ),
    );
  }

  Widget _buildPanel() {
    return Container(
      padding: const EdgeInsets.fromLTRB(18, 14, 18, 8),
      decoration: const BoxDecoration(
        color: Palette.surface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(26)),
        border: Border(top: BorderSide(color: Palette.line)),
      ),
      child: SafeArea(
        top: false,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              StepSlider(
                value: m.step,
                names: m.project.stepNames,
                onChanged: (v) {
                  m.step = v;
                  m.changed();
                  setState(() {});
                },
                onEnd: (v) {
                  m.step = v;
                  _scheduleSave();
                },
              ),
              _slider('Opacidade da foto', m.refOpacity, 0, 1, (v) => m.refOpacity = v),
              _slider('Opacidade da guia', m.guideOpacity, 0, 1, (v) => m.guideOpacity = v),
              _slider('Escala do decalque', m.ovScale, 0.2, 3, (v) => m.ovScale = v),
              _slider('Rotação do decalque', m.ovRot * 180 / math.pi, -180, 180,
                  (v) => m.ovRot = v * math.pi / 180,
                  suffix: '°'),
              _slider('Espessura do traço', m.brushPx, 1, 14, (v) => m.brushPx = v,
                  suffix: ' px'),
              const SizedBox(height: 6),
              Row(
                children: [
                  for (final c in _inks)
                    Padding(
                      padding: const EdgeInsets.only(right: 10),
                      child: PressableScale(
                        onTap: () {
                          m.color = c;
                          setState(() {});
                        },
                        child: Container(
                          width: 30,
                          height: 30,
                          decoration: BoxDecoration(
                            color: Color(c),
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: m.color == c ? Palette.accent : Palette.line,
                              width: m.color == c ? 3 : 1.5,
                            ),
                          ),
                        ),
                      ),
                    ),
                  const Spacer(),
                  TextButton.icon(
                    onPressed: () {
                      m.resetOverlay();
                      m.refitView();
                      setState(() {});
                    },
                    icon: const Icon(Icons.restart_alt_rounded, size: 18),
                    label: const Text('Recentralizar'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _slider(String label, double value, double min, double max,
      void Function(double) apply,
      {String suffix = ''}) {
    final shown = suffix.isEmpty
        ? '${(value * 100).round()}%'
        : '${value.toStringAsFixed(suffix == '°' ? 0 : 1)}$suffix';
    final display = label.startsWith('Escala') ? '${(value * 100).round()}%' : shown;
    return Row(
      children: [
        SizedBox(
          width: 138,
          child: Text(label,
              style: const TextStyle(fontSize: 12.5, color: Palette.textDim)),
        ),
        Expanded(
          child: Slider(
            value: value.clamp(min, max).toDouble(),
            min: min,
            max: max,
            onChanged: (v) {
              apply(v);
              m.changed();
              setState(() {});
            },
          ),
        ),
        SizedBox(
          width: 46,
          child: Text(display,
              textAlign: TextAlign.right,
              style: const TextStyle(fontSize: 12.5)),
        ),
      ],
    );
  }
}
