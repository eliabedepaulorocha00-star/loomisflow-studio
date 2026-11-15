import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

const String kUserAgent = 'LoomisFlowStudio/1.0 (app open-source de desenho)';

class RefImage {
  RefImage({
    required this.title,
    required this.thumbUrl,
    required this.fullUrl,
    required this.license,
    required this.author,
    required this.pageUrl,
  });

  final String title;
  final String thumbUrl;
  final String fullUrl; // versão de até ~1600 px
  final String license;
  final String author;
  final String pageUrl;

  String get credit => '$author · $license · Wikimedia Commons';
}

/// Busca imagens de referência na API pública e gratuita do Wikimedia Commons.
/// Só devolve arquivos com licença livre (domínio público ou Creative Commons).
class CommonsApi {
  static final _tag = RegExp(r'<[^>]*>');

  static Future<List<RefImage>> search(String query, {int limit = 30}) async {
    final uri = Uri.https('commons.wikimedia.org', '/w/api.php', {
      'action': 'query',
      'format': 'json',
      'origin': '*',
      'generator': 'search',
      'gsrsearch': '$query filetype:bitmap',
      'gsrnamespace': '6',
      'gsrlimit': '$limit',
      'prop': 'imageinfo',
      'iiprop': 'url|extmetadata|size',
      'iiurlwidth': '1600',
      'iiextmetadatafilter': 'LicenseShortName|Artist|NonFree',
    });
    final res = await http
        .get(uri, headers: {'User-Agent': kUserAgent})
        .timeout(const Duration(seconds: 20));
    if (res.statusCode != 200) {
      throw Exception('Servidor respondeu ${res.statusCode}');
    }
    final json = jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
    final pages = (json['query']?['pages'] as Map<String, dynamic>?)?.values ?? [];

    final out = <RefImage>[];
    for (final raw in pages) {
      final page = raw as Map<String, dynamic>;
      final infos = page['imageinfo'] as List?;
      if (infos == null || infos.isEmpty) continue;
      final info = infos.first as Map<String, dynamic>;
      final meta = (info['extmetadata'] as Map<String, dynamic>?) ?? {};
      String m(String k) => ((meta[k] as Map?)?['value'] ?? '').toString();

      final license = m('LicenseShortName');
      final nonFree = m('NonFree').toLowerCase() == 'true';
      final lic = license.toLowerCase();
      final free = lic.contains('public domain') ||
          lic.startsWith('cc') ||
          lic == 'pd' ||
          lic.contains('cc0');
      if (nonFree || !free) continue;

      final thumb = (info['thumburl'] ?? info['url'])?.toString();
      final full = (info['thumburl'] ?? info['url'])?.toString();
      if (thumb == null || full == null) continue;
      final w = (info['width'] as num?) ?? 0;
      final h = (info['height'] as num?) ?? 0;
      if (w < 300 || h < 300) continue;

      final title = (page['title'] as String? ?? '')
          .replaceFirst('File:', '')
          .replaceAll(RegExp(r'\.[A-Za-z0-9]+$'), '');
      out.add(RefImage(
        title: title,
        thumbUrl: thumb,
        fullUrl: full,
        license: license,
        author: m('Artist').replaceAll(_tag, '').trim().isEmpty
            ? 'Autor desconhecido'
            : m('Artist').replaceAll(_tag, '').trim(),
        pageUrl: info['descriptionurl']?.toString() ??
            'https://commons.wikimedia.org/wiki/${page['title']}',
      ));
    }
    return out;
  }

  static Future<Uint8List> download(String url) async {
    final res = await http
        .get(Uri.parse(url), headers: {'User-Agent': kUserAgent})
        .timeout(const Duration(seconds: 40));
    if (res.statusCode != 200) {
      throw Exception('Falha ao baixar (${res.statusCode})');
    }
    return res.bodyBytes;
  }
}
