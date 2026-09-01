import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

class LocalKnowledgeRetriever {
  LocalKnowledgeRetriever(this.knowledgeDirectory);

  final Directory knowledgeDirectory;
  static final Map<String, Future<List<Map<String, dynamic>>>> _cache = {};

  Future<List<Map<String, Object?>>> retrieve(String query,
      {int limit = 5}) async {
    final records = await _cache.putIfAbsent(
      knowledgeDirectory.absolute.path,
      () => _loadRecords(),
    );
    final scored = <({double score, Map<String, dynamic> record})>[];
    for (final record in records) {
      final score = _score(query, record);
      if (score > 0) scored.add((score: score, record: record));
    }
    scored.sort((left, right) {
      final byScore = right.score.compareTo(left.score);
      if (byScore != 0) return byScore;
      return ((right.record['priority'] as num?) ?? 0)
          .compareTo((left.record['priority'] as num?) ?? 0);
    });
    return scored.take(limit).map((item) => _compact(item.record)).toList();
  }

  Future<List<Map<String, Object?>>> mediaForRecords(
      List<Map<String, Object?>> records) async {
    final seen = <String>{};
    final media = <Map<String, Object?>>[];
    for (final record in records) {
      final recordId = record['id']?.toString() ?? '';
      final models = (record['models'] as List<Object?>? ?? const [])
          .map((value) => value.toString())
          .toList(growable: false);
      for (final rawSource
          in (record['source_files'] as List<Object?>? ?? const [])) {
        final relativePath = rawSource.toString();
        if (!_isSupportedMedia(relativePath)) continue;
        final file = File(p.join(knowledgeDirectory.path, relativePath));
        if (!await file.exists()) continue;
        final absolutePath = file.absolute.path;
        if (!seen.add(absolutePath)) continue;
        media.add({
          'media_id': _mediaId(relativePath),
          'kind': _mediaKind(relativePath),
          'caption': p.basenameWithoutExtension(relativePath),
          'path': absolutePath,
          'record_id': recordId,
          'models': models,
        });
      }
    }
    return media;
  }

  Future<List<Map<String, dynamic>>> _loadRecords() async {
    final file = File(p.join(knowledgeDirectory.path, 'rag_cards',
        'customer_service_rag_cards.jsonl'));
    if (!await file.exists()) return const [];
    final records = <Map<String, dynamic>>[];
    await for (final line in file
        .openRead()
        .transform(utf8.decoder)
        .transform(const LineSplitter())) {
      if (line.trim().isEmpty) continue;
      final decoded = jsonDecode(line);
      if (decoded is Map<String, dynamic> && decoded['status'] == 'active') {
        records.add(decoded);
      }
    }
    return records;
  }

  double _score(String query, Map<String, dynamic> record) {
    final normalizedQuery = _normalize(query);
    if (normalizedQuery.isEmpty) return 0;
    var score = 0.0;
    score += _termScore(normalizedQuery, record['keywords'], 8);
    score += _termScore(normalizedQuery, record['synonyms'], 7);
    score += _termScore(normalizedQuery, record['models'], 10);
    score += _textScore(normalizedQuery, record['issue']?.toString(), 4);
    score += _textScore(normalizedQuery, record['intent']?.toString(), 2);
    score += _textScore(normalizedQuery, record['id']?.toString(), 6);
    score += _termScore(normalizedQuery, record['source_files'], 3);
    if (_isMediaQuery(normalizedQuery) && _hasSupportedMedia(record)) {
      score += 20;
    }
    if (_isProductCatalogQuery(normalizedQuery)) {
      final intent = _normalize(record['intent']?.toString() ?? '');
      final id = _normalize(record['id']?.toString() ?? '');
      if (intent.contains('presale')) score += 18;
      if (id.contains('selling_points') || id.contains('recommend')) {
        score += 22;
      }
    }
    return score;
  }

  bool _isProductCatalogQuery(String query) => const [
        'recommend',
        'suggest',
        'whichmodel',
        'whatmodel',
        'shouldibuy',
        'shouldwebuy',
        'needtobuy',
        'wanttobuy',
        'whatproducts',
        'whichproducts',
        'whatmodels',
        'whichmodels',
        'doyouhave',
        '推荐',
        '建议',
        '哪款',
        '买哪',
        '选哪',
      ].any(query.contains);

  bool _isMediaQuery(String query) => const [
        'image',
        'images',
        'picture',
        'pictures',
        'photo',
        'photos',
        'video',
        '图片',
        '照片',
        '外观',
        '截图',
        '视频',
      ].any(query.contains);

  bool _hasSupportedMedia(Map<String, dynamic> record) {
    final sources = record['source_files'];
    return sources is List<Object?> &&
        sources.any((source) => _isSupportedMedia(source.toString()));
  }

  double _termScore(String query, Object? rawTerms, double weight) {
    if (rawTerms is! List<Object?>) return 0;
    var score = 0.0;
    for (final raw in rawTerms) {
      final term = _normalize(raw.toString());
      if (term.length >= 2 && query.contains(term)) score += weight;
    }
    return score;
  }

  double _textScore(String query, String? text, double weight) {
    if (text == null) return 0;
    final normalized = _normalize(text);
    if (normalized.isEmpty) return 0;
    if (query.contains(normalized) || normalized.contains(query)) return weight;
    final queryPairs = _pairs(query);
    final textPairs = _pairs(normalized);
    if (queryPairs.isEmpty || textPairs.isEmpty) return 0;
    final overlap = queryPairs.intersection(textPairs).length;
    return overlap / queryPairs.length * weight;
  }

  Set<String> _pairs(String value) => {
        for (var index = 0; index + 1 < value.length; index++)
          value.substring(index, index + 2),
      };

  String _normalize(String value) =>
      value.toLowerCase().replaceAll(RegExp(r'\s+'), '');

  bool _isSupportedMedia(String path) => const {
        '.png',
        '.jpg',
        '.jpeg',
        '.webp',
        '.gif',
        '.mp4',
        '.mov',
      }.contains(p.extension(path).toLowerCase());

  String _mediaKind(String path) =>
      const {'.mp4', '.mov'}.contains(p.extension(path).toLowerCase())
          ? 'video'
          : 'image';

  String _mediaId(String relativePath) {
    // FNV-1a gives a deterministic ID without adding a crypto dependency.
    var hash = 0xcbf29ce484222325;
    for (final byte in utf8.encode(relativePath)) {
      hash ^= byte;
      hash = (hash * 0x100000001b3) & 0x7fffffffffffffff;
    }
    return 'kb_${hash.toRadixString(16).padLeft(16, '0')}';
  }

  Map<String, Object?> _compact(Map<String, dynamic> record) => {
        for (final key in const [
          'id',
          'product_line',
          'models',
          'intent',
          'issue',
          'risk_level',
          'auto_reply_allowed',
          'required_slots',
          'reply_template',
          'actions',
          'do_not_say',
          'escalation',
          'source_files',
        ])
          if (record.containsKey(key)) key: record[key],
      };
}
