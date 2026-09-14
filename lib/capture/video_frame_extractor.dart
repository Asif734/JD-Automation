import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;

class ExtractedVideoFrames {
  const ExtractedVideoFrames({
    required this.videoPath,
    required this.sha256Digest,
    required this.framePaths,
  });

  final String videoPath;
  final String sha256Digest;
  final List<String> framePaths;
}

class VideoFrameExtractor {
  const VideoFrameExtractor({this.ffmpegExecutable});

  static const maximumFrames = 20;
  final String? ffmpegExecutable;

  List<String> buildArguments(String inputPath, String outputPattern) => [
        '-hide_banner',
        '-loglevel',
        'error',
        '-i',
        inputPath,
        '-vf',
        'fps=1',
        '-frames:v',
        '$maximumFrames',
        '-q:v',
        '2',
        outputPattern,
      ];

  Future<ExtractedVideoFrames> extract(String videoPath) async {
    final video = File(videoPath);
    if (!await video.exists()) {
      throw VideoFrameExtractionException(
          'Downloaded video is missing: $videoPath');
    }
    final digest = (await sha256.bind(video.openRead()).first).toString();
    final frameDirectory = Directory(
      p.join(video.parent.path, 'frames_${digest.substring(0, 16)}'),
    );
    await frameDirectory.create(recursive: true);
    final existing = await _frames(frameDirectory);
    if (existing.isNotEmpty) {
      return ExtractedVideoFrames(
        videoPath: videoPath,
        sha256Digest: digest,
        framePaths: existing.take(maximumFrames).toList(growable: false),
      );
    }

    final executable = ffmpegExecutable ?? await _findFfmpeg();
    final pattern = p.join(frameDirectory.path, 'frame_%02d.jpg');
    final result = await Process.run(
      executable,
      buildArguments(videoPath, pattern),
    );
    if (result.exitCode != 0) {
      throw VideoFrameExtractionException(
        'FFmpeg failed to sample the customer video: ${result.stderr}',
      );
    }
    final frames = await _frames(frameDirectory);
    if (frames.isEmpty) {
      throw const VideoFrameExtractionException(
        'The customer video contained no decodable frames.',
      );
    }
    return ExtractedVideoFrames(
      videoPath: videoPath,
      sha256Digest: digest,
      framePaths: frames.take(maximumFrames).toList(growable: false),
    );
  }

  Future<List<String>> _frames(Directory directory) async {
    final paths = await directory
        .list()
        .where((entry) =>
            entry is File &&
            RegExp(r'^frame_\d{2}\.jpg$').hasMatch(p.basename(entry.path)))
        .map((entry) => entry.path)
        .toList();
    paths.sort();
    return paths;
  }

  Future<String> _findFfmpeg() async {
    for (final candidate in const [
      '/opt/homebrew/bin/ffmpeg',
      '/usr/local/bin/ffmpeg',
      '/usr/bin/ffmpeg',
    ]) {
      if (await File(candidate).exists()) return candidate;
    }
    throw const VideoFrameExtractionException(
      'FFmpeg is required for customer-video analysis but was not found.',
    );
  }
}

class VideoFrameExtractionException implements Exception {
  const VideoFrameExtractionException(this.message);
  final String message;

  @override
  String toString() => message;
}
