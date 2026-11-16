import 'dart:io';

import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/app_state.dart';
import '../../core/exporter.dart';
import '../../core/models.dart';
import '../../core/spring.dart';
import '../../core/theme.dart';

/// Meu Progresso / Galeria: projetos salvos automaticamente no aparelho.
class GalleryScreen extends StatelessWidget {
  const GalleryScreen({super.key, required this.onOpenedProject});
  final VoidCallback onOpenedProject;

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final list = app.projects;
    final strokes = list.fold<int>(0, (a, p) => a + p.strokes.length);
    return SafeArea(
      bottom: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Meu Progresso',
                style: TextStyle(fontSize: 26, fontWeight: FontWeight.w700)),
            const SizedBox(height: 12),
            Row(
              children: [
                _Stat(value: '${list.length}', label: 'retratos'),
                const SizedBox(width: 10),
                _Stat(value: '$strokes', label: 'traços'),
                const SizedBox(width: 10),
                _Stat(
                  value: '${list.where((p) => p.strokes.isNotEmpty).length}',
                  label: 'com esboço',
                ),
              ],
            ),
            const SizedBox(height: 14),
            Expanded(
              child: list.isEmpty
                  ? const Center(
                      child: Text(
                        'Seus retratos aparecem aqui.\nSalvamento automático e local.',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: Palette.textDim, height: 1.4),
                      ),
                    )
                  : GridView.builder(
                      padding: const EdgeInsets.only(bottom: 16),
                      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: 2,
                        mainAxisSpacing: 10,
                        crossAxisSpacing: 10,
                        childAspectRatio: 0.82,
                      ),
                      itemCount: list.length,
                      itemBuilder: (_, i) => _ProjectCard(
                        project: list[i],
                        onTap: () => _openSheet(context, list[i]),
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  void _openSheet(BuildContext context, Project pr) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Palette.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(26)),
      ),
      builder: (_) => _ProjectSheet(project: pr, onOpen: () async {
        await AppScope.of(context).open(pr);
        onOpenedProject();
      }),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.value, required this.label});
  final String value, label;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: Palette.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Palette.line),
        ),
        child: Column(
          children: [
            Text(value,
                style: const TextStyle(
                    fontSize: 22, fontWeight: FontWeight.w700, color: Palette.accent)),
            Text(label, style: const TextStyle(fontSize: 12, color: Palette.textDim)),
          ],
        ),
      ),
    );
  }
}

class _ProjectCard extends StatelessWidget {
  const _ProjectCard({required this.project, required this.onTap});
  final Project project;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final progress = (project.step / project.maxStep).clamp(0.0, 1.0);
    return PressableScale(
      onTap: onTap,
      pressedScale: 0.96,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(18),
        child: Container(
          color: Palette.surface,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Image.file(
                  File(project.referencePath),
                  fit: BoxFit.cover,
                  width: double.infinity,
                  cacheWidth: 500,
                  errorBuilder: (_, __, ___) =>
                      const Center(child: Icon(Icons.image_not_supported_outlined)),
                ),
              ),
              LinearProgressIndicator(
                value: progress,
                minHeight: 3,
                backgroundColor: Palette.line,
                color: Palette.accent,
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(project.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                    const SizedBox(height: 2),
                    Text('${project.strokes.length} traços',
                        style: const TextStyle(fontSize: 11.5, color: Palette.textDim)),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ProjectSheet extends StatefulWidget {
  const _ProjectSheet({required this.project, required this.onOpen});
  final Project project;
  final Future<void> Function() onOpen;

  @override
  State<_ProjectSheet> createState() => _ProjectSheetState();
}

class _ProjectSheetState extends State<_ProjectSheet> {
  final ValueNotifier<double?> _progress = ValueNotifier(null);
  bool _working = false;

  Project get pr => widget.project;

  Future<void> _export(Future<File> Function() make, String text) async {
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _working = true);
    try {
      final f = await make();
      await Share.shareXFiles([XFile(f.path)], text: text);
    } on StateError catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('Falha ao exportar: $e')));
    } finally {
      if (mounted) {
        _progress.value = null;
        setState(() => _working = false);
      }
    }
  }

  Future<void> _rename() async {
    final c = TextEditingController(text: pr.title);
    final app = AppScope.of(context);
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Palette.surface,
        title: const Text('Renomear'),
        content: TextField(controller: c, autofocus: true),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancelar')),
          TextButton(
              onPressed: () => Navigator.pop(ctx, c.text.trim()),
              child: const Text('Salvar')),
        ],
      ),
    );
    if (name == null || name.isEmpty) return;
    pr.title = name;
    await app.saveStep(pr);
    app.touch();
    if (mounted) setState(() {});
  }

  Future<void> _delete() async {
    final app = AppScope.of(context);
    final nav = Navigator.of(context);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Palette.surface,
        title: const Text('Excluir retrato?'),
        content: const Text('A foto, o guia e o esboço serão apagados do aparelho.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Excluir')),
        ],
      ),
    );
    if (ok != true) return;
    await app.delete(pr);
    nav.pop();
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(18, 16, 18, 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(pr.title,
                      style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
                ),
                IconButton(onPressed: _rename, icon: const Icon(Icons.edit_outlined)),
                IconButton(onPressed: _delete, icon: const Icon(Icons.delete_outline_rounded)),
              ],
            ),
            const SizedBox(height: 6),
            ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: SizedBox(
                height: 200,
                width: double.infinity,
                child: Image.file(File(pr.referencePath), fit: BoxFit.cover, cacheWidth: 700),
              ),
            ),
            const SizedBox(height: 14),
            _action(Icons.draw_outlined, 'Continuar no Estúdio', () async {
              Navigator.pop(context);
              await widget.onOpen();
            }),
            _action(Icons.compare_rounded, 'Compartilhar imagem comparativa (PNG)',
                _working ? null : () => _export(() => Exporter.comparisonPng(pr), 'Feito no LoomisFlow Studio')),
            _action(Icons.movie_creation_outlined, 'Compartilhar time-lapse (vídeo MP4)',
                _working
                    ? null
                    : () => _export(
                          () => Exporter.timelapse(pr,
                              onProgress: (v) => _progress.value = v),
                          'Time-lapse feito no LoomisFlow Studio',
                        )),
            _action(Icons.gif_box_outlined, 'Compartilhar time-lapse (GIF animado)',
                _working
                    ? null
                    : () => _export(
                          () => Exporter.timelapseGif(pr,
                              onProgress: (v) => _progress.value = v),
                          'Time-lapse feito no LoomisFlow Studio',
                        )),
            ValueListenableBuilder<double?>(
              valueListenable: _progress,
              builder: (_, v, __) => v == null && !_working
                  ? const SizedBox.shrink()
                  : Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: LinearProgressIndicator(
                          value: v, color: Palette.accent, backgroundColor: Palette.line),
                    ),
            ),
            const SizedBox(height: 4),
            const Text('Exportações sem marca d\'água. Tudo é gerado no aparelho.',
                style: TextStyle(fontSize: 11.5, color: Palette.textDim)),
          ],
        ),
      ),
    );
  }

  Widget _action(IconData icon, String label, VoidCallback? onTap) {
    return PressableScale(
      onTap: onTap,
      child: Opacity(
        opacity: onTap == null ? 0.4 : 1,
        child: Container(
          margin: const EdgeInsets.only(bottom: 8),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
          decoration: BoxDecoration(
            color: Palette.surfaceHi,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Row(
            children: [
              Icon(icon, color: Palette.accent, size: 22),
              const SizedBox(width: 12),
              Expanded(child: Text(label, style: const TextStyle(fontWeight: FontWeight.w600))),
            ],
          ),
        ),
      ),
    );
  }
}
