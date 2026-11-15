import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:webview_flutter/webview_flutter.dart';

import '../../core/app_state.dart';
import '../../core/spring.dart';
import '../../core/theme.dart';

const _ua = 'Mozilla/5.0 (Linux; Android 14; Pixel 8) AppleWebKit/537.36 '
    '(KHTML, like Gecko) Chrome/130.0.0.0 Mobile Safari/537.36';

/// JavaScript injetado em cada página: segurar o dedo numa foto (0,55 s) a captura.
/// Com "Modo toque" ligado, um toque simples também captura.
const _pickJs = r'''
(function () {
  if (!window.__lfInstalled) {
    window.__lfInstalled = true;
    window.__lfCapture = false;
    var timer = null, sx = 0, sy = 0, fired = false;

    function bgUrl(el) {
      var s = window.getComputedStyle(el).backgroundImage || '';
      var m = s.match(/url\(["']?(.*?)["']?\)/);
      return m ? m[1] : '';
    }
    function pick(x, y) {
      var els = document.elementsFromPoint(x, y);
      for (var i = 0; i < els.length; i++) {
        var el = els[i], src = '', w = 0, h = 0;
        if (el.tagName === 'IMG') {
          src = el.currentSrc || el.src || el.getAttribute('data-src') || '';
          w = el.naturalWidth || 0; h = el.naturalHeight || 0;
          var a = el.closest ? el.closest('a') : null;
          if (a && a.href && /\.(jpe?g|png|webp)(\?|#|$)/i.test(a.href)) src = a.href;
        } else {
          src = bgUrl(el);
        }
        if (src) return { src: src, w: w, h: h };
      }
      return null;
    }
    function send(r) {
      LoomisPick.postMessage(JSON.stringify(r || { error: 'nenhuma imagem aqui' }));
    }

    document.addEventListener('touchstart', function (e) {
      if (e.touches.length !== 1) return;
      var t = e.touches[0];
      sx = t.clientX; sy = t.clientY; fired = false;
      clearTimeout(timer);
      timer = setTimeout(function () {
        var r = pick(sx, sy);
        if (r) { fired = true; send(r); }
      }, 550);
    }, { passive: true, capture: true });

    document.addEventListener('touchmove', function (e) {
      var t = e.touches[0];
      if (Math.abs(t.clientX - sx) > 10 || Math.abs(t.clientY - sy) > 10) clearTimeout(timer);
    }, { passive: true, capture: true });

    ['touchend', 'touchcancel'].forEach(function (n) {
      document.addEventListener(n, function () { clearTimeout(timer); }, { passive: true, capture: true });
    });

    document.addEventListener('contextmenu', function (e) {
      if (fired || window.__lfCapture) e.preventDefault();
    }, true);

    document.addEventListener('click', function (e) {
      if (fired) { e.preventDefault(); e.stopPropagation(); fired = false; return; }
      if (!window.__lfCapture) return;
      e.preventDefault(); e.stopPropagation();
      send(pick(e.clientX, e.clientY));
    }, true);
  }
})();
''';

/// Aba "Pesquisar": mini-navegador para achar referências na web e mandar
/// qualquer foto direto para o Estúdio (segure o dedo sobre a imagem).
class BrowserScreen extends StatefulWidget {
  const BrowserScreen({
    super.key,
    required this.active,
    required this.onOpenedProject,
    required this.onLeave,
  });

  final bool active;
  final VoidCallback onOpenedProject;
  final VoidCallback onLeave;

  @override
  State<BrowserScreen> createState() => _BrowserScreenState();
}

class _BrowserScreenState extends State<BrowserScreen>
    with AutomaticKeepAliveClientMixin {
  late final WebViewController _c;
  final _field = TextEditingController();
  final _focus = FocusNode();

  bool _started = false;
  bool _tapMode = false;
  bool _canBack = false;
  bool _busy = false;
  int _progress = 100;
  String _url = '';
  String _term = 'portrait reference';

  static final _engines = <(String, String Function(String))>[
    ('DuckDuckGo', (q) => 'https://duckduckgo.com/?q=$q&iax=images&ia=images'),
    ('Google', (q) => 'https://www.google.com/search?tbm=isch&q=$q'),
    ('Pinterest', (q) => 'https://www.pinterest.com/search/pins/?q=$q'),
    ('Unsplash', (q) => 'https://unsplash.com/s/photos/${q.replaceAll('+', '-')}'),
  ];

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _c = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(Palette.bg)
      ..addJavaScriptChannel('LoomisPick', onMessageReceived: (m) => _onPick(m.message))
      ..setNavigationDelegate(NavigationDelegate(
        onProgress: (p) {
          if (mounted) setState(() => _progress = p);
        },
        onPageStarted: _updateUrl,
        onUrlChange: (change) {
          final u = change.url;
          if (u != null) _updateUrl(u);
        },
        onPageFinished: (u) async {
          _updateUrl(u);
          await _inject();
          await _refreshBack();
        },
        // bloqueia esquemas que abririam outros apps (intent://, market://...)
        onNavigationRequest: (r) => r.url.startsWith('http') || r.url.startsWith('about:')
            ? NavigationDecision.navigate
            : NavigationDecision.prevent,
      ));
    if (defaultTargetPlatform == TargetPlatform.android) {
      _c.setUserAgent(_ua);
    }
    if (widget.active) _start();
  }

  @override
  void didUpdateWidget(covariant BrowserScreen old) {
    super.didUpdateWidget(old);
    if (widget.active && !_started) _start();
  }

  @override
  void dispose() {
    _field.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _start() {
    _started = true;
    _load(_engines.first.$2(Uri.encodeQueryComponent(_term)));
  }

  void _load(String url) {
    try {
      _c.loadRequest(Uri.parse(url));
    } catch (_) {
      _snack('Endereço inválido.');
    }
  }

  void _updateUrl(String u) {
    _url = u;
    if (!_focus.hasFocus && mounted) {
      _field.text = u;
    }
  }

  Future<void> _refreshBack() async {
    final b = await _c.canGoBack();
    if (mounted) setState(() => _canBack = b);
  }

  Future<void> _inject() async {
    try {
      await _c.runJavaScript(_pickJs);
      await _c.runJavaScript('window.__lfCapture = $_tapMode;');
    } catch (_) {}
  }

  void _go(String raw) {
    final t = raw.trim();
    if (t.isEmpty) return;
    _focus.unfocus();
    if (RegExp(r'^https?://', caseSensitive: false).hasMatch(t)) {
      _load(t);
    } else if (!t.contains(' ') && t.contains('.')) {
      _load('https://$t');
    } else {
      _term = t;
      _load(_engines.first.$2(Uri.encodeQueryComponent(t)));
    }
  }

  void _snack(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(text)));
  }

  // ------------------------------------------------------------ captura

  Future<void> _onPick(String raw) async {
    if (_busy) return;
    Map<String, dynamic> j;
    try {
      j = jsonDecode(raw) as Map<String, dynamic>;
    } catch (_) {
      return;
    }
    if (j['error'] != null) {
      _snack('Não achei uma imagem ali. Tente segurar direto sobre a foto.');
      return;
    }
    var src = (j['src'] as String? ?? '').trim();
    if (src.isEmpty) return;
    if (src.startsWith('//')) src = 'https:$src';

    setState(() => _busy = true);
    try {
      final Uint8List bytes;
      if (src.startsWith('data:')) {
        final i = src.indexOf(',');
        if (i < 0 || !src.substring(0, i).contains('base64')) {
          throw 'formato de imagem não suportado';
        }
        bytes = base64Decode(src.substring(i + 1));
      } else if (src.startsWith('http')) {
        final res = await http.get(Uri.parse(src), headers: {
          'User-Agent': _ua,
          'Referer': _url,
          'Accept': 'image/*,*/*;q=0.8',
        }).timeout(const Duration(seconds: 30));
        if (res.statusCode != 200) throw 'o site recusou (${res.statusCode})';
        bytes = res.bodyBytes;
      } else {
        throw 'esta imagem é protegida pelo site (${src.split(':').first})';
      }

      final ui.Image decoded;
      try {
        final codec = await ui.instantiateImageCodec(bytes);
        decoded = (await codec.getNextFrame()).image;
      } catch (_) {
        throw 'formato de imagem não suportado (SVG/GIF animado?)';
      }
      if (!mounted) return;
      final ok = await _confirm(bytes, decoded.width, decoded.height);
      if (ok != true || !mounted) return;

      widget.onOpenedProject();
      await AppScope.of(context).createFromBytes(bytes);
    } catch (e) {
      _snack('Não foi possível usar a imagem: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<bool?> _confirm(Uint8List bytes, int w, int h) {
    final low = math.min(w, h) < 400;
    return showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Palette.surface,
        title: const Text('Usar como referência?'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxHeight: 280),
                    child: Image.memory(bytes, fit: BoxFit.contain),
                  ),
                ),
              ),
              const SizedBox(height: 10),
              Text('$w × $h px',
                  style: const TextStyle(color: Palette.textDim, fontSize: 12.5)),
              if (low)
                const Padding(
                  padding: EdgeInsets.only(top: 6),
                  child: Text(
                    'Resolução baixa: a detecção do rosto e o decalque podem ficar piores. '
                    'Se puder, abra a imagem em tamanho maior e capture de novo.',
                    style: TextStyle(color: Palette.accent, fontSize: 12.5),
                  ),
                ),
              const SizedBox(height: 8),
              const Text(
                'Use para estudo pessoal e respeite os direitos do autor ao compartilhar.',
                style: TextStyle(color: Palette.textDim, fontSize: 11.5),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancelar')),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Usar no Estúdio')),
        ],
      ),
    );
  }

  // ----------------------------------------------------------------- UI

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return PopScope(
      canPop: !widget.active,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        if (await _c.canGoBack()) {
          await _c.goBack();
        } else {
          widget.onLeave();
        }
      },
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Pesquisar',
                  style: TextStyle(fontSize: 26, fontWeight: FontWeight.w700)),
              const SizedBox(height: 10),
              TextField(
                controller: _field,
                focusNode: _focus,
                keyboardType: TextInputType.url,
                textInputAction: TextInputAction.go,
                onSubmitted: _go,
                onTap: () => _field.selection =
                    TextSelection(baseOffset: 0, extentOffset: _field.text.length),
                decoration: InputDecoration(
                  hintText: 'Pesquisar imagens ou digitar um site',
                  prefixIcon: const Icon(Icons.search_rounded),
                  filled: true,
                  fillColor: Palette.surface,
                  isDense: true,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(18),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
              const SizedBox(height: 8),
              SizedBox(
                height: 34,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: _engines.length,
                  separatorBuilder: (_, __) => const SizedBox(width: 8),
                  itemBuilder: (_, i) => PressableScale(
                    onTap: () => _load(
                        _engines[i].$2(Uri.encodeQueryComponent(_term))),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14),
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: Palette.surface,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: Palette.line),
                      ),
                      child: Text(_engines[i].$1,
                          style: const TextStyle(
                              fontSize: 12.5, fontWeight: FontWeight.w600)),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              if (_progress < 100)
                LinearProgressIndicator(
                  value: _progress / 100,
                  minHeight: 2,
                  color: Palette.accent,
                  backgroundColor: Palette.line,
                )
              else
                const SizedBox(height: 2),
              const SizedBox(height: 6),
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(18),
                  child: Stack(
                    children: [
                      Positioned.fill(child: WebViewWidget(controller: _c)),
                      if (_busy)
                        const Positioned.fill(
                          child: ColoredBox(
                            color: Color(0x88000000),
                            child: Center(
                              child: CircularProgressIndicator(color: Palette.accent),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  IconButton(
                    onPressed: _canBack ? () => _c.goBack() : null,
                    icon: const Icon(Icons.arrow_back_rounded),
                  ),
                  IconButton(
                    onPressed: () => _c.goForward(),
                    icon: const Icon(Icons.arrow_forward_rounded),
                  ),
                  IconButton(
                    onPressed: () => _c.reload(),
                    icon: const Icon(Icons.refresh_rounded),
                  ),
                  const Spacer(),
                  PressableScale(
                    onTap: () {
                      setState(() => _tapMode = !_tapMode);
                      _c.runJavaScript('window.__lfCapture = $_tapMode;');
                      _snack(_tapMode
                          ? 'Modo toque ligado: um toque numa foto a captura.'
                          : 'Modo toque desligado: segure o dedo na foto para capturar.');
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                      decoration: BoxDecoration(
                        color: _tapMode ? Palette.accent : Palette.surfaceHi,
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.touch_app_rounded,
                              size: 18,
                              color: _tapMode ? Palette.bg : Palette.text),
                          const SizedBox(width: 6),
                          Text('Modo toque',
                              style: TextStyle(
                                  fontSize: 12.5,
                                  fontWeight: FontWeight.w700,
                                  color: _tapMode ? Palette.bg : Palette.text)),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
              const Text(
                'Segure o dedo numa foto para usá-la como referência.',
                style: TextStyle(color: Palette.textDim, fontSize: 12),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
