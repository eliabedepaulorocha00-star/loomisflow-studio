import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../../core/app_state.dart';
import '../../core/guide_renderer.dart';
import '../../core/models.dart';
import '../../core/spring.dart';
import '../../core/theme.dart';
import '../../widgets/step_slider.dart';

/// Modo Câmera/AR: projeta a guia do passo atual sobre o caderno físico.
/// Use o celular em um tripé/suporte olhando para a folha; arraste, pince e gire
/// para encaixar a guia no papel e depois TRAVE o decalque para não mexer mais.
class ArScreen extends StatefulWidget {
  const ArScreen({super.key});

  @override
  State<ArScreen> createState() => _ArScreenState();
}

class _ArScreenState extends State<ArScreen> with WidgetsBindingObserver {
  CameraController? _cam;
  String? _error;

  // Transformação do decalque (em px de tela)
  Offset _off = Offset.zero;
  double _scale = 1;
  double _rot = 0;
  Offset _startOff = Offset.zero;
  Offset _startFocal = Offset.zero;
  double _startScale = 1, _startRot = 0;

  double _step = 0;
  double _guideOpacity = 0.85;
  double _photoOpacity = 0.0;
  bool _locked = false;
  bool _hideUi = false;
  bool _showShading = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WakelockPlus.enable();
    _initCamera();
  }

  Future<void> _initCamera() async {
    try {
      final cams = await availableCameras();
      if (cams.isEmpty) {
        setState(() => _error = 'Nenhuma câmera encontrada.');
        return;
      }
      final back = cams.firstWhere(
        (c) => c.lensDirection == CameraLensDirection.back,
        orElse: () => cams.first,
      );
      final ctrl = CameraController(back, ResolutionPreset.high, enableAudio: false);
      await ctrl.initialize();
      if (!mounted) {
        await ctrl.dispose();
        return;
      }
      setState(() => _cam = ctrl);
    } on CameraException catch (e) {
      setState(() => _error = e.code == 'CameraAccessDenied'
          ? 'Permissão da câmera negada. Libere o acesso nas configurações do sistema.'
          : 'Erro na câmera: ${e.description ?? e.code}');
    } catch (e) {
      setState(() => _error = 'Erro na câmera: $e');
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final c = _cam;
    if (c == null || !c.value.isInitialized) return;
    if (state == AppLifecycleState.inactive) {
      c.dispose();
      _cam = null;
    } else if (state == AppLifecycleState.resumed) {
      _initCamera();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    WakelockPlus.disable();
    _cam?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final pr = app.current!;
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          Positioned.fill(child: _preview()),
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onScaleStart: (d) {
                _startOff = _off;
                _startScale = _scale;
                _startRot = _rot;
                _startFocal = d.focalPoint;
              },
              onScaleUpdate: (d) {
                if (_locked) return;
                setState(() {
                  _off = _startOff + (d.focalPoint - _startFocal);
                  _scale = (_startScale * d.scale).clamp(0.15, 6.0).toDouble();
                  _rot = _startRot + d.rotation;
                });
              },
              child: RepaintBoundary(
                child: CustomPaint(
                  painter: _ArPainter(
                    project: pr,
                    reference: app.currentReference,
                    shading: _showShading ? app.currentShading : null,
                    off: _off,
                    scale: _scale,
                    rot: _rot,
                    step: _step,
                    guideOpacity: _guideOpacity,
                    photoOpacity: _photoOpacity,
                  ),
                  size: Size.infinite,
                ),
              ),
            ),
          ),
          if (!_hideUi) ..._controls(pr),
          Positioned(
            top: 0,
            right: 0,
            child: SafeArea(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => setState(() => _hideUi = !_hideUi),
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Opacity(
                    opacity: _hideUi ? 0.25 : 0.9,
                    child: Icon(_hideUi
                        ? Icons.fullscreen_exit_rounded
                        : Icons.center_focus_strong_outlined),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _preview() {
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Text(_error!,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Palette.textDim)),
        ),
      );
    }
    final c = _cam;
    if (c == null || !c.value.isInitialized) {
      return const Center(child: CircularProgressIndicator(color: Palette.accent));
    }
    final ps = c.value.previewSize!; // vem em paisagem
    return ClipRect(
      child: FittedBox(
        fit: BoxFit.cover,
        child: SizedBox(
          width: ps.height,
          height: ps.width,
          child: CameraPreview(c),
        ),
      ),
    );
  }

  List<Widget> _controls(Project pr) {
    return [
      Positioned(
        top: 0,
        left: 0,
        child: SafeArea(
          child: IconButton(
            icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20),
            onPressed: () => Navigator.of(context).pop(),
          ),
        ),
      ),
      Positioned(
        left: 0,
        right: 0,
        bottom: 0,
        child: Container(
          padding: const EdgeInsets.fromLTRB(18, 12, 18, 6),
          decoration: BoxDecoration(
            color: Palette.surface.withValues(alpha: 0.92),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(26)),
          ),
          child: SafeArea(
            top: false,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                StepSlider(
                  value: _step,
                  onChanged: (v) => setState(() => _step = v),
                ),
                _row('Opacidade da guia', _guideOpacity,
                    (v) => setState(() => _guideOpacity = v)),
                _row('Foto de referência', _photoOpacity,
                    (v) => setState(() => _photoOpacity = v)),
                const SizedBox(height: 4),
                Row(
                  children: [
                    Expanded(
                      child: _Pill(
                        icon: _locked ? Icons.lock_rounded : Icons.lock_open_rounded,
                        label: _locked ? 'Decalque travado' : 'Travar decalque',
                        active: _locked,
                        onTap: () => setState(() => _locked = !_locked),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _Pill(
                        icon: Icons.contrast_rounded,
                        label: 'Sombras',
                        active: _showShading,
                        onTap: () => setState(() => _showShading = !_showShading),
                      ),
                    ),
                    const SizedBox(width: 8),
                    _Pill(
                      icon: Icons.restart_alt_rounded,
                      label: '',
                      onTap: () => setState(() {
                        _off = Offset.zero;
                        _scale = 1;
                        _rot = 0;
                      }),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    ];
  }

  Widget _row(String label, double v, ValueChanged<double> on) {
    return Row(
      children: [
        SizedBox(
          width: 130,
          child: Text(label,
              style: const TextStyle(fontSize: 12.5, color: Palette.textDim)),
        ),
        Expanded(child: Slider(value: v, onChanged: on)),
      ],
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill({required this.icon, required this.label, required this.onTap, this.active = false});
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool active;

  @override
  Widget build(BuildContext context) {
    return PressableScale(
      onTap: onTap,
      child: Container(
        height: 42,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          color: active ? Palette.accent : Palette.surfaceHi,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 18, color: active ? Palette.bg : Palette.text),
            if (label.isNotEmpty) ...[
              const SizedBox(width: 6),
              Flexible(
                child: Text(label,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                        color: active ? Palette.bg : Palette.text)),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _ArPainter extends CustomPainter {
  _ArPainter({
    required this.project,
    required this.reference,
    required this.shading,
    required this.off,
    required this.scale,
    required this.rot,
    required this.step,
    required this.guideOpacity,
    required this.photoOpacity,
  });

  final Project project;
  final ui.Image? reference;
  final ui.Image? shading;
  final Offset off;
  final double scale, rot, step, guideOpacity, photoOpacity;

  @override
  void paint(Canvas canvas, Size size) {
    final g = project.guide;
    final img = g.imageSize;
    final base = math.min(size.width, size.height) * 0.8 /
        math.max(img.width, img.height);
    final k = base * scale;

    canvas.save();
    canvas.translate(size.width / 2 + off.dx, size.height / 2 + off.dy);
    canvas.rotate(rot);
    canvas.scale(k);
    canvas.translate(-img.width / 2, -img.height / 2);

    if (reference != null && photoOpacity > 0.01) {
      canvas.drawImageRect(
        reference!,
        Rect.fromLTWH(0, 0, reference!.width.toDouble(), reference!.height.toDouble()),
        Offset.zero & img,
        Paint()
          ..filterQuality = FilterQuality.medium
          ..color = Color.fromRGBO(255, 255, 255, photoOpacity),
      );
    }
    // linhas finas e luminosas para ficarem visíveis sobre o papel branco
    paintGuide(
      canvas,
      g,
      step,
      color: const Color(0xFF00E5A8),
      opacity: guideOpacity,
      lineScale: 1 / k * 0.8,
      shading: shading,
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _ArPainter o) =>
      o.off != off ||
      o.scale != scale ||
      o.rot != rot ||
      o.step != step ||
      o.guideOpacity != guideOpacity ||
      o.photoOpacity != photoOpacity ||
      o.reference != reference ||
      o.shading != shading;
}
