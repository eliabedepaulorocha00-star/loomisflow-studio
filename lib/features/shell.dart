import 'package:flutter/material.dart';

import '../core/spring.dart';
import '../core/theme.dart';
import 'browser/browser_screen.dart';
import 'gallery/gallery_screen.dart';
import 'library/library_screen.dart';
import 'studio/studio_screen.dart';

/// Navegação inferior limpa com 3 abas: Estúdio · Referências · Progresso.
class Shell extends StatefulWidget {
  const Shell({super.key});

  @override
  State<Shell> createState() => _ShellState();
}

class _ShellState extends State<Shell> {
  int _tab = 0;

  static const _tabs = [
    (Icons.auto_awesome_outlined, Icons.auto_awesome, 'Estúdio'),
    (Icons.collections_outlined, Icons.collections, 'Referências'),
    (Icons.travel_explore_outlined, Icons.travel_explore, 'Pesquisar'),
    (Icons.timeline_outlined, Icons.timeline, 'Progresso'),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(
        index: _tab,
        children: [
          const StudioScreen(),
          LibraryScreen(onOpenedProject: () => setState(() => _tab = 0)),
          BrowserScreen(
            active: _tab == 2,
            onOpenedProject: () => setState(() => _tab = 0),
            onLeave: () => setState(() => _tab = 0),
          ),
          GalleryScreen(onOpenedProject: () => setState(() => _tab = 0)),
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
          child: Container(
            height: 64,
            decoration: BoxDecoration(
              color: Palette.surface,
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: Palette.line),
            ),
            child: LayoutBuilder(builder: (context, box) {
              final w = box.maxWidth / _tabs.length;
              return Stack(
                children: [
                  AnimatedPositioned(
                    duration: kSpringDuration,
                    curve: kSpringCurve,
                    left: _tab * w + 8,
                    top: 8,
                    width: w - 16,
                    height: 48,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: Palette.accent.withValues(alpha: 0.14),
                        borderRadius: BorderRadius.circular(18),
                      ),
                    ),
                  ),
                  Row(
                    children: [
                      for (var i = 0; i < _tabs.length; i++)
                        Expanded(
                          child: PressableScale(
                            onTap: () => setState(() => _tab = i),
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(
                                  i == _tab ? _tabs[i].$2 : _tabs[i].$1,
                                  size: 22,
                                  color: i == _tab ? Palette.accent : Palette.textDim,
                                ),
                                const SizedBox(height: 3),
                                Text(
                                  _tabs[i].$3,
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w600,
                                    color: i == _tab ? Palette.accent : Palette.textDim,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                    ],
                  ),
                ],
              );
            }),
          ),
        ),
      ),
    );
  }
}
