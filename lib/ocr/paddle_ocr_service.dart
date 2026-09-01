import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

class PaddleOcrService {
  PaddleOcrService({this.pythonPath, this.bridgePath});

  final String? pythonPath;
  final String? bridgePath;
  Process? _process;
  StreamSubscription<String>? _stdoutSubscription;
  final Map<String, Completer<PaddleOcrResult>> _pending = {};
  Completer<void>? _ready;
  Future<void> _tail = Future.value();
  int _sequence = 0;
  String _lastError = '';

  Future<void> close() async {
    final process = _process;
    _process = null;
    if (process != null) {
      await process.stdin.close();
      process.kill();
    }
    await _stdoutSubscription?.cancel();
    _stdoutSubscription = null;
  }

  Future<PaddleOcrResult> recognize(
    String pngBase64, {
    required int imageWidth,
    required int imageHeight,
  }) {
    final operation = _tail.then((_) => _recognize(pngBase64));
    _tail = operation.then<void>((_) {}, onError: (_) {});
    return operation;
  }

  Future<PaddleOcrResult> _recognize(String pngBase64) async {
    if (pngBase64.isEmpty) {
      throw StateError('Native window capture returned an empty PNG.');
    }
    await _ensureStarted();
    final id = 'ocr-${DateTime.now().microsecondsSinceEpoch}-${_sequence++}';
    final completer = Completer<PaddleOcrResult>();
    _pending[id] = completer;
    _process!.stdin.writeln(jsonEncode({'id': id, 'pngBase64': pngBase64}));
    await _process!.stdin.flush();
    try {
      return await completer.future.timeout(const Duration(seconds: 45));
    } on TimeoutException {
      _pending.remove(id);
      throw TimeoutException(
          'PaddleOCR did not finish within 45 seconds. $_lastError');
    }
  }

  Future<void> _ensureStarted() async {
    if (_process != null) return _ready!.future;
    final root = _findProjectRoot();
    final bundled = p.join(
      File(Platform.resolvedExecutable).parent.parent.path,
      'Resources',
      'PaddleOCR',
      'jd_paddle_ocr',
    );
    final useBundled = File(bundled).existsSync();
    final executable = useBundled
        ? bundled
        : pythonPath ??
            Platform.environment['JD_PADDLE_PYTHON'] ??
            p.join(root.path, '.paddleocr-venv', 'bin', 'python');
    final bridge =
        bridgePath ?? p.join(root.path, 'tools', 'paddle_ocr_bridge.py');
    if (!File(executable).existsSync()) {
      throw StateError('Bundled PaddleOCR runtime is missing. Rebuild with '
          'tools/build_standalone_macos.sh.');
    }
    if (!useBundled && !File(bridge).existsSync()) {
      throw StateError('PaddleOCR bridge is missing at $bridge.');
    }
    _ready = Completer<void>();
    _process = await Process.start(
      executable,
      useBundled ? const [] : [bridge],
      workingDirectory: useBundled ? File(bundled).parent.path : root.path,
      environment: {
        ...Platform.environment,
        'PADDLE_PDX_CACHE_HOME':
            p.join(Directory.systemTemp.path, 'jd_automation_paddlex_cache'),
        'PADDLE_PDX_DISABLE_MODEL_SOURCE_CHECK': 'True',
        'OMP_NUM_THREADS': '2',
        'FLAGS_paddle_num_threads': '2',
      },
    );
    _stdoutSubscription = _process!.stdout
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen(_handleLine);
    _process!.stderr.transform(utf8.decoder).listen((value) {
      final cleaned = value.trim();
      if (cleaned.isNotEmpty) _lastError = cleaned;
    });
    unawaited(_process!.exitCode.then((code) {
      final error = StateError('PaddleOCR process exited with code $code. '
          '$_lastError');
      if (!(_ready?.isCompleted ?? true)) _ready!.completeError(error);
      for (final completer in _pending.values) {
        if (!completer.isCompleted) completer.completeError(error);
      }
      _pending.clear();
      _stdoutSubscription?.cancel();
      _stdoutSubscription = null;
      _process = null;
      _ready = null;
    }));
    return _ready!.future.timeout(const Duration(seconds: 90));
  }

  void _handleLine(String line) {
    Map<String, dynamic> payload;
    try {
      payload = jsonDecode(line) as Map<String, dynamic>;
    } catch (_) {
      return;
    }
    if (payload['event'] == 'ready') {
      if (!(_ready?.isCompleted ?? true)) _ready!.complete();
      return;
    }
    final id = payload['id']?.toString();
    if (id == null) return;
    final completer = _pending.remove(id);
    if (completer == null) return;
    if (payload['error'] case final Object error) {
      completer.completeError(StateError('PaddleOCR failed: $error'));
      return;
    }
    List<Map<String, Object?>> maps(String key) =>
        (payload[key] as List<Object?>? ?? const [])
            .whereType<Map<String, dynamic>>()
            .map((item) => item.cast<String, Object?>())
            .toList(growable: false);
    completer.complete(PaddleOcrResult(
      observations: maps('observations'),
      visualRegions: maps('visualRegions'),
    ));
  }

  Directory _findProjectRoot() {
    final starts = <Directory>[
      Directory.current,
      File(Platform.resolvedExecutable).parent,
    ];
    for (final start in starts) {
      var current = start.absolute;
      for (var depth = 0; depth < 14; depth++) {
        if (File(p.join(current.path, 'tools', 'paddle_ocr_bridge.py'))
            .existsSync()) {
          return current;
        }
        final parent = current.parent;
        if (parent.path == current.path) break;
        current = parent;
      }
    }
    final bundledRoot = File(Platform.resolvedExecutable).parent.parent;
    if (File(
            p.join(bundledRoot.path, 'Resources', 'PaddleOCR', 'jd_paddle_ocr'))
        .existsSync()) {
      return bundledRoot;
    }
    throw StateError('Could not locate PaddleOCR runtime.');
  }
}

class PaddleOcrResult {
  const PaddleOcrResult({
    required this.observations,
    required this.visualRegions,
  });

  final List<Map<String, Object?>> observations;
  final List<Map<String, Object?>> visualRegions;
}
