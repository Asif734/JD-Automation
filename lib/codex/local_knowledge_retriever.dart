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
    final records = <Map<String, dynamic>>[];
    await _loadJsonLines(
      File(p.join(knowledgeDirectory.path, 'rag_cards',
          'customer_service_rag_cards.jsonl')),
      records,
      defaultPriority: 100,
      activeOnly: true,
    );
    await _loadJsonLines(
      File(p.join(knowledgeDirectory.path, 'rag_cards', 'source_chunks.jsonl')),
      records,
      defaultPriority: 40,
    );

    final markdownFiles = await knowledgeDirectory
        .list(recursive: true, followLinks: false)
        .where((entry) =>
            entry is File && p.extension(entry.path).toLowerCase() == '.md')
        .cast<File>()
        .toList();
    markdownFiles.sort((left, right) => left.path.compareTo(right.path));
    for (final file in markdownFiles) {
      final relativePath = p.relative(file.path, from: knowledgeDirectory.path);
      final content = await file.readAsString();
      records.addAll(_markdownRecords(relativePath, content));
    }
    return records;
  }

  Future<void> _loadJsonLines(
    File file,
    List<Map<String, dynamic>> records, {
    required int defaultPriority,
    bool activeOnly = false,
  }) async {
    if (!await file.exists()) return;
    await for (final line in file
        .openRead()
        .transform(utf8.decoder)
        .transform(const LineSplitter())) {
      if (line.trim().isEmpty) continue;
      final decoded = jsonDecode(line);
      if (decoded is Map<String, dynamic> &&
          (!activeOnly || decoded['status'] == 'active')) {
        records.add(
            {...decoded, 'priority': decoded['priority'] ?? defaultPriority});
      }
    }
  }

  List<Map<String, dynamic>> _markdownRecords(
      String relativePath, String content) {
    if (content.trim().isEmpty) return const [];
    const maximumChunkLength = 5000;
    final sections = <({String title, String text})>[];
    var title = p.basenameWithoutExtension(relativePath);
    var buffer = StringBuffer();

    void saveSection() {
      final text = buffer.toString().trim();
      if (text.isNotEmpty) sections.add((title: title, text: text));
      buffer = StringBuffer();
    }

    for (final line in const LineSplitter().convert(content)) {
      final heading = RegExp(r'^#{1,6}\s+(.+?)\s*$').firstMatch(line);
      if (heading != null) {
        saveSection();
        title = heading.group(1)!.trim();
      }
      buffer.writeln(line);
    }
    saveSection();

    final records = <Map<String, dynamic>>[];
    var chunkIndex = 0;
    for (final section in sections) {
      for (var offset = 0; offset < section.text.length;) {
        final end = (offset + maximumChunkLength).clamp(0, section.text.length);
        final chunk = section.text.substring(offset, end).trim();
        offset = end;
        if (chunk.isEmpty) continue;
        chunkIndex += 1;
        final models = RegExp(r'\b[A-Z]{1,5}[ -]?\d{2,5}[A-Z]{0,3}\b')
            .allMatches(chunk.toUpperCase())
            .map((match) => match.group(0)!.replaceAll(RegExp(r'[ -]'), ''))
            .toSet()
            .toList(growable: false);
        records.add({
          'id': 'md_${_stableId('$relativePath:$chunkIndex')}',
          'type': 'source_markdown',
          'source_file': relativePath,
          'source_files': [relativePath],
          'title': section.title,
          'models': models,
          'intent': 'knowledge_source',
          'content': chunk,
          'priority': 20,
        });
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
    score += _textScore(normalizedQuery, record['title']?.toString(), 5);
    score += _textScore(normalizedQuery, record['content']?.toString(), 6);
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
    // Curated active cards carry reviewed reply policy, required slots, and
    // governed media links. Keep a genuinely matching card ahead of duplicate
    // source chunks/Markdown while allowing source-only exact matches through.
    if (record['status'] == 'active' && score >= 8) score += 30;
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
        'show',
        'display',
        'view',
        'video',
        '图片',
        '照片',
        '展示',
        '看看',
        '参考',
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
          'type',
          'title',
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
          'source_file',
          'content',
        ])
          if (record.containsKey(key)) key: record[key],
      };

  String _stableId(String value) {
    var hash = 0xcbf29ce484222325;
    for (final byte in utf8.encode(value)) {
      hash ^= byte;
      hash = (hash * 0x100000001b3) & 0x7fffffffffffffff;
    }
    return hash.toRadixString(16).padLeft(16, '0');
  }
}
