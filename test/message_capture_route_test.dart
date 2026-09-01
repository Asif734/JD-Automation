import 'package:flutter_test/flutter_test.dart';
import 'package:jd_automation/capture/message_capture_route.dart';

void main() {
  test('strictly separates text, image, and unknown message routes', () {
    expect(strictMessageCaptureRoute('text'), MessageCaptureRoute.textOcr);
    expect(
        strictMessageCaptureRoute('image'), MessageCaptureRoute.imageAnalysis);
    expect(strictMessageCaptureRoute('unknown'), MessageCaptureRoute.defer);
    expect(strictMessageCaptureRoute('unavailable'), MessageCaptureRoute.defer);
  });
}
