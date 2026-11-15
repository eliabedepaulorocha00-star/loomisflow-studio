import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/app_state.dart';
import '../../core/spring.dart';
import '../../core/theme.dart';
import 'commons_api.dart';

/// Biblioteca de Referências: imagens livres (domínio público / Creative Commons)
/// do Wikimedia Commons. Sem conta, sem chave de API, sem limite.
class LibraryScreen extends StatefulWidget {
  const LibraryScreen({super.key, required this.onOpenedProject});
  final VoidCallback onOpenedProject;

  @override
  State<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends State<LibraryScreen>
    with AutomaticKeepAliveClientMixin {
  final _controller = TextEditingController();
  List<({String title, String query})> _collections = [];
  int _selected = 0;
  List<RefImage> _items = [];
  bool _loading = false;
  String? _error;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _loadCatalog();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _loadCatalog() async {
    try {
      final raw = await rootBundle.loadString('assets/library/catalog.json');
      final j = jsonDecode(raw) as Map<String, dynamic>;
      _collections = [
        for (final c in (j['collections'] as List))
          (title: c['title'] as String, query: c['query'] as String),
      ];
    } catch (_) {
      _collections = [(title: 'Retratos', query: 'portrait face photograph')];
    }
    if (mounted) setState(() {});
    _run(_collections.first.query);
  }

  Future<void> _run(String query) async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final r = await CommonsApi.search(query);
      if (!mounted) return;
      setState(() {
        _items = r;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'Sem conexão com a biblioteca online.\n'
            'Você ainda pode usar suas próprias fotos no Estúdio.';
      });
    }
  }

  Future<void> _use(RefImage item) async {
    final app = AppScope.of(context);
    final messenger = ScaffoldMessenger.of(context);
    widget.onOpenedProject();
    try {
      final bytes = await CommonsApi.download(item.fullUrl);
      await app.createFromBytes(bytes);
      final pr = app.current;
      if (pr != null) {
        pr.title = item.title.length > 40 ? '${item.title.substring(0, 40)}…' : item.title;
        await app.saveStep(pr);
        app.touch();
      }
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('Não foi possível baixar: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return SafeArea(
      bottom: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Referências',
                style: TextStyle(fontSize: 26, fontWeight: FontWeight.w700)),
            const SizedBox(height: 4),
            const Text('Modelos gratuitos com licença livre',
                style: TextStyle(color: Palette.textDim)),
            const SizedBox(height: 12),
            TextField(
              controller: _controller,
              textInputAction: TextInputAction.search,
              onSubmitted: (v) {
                if (v.trim().isEmpty) return;
                setState(() => _selected = -1);
                _run(v.trim());
              },
              decoration: InputDecoration(
                hintText: 'Buscar (ex.: old man portrait)',
                prefixIcon: const Icon(Icons.search_rounded),
                filled: true,
                fillColor: Palette.surface,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(18),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
            const SizedBox(height: 10),
            SizedBox(
              height: 38,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: _collections.length,
                separatorBuilder: (_, __) => const SizedBox(width: 8),
                itemBuilder: (_, i) {
                  final sel = i == _selected;
                  return PressableScale(
                    onTap: () {
                      setState(() => _selected = i);
                      _run(_collections[i].query);
                    },
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 220),
                      padding: const EdgeInsets.symmetric(horizontal: 14),
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: sel ? Palette.accent : Palette.surface,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: sel ? Palette.accent : Palette.line),
                      ),
                      child: Text(_collections[i].title,
                          style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: sel ? Palette.bg : Palette.text)),
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: 10),
            Expanded(child: _body()),
          ],
        ),
      ),
    );
  }

  Widget _body() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator(color: Palette.accent));
    }
    if (_error != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(_error!,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Palette.textDim)),
            const SizedBox(height: 12),
            TextButton(
              onPressed: () => _run(_selected >= 0 && _selected < _collections.length
                  ? _collections[_selected].query
                  : _controller.text),
              child: const Text('Tentar de novo'),
            ),
          ],
        ),
      );
    }
    if (_items.isEmpty) {
      return const Center(
        child: Text('Nada encontrado.', style: TextStyle(color: Palette.textDim)),
      );
    }
    return GridView.builder(
      padding: const EdgeInsets.only(bottom: 16),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        mainAxisSpacing: 10,
        crossAxisSpacing: 10,
        childAspectRatio: 0.78,
      ),
      itemCount: _items.length,
      itemBuilder: (_, i) => _Tile(item: _items[i], onUse: () => _use(_items[i])),
    );
  }
}

class _Tile extends StatelessWidget {
  const _Tile({required this.item, required this.onUse});
  final RefImage item;
  final VoidCallback onUse;

  @override
  Widget build(BuildContext context) {
    return PressableScale(
      onTap: onUse,
      pressedScale: 0.96,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(18),
        child: Container(
          color: Palette.surface,
          child: Stack(
            fit: StackFit.expand,
            children: [
              Image.network(
                item.thumbUrl,
                fit: BoxFit.cover,
                headers: const {'User-Agent': kUserAgent},
                cacheWidth: 500,
                errorBuilder: (_, __, ___) => const Center(
                    child: Icon(Icons.broken_image_outlined, color: Palette.textDim)),
                loadingBuilder: (c, child, p) => p == null
                    ? child
                    : const Center(
                        child: SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Palette.accent),
                        ),
                      ),
              ),
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: Container(
                  padding: const EdgeInsets.fromLTRB(10, 18, 10, 8),
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [Colors.transparent, Color(0xDD000000)],
                    ),
                  ),
                  child: Text(item.license,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 11, color: Palette.textDim)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
