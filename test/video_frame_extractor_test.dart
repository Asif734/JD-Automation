import 'package:flutter_test/flutter_test.dart';
import 'package:jd_automation/capture/video_frame_extractor.dart';

void main() {
  test('samples exactly one frame per second with a hard twenty-frame cap', () {
    const extractor = VideoFrameExtractor(ffmpegExecutable: '/test/ffmpeg');
    final arguments = extractor.buildArguments(
      '/input/customer.mp4',
      '/output/frame_%02d.jpg',
    );

    expect(arguments, containsAllInOrder(['-vf', 'fps=1']));
    expect(arguments, containsAllInOrder(['-frames:v', '20']));
    expect(arguments.last, '/output/frame_%02d.jpg');
    expect(VideoFrameExtractor.maximumFrames, 20);
  });
}
