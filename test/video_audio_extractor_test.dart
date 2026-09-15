import 'package:flutter_test/flutter_test.dart';
import 'package:jd_automation/capture/video_audio_extractor.dart';

void main() {
  test('extracts the first audio stream as speech-ready mono 16 kHz WAV', () {
    const extractor = VideoAudioExtractor(
      ffmpegExecutable: '/test/ffmpeg',
      ffprobeExecutable: '/test/ffprobe',
    );
    expect(extractor.probeArguments('/input/video.mp4'),
        containsAllInOrder(['-select_streams', 'a:0']));
    expect(
      extractor.extractionArguments('/input/video.mp4', '/output/audio.wav'),
      containsAllInOrder(['-map', '0:a:0', '-vn', '-ac', '1', '-ar', '16000']),
    );
    expect(extractor.volumeArguments('/output/audio.wav'),
        containsAllInOrder(['-af', 'volumedetect']));
    expect(VideoAudioExtractor.audibleThresholdDb, -55);
  });
}
