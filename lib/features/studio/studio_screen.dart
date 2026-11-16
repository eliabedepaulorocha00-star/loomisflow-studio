import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../core/app_state.dart';
import '../../core/guide_renderer.dart';
import '../../core/models.dart';
import '../../core/spring.dart';
import '../../core/theme.dart';
import '../../widgets/step_slider.dart';
import '../trace/ar_screen.dart';
import '../trace/trace_screen.dart';

class StudioScreen extends StatelessWidget {
  const StudioScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final cur = state.current;
    return SafeArea(
      bottom: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Expanded(
                  child: Text('Estúdio',
                      style: TextStyle(fontSize: 26, fontWeight: FontWeight.w700)),
                ),
                if (cur != null)
                  PressableScale(
                    onTap: () => _showSourceSheet(context),
                    child: const Padding(
                      padding: EdgeInsets.all(8),
                      child: Icon(Icons.add_photo_alternate_outlined,
                          color: Palette.accent),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 10),
            Expanded(
              child: AnimatedSwitcher(
                duration: kSpringDuration,
                switchInCurve: Curves.easeOutCubic,
                child: state.busy
                    ? _Busy(label: state.busyLabel, key: const ValueKey('busy'))
                    : cur == null
                        ? const _EmptyStudio(key: ValueKey('empty'))
                        : _Workbench(
                            key: ValueKey('${cur.id}-${cur.figure != null}'),
                            project: cur,
                          ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

Future<void> pickAndCreate(BuildContext context, ImageSource source) async {
  final state = AppScope.of(context);
  final messenger = ScaffoldMessenger.of(context);
  try {
    final file = await ImagePicker().pickImage(source: source);
    if (file == null) return;
    final bytes = await file.readAsBytes();
    await state.createFromBytes(bytes);
  } catch (e) {
    messenger.showSnackBar(
      SnackBar(content: Text('Não foi possível abrir a imagem: $e')),
    );
  }
}

void _showSourceSheet(BuildContext context) {
  showModalBottomSheet<void>(
    context: context,
    backgroundColor: Palette.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (ctx) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.photo_library_outlined, color: Palette.accent),
              title: const Text('Escolher da galeria'),
              onTap: () {
                Navigator.pop(ctx);
                pickAndCreate(context, ImageSource.gallery);
              },
            ),
            ListTile(
              leading: const Icon(Icons.photo_camera_outlined, color: Palette.accent),
              title: const Text('Tirar foto agora'),
              onTap: () {
                Navigator.pop(ctx);
                pickAndCreate(context, ImageSource.camera);
              },
            ),
          ],
        ),
      ),
    ),
  );
}

class _EmptyStudio extends StatelessWidget {
  const _EmptyStudio({super.key});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 120,
              height: 120,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border:
                    Border.all(color: Palette.accent.withValues(alpha: 0.6), width: 2),
              ),
              child: CustomPaint(painter: _LogoPainter()),
            ),
            const SizedBox(height: 24),
            const Text('Transforme qualquer foto\nem um passo a passo de construção',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600, height: 1.3)),
            const SizedBox(height: 8),
            const Text('Rosto (Loomis) ou corpo inteiro. Tudo roda no seu aparelho.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Palette.textDim)),
            const SizedBox(height: 28),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _BigButton(
                  icon: Icons.photo_library_outlined,
                  label: 'Galeria',
                  onTap: () => pickAndCreate(context, ImageSource.gallery),
                ),
                const SizedBox(width: 14),
                _BigButton(
                  icon: Icons.photo_camera_outlined,
                  label: 'Câmera',
                  onTap: () => pickAndCreate(context, ImageSource.camera),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _LogoPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final p = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.6
      ..color = Palette.accent;
    canvas.drawOval(Rect.fromCenter(center: c.translate(24, 0), width: 14, height: 60), p);
    canvas.drawOval(Rect.fromCenter(center: c.translate(-24, 0), width: 14, height: 60),
        p..color = Palette.accent.withValues(alpha: 0.4));
    canvas.drawLine(c.translate(-50, 0), c.translate(50, 0), p..color = Palette.accent);
    canvas.drawLine(c.translate(0, -50), c.translate(0, 50), p);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _BigButton extends StatelessWidget {
  const _BigButton({required this.icon, required this.label, required this.onTap});
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return PressableScale(
      onTap: onTap,
      child: Container(
        width: 132,
        padding: const EdgeInsets.symmetric(vertical: 18),
        decoration: BoxDecoration(
          color: Palette.surface,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: Palette.line),
        ),
        child: Column(
          children: [
            Icon(icon, color: Palette.accent, size: 28),
            const SizedBox(height: 8),
            Text(label, style: const TextStyle(fontWeight: FontWeight.w600)),
          ],
        ),
      ),
    );
  }
}

class _Busy extends StatelessWidget {
  const _Busy({super.key, required this.label});
  final String label;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(
            width: 44,
            height: 44,
            child: CircularProgressIndicator(strokeWidth: 3, color: Palette.accent),
          ),
          const SizedBox(height: 18),
          Text(label, style: const TextStyle(color: Palette.textDim)),
        ],
      ),
    );
  }
}

class _Workbench extends StatefulWidget {
  const _Workbench({super.key, required this.project});
  final Project project;

  @override
  State<_Workbench> createState() => _WorkbenchState();
}

class _WorkbenchState extends State<_Workbench> {
  late double _step = math.min(widget.project.step, widget.project.maxStep);
  bool _adjusting = false;
  double _s0Scale = 1, _s0Rot = 0;

  void _syncAfterReturn(AppState state, Project pr) {
    if (!mounted) return;
    setState(() => _step = math.min(pr.step, pr.maxStep));
    state.touch(); // atualiza contagem de traços na galeria
  }

  Future<void> _menu(String v, AppState state) async {
    final pr = widget.project;
    switch (v) {
      case 'adjust':
        setState(() => _adjusting = !_adjusting);
      case 'reset':
        setState(pr.resetAdjust);
        await state.saveStep(pr);
      case 'face':
        await state.reanalyze(pr, force: GuideKind.face);
      case 'body':
        await state.reanalyze(pr, force: GuideKind.body);
      case 'auto':
        await state.reanalyze(pr);
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final pr = widget.project;
    final size = pr.guide.imageSize;
    final isBody = pr.figure != null;
    final reason = state.detectionProjectId == pr.id && state.detectionNote.isNotEmpty
        ? '\nMotivo: ${state.detectionNote}'
        : '';
    final status = isBody
        ? 'Guia de corpo (pose detectada)'
        : pr.guide.detected
            ? 'Guia de rosto'
            : 'Rosto não detectado — usando as proporções clássicas do Loomis.$reason';
    return Column(
      children: [
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(22),
            child: Container(
              color: Palette.surface,
              child: LayoutBuilder(builder: (context, box) {
                final pad = 10.0;
                final s = math.min((box.maxWidth - pad * 2) / size.width,
                    (box.maxHeight - pad * 2) / size.height);
                return Stack(
                  children: [
                    Positioned.fill(
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onScaleStart: _adjusting
                            ? (d) {
                                _s0Scale = pr.adjScale;
                                _s0Rot = pr.adjRot;
                              }
                            : null,
                        onScaleUpdate: _adjusting
                            ? (d) => setState(() {
                                  pr.adjDx += d.focalPointDelta.dx / s;
                                  pr.adjDy += d.focalPointDelta.dy / s;
                                  pr.adjScale =
                                      (_s0Scale * d.scale).clamp(0.3, 4.0).toDouble();
                                  pr.adjRot = _s0Rot + d.rotation;
                                })
                            : null,
                        onScaleEnd: _adjusting ? (_) => state.saveStep(pr) : null,
                        child: RepaintBoundary(
                          child: CustomPaint(
                            size: Size.infinite,
                            painter: _PreviewPainter(
                              project: pr,
                              step: _step,
                              reference: state.currentReference,
                              shading: state.currentShading,
                            ),
                          ),
                        ),
                      ),
                    ),
                    Positioned(
                      top: 8,
                      right: 8,
                      child: Row(
                        children: [
                          _RoundButton(
                            icon: Icons.open_with_rounded,
                            active: _adjusting,
                            tooltip: 'Ajustar a guia à mão',
                            onTap: () => setState(() => _adjusting = !_adjusting),
                          ),
                          const SizedBox(width: 8),
                          PopupMenuButton<String>(
                            tooltip: 'Opções da guia',
                            color: Palette.surfaceHi,
                            onSelected: (v) => _menu(v, state),
                            itemBuilder: (_) => [
                              const PopupMenuItem(
                                  value: 'adjust', child: Text('Ajustar guia à mão')),
                              if (pr.hasAdjust)
                                const PopupMenuItem(
                                    value: 'reset', child: Text('Restaurar ajuste')),
                              const PopupMenuItem(
                                  value: 'face', child: Text('Usar guia de rosto')),
                              const PopupMenuItem(
                                  value: 'body', child: Text('Usar guia de corpo')),
                              const PopupMenuItem(
                                  value: 'auto', child: Text('Reanalisar automaticamente')),
                            ],
                            child: Container(
                              width: 38,
                              height: 38,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: Palette.surfaceHi.withValues(alpha: 0.9),
                                border: Border.all(color: Palette.line),
                              ),
                              child: const Icon(Icons.more_vert_rounded, size: 20),
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (_adjusting)
                      Positioned(
                        left: 12,
                        bottom: 12,
                        right: 12,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                          decoration: BoxDecoration(
                            color: Palette.surfaceHi.withValues(alpha: 0.92),
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: Row(
                            children: [
                              const Expanded(
                                child: Text(
                                  'Arraste, pince e gire para encaixar a guia',
                                  style: TextStyle(fontSize: 12.5),
                                ),
                              ),
                              TextButton(
                                onPressed: () => setState(() => _adjusting = false),
                                child: const Text('Concluir'),
                              ),
                            ],
                          ),
                        ),
                      ),
                  ],
                );
              }),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Text(status,
              style: const TextStyle(color: Palette.textDim, fontSize: 12)),
        ),
        const SizedBox(height: 8),
        StepSlider(
          value: _step,
          names: pr.stepNames,
          onChanged: (v) => setState(() => _step = v),
          onEnd: (v) {
            pr.step = v;
            state.saveStep(pr);
          },
        ),
        const SizedBox(height: 4),
        Row(
          children: [
            Expanded(
              child: _ActionButton(
                icon: Icons.draw_outlined,
                label: 'Decalcar na tela',
                filled: true,
                onTap: () {
                  pr.step = _step;
                  Navigator.of(context)
                      .push(springRoute<void>(const TraceScreen()))
                      .then((_) => _syncAfterReturn(state, pr));
                },
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _ActionButton(
                icon: Icons.view_in_ar_outlined,
                label: 'AR no caderno',
                onTap: () {
                  pr.step = _step;
                  Navigator.of(context)
                      .push(springRoute<void>(const ArScreen()))
                      .then((_) => _syncAfterReturn(state, pr));
                },
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
      ],
    );
  }
}

class _RoundButton extends StatelessWidget {
  const _RoundButton({
    required this.icon,
    required this.onTap,
    required this.tooltip,
    this.active = false,
  });
  final IconData icon;
  final VoidCallback onTap;
  final String tooltip;
  final bool active;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: PressableScale(
        onTap: onTap,
        child: Container(
          width: 38,
          height: 38,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: active ? Palette.accent : Palette.surfaceHi.withValues(alpha: 0.9),
            border: Border.all(color: Palette.line),
          ),
          child: Icon(icon, size: 19, color: active ? Palette.bg : Palette.text),
        ),
      ),
    );
  }
}

class _ActionButton extends StatelessWidget {
  const _ActionButton({
    required this.icon,
    required this.label,
    required this.onTap,
    this.filled = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool filled;

  @override
  Widget build(BuildContext context) {
    return PressableScale(
      onTap: onTap,
      child: Container(
        height: 52,
        decoration: BoxDecoration(
          color: filled ? Palette.accent : Palette.surface,
          borderRadius: BorderRadius.circular(18),
          border: filled ? null : Border.all(color: Palette.line),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 20, color: filled ? Palette.bg : Palette.accent),
            const SizedBox(width: 8),
            Text(label,
                style: TextStyle(
                    fontWeight: FontWeight.w700,
                    color: filled ? Palette.bg : Palette.text)),
          ],
        ),
      ),
    );
  }
}

class _PreviewPainter extends CustomPainter {
  _PreviewPainter({
    required this.project,
    required this.step,
    required this.reference,
    required this.shading,
  }) : adjSig = project.adjSig;

  final Project project;
  final double step;
  final ui.Image? reference;
  final ui.Image? shading;
  final int adjSig;

  @override
  void paint(Canvas canvas, Size size) {
    final imageSize = project.guide.imageSize;
    const pad = 10.0;
    final avail = Size(size.width - pad * 2, size.height - pad * 2);
    final s = math.min(avail.width / imageSize.width, avail.height / imageSize.height);
    final dx = (size.width - imageSize.width * s) / 2;
    final dy = (size.height - imageSize.height * s) / 2;
    canvas.save();
    canvas.translate(dx, dy);
    canvas.scale(s);

    final dst = Offset.zero & imageSize;
    if (reference != null) {
      // a foto escurece conforme a guia ganha detalhe
      final a = (0.75 - step * 0.045).clamp(0.3, 0.75);
      canvas.drawImageRect(
        reference!,
        Rect.fromLTWH(0, 0, reference!.width.toDouble(), reference!.height.toDouble()),
        dst,
        Paint()
          ..filterQuality = FilterQuality.medium
          ..color = Color.fromRGBO(255, 255, 255, a),
      );
    }
    paintProjectGuide(canvas, project, step,
        color: Palette.guide, lineScale: 1 / s, shading: shading);
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _PreviewPainter old) =>
      old.step != step ||
      old.reference != reference ||
      old.shading != shading ||
      old.adjSig != adjSig ||
      old.project != project;
}
