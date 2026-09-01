enum MessageCaptureRoute { textOcr, imageAnalysis, defer }

/// Clipboard copy is used only as a type discriminator. It never supplies
/// customer text and there is deliberately no cross-route fallback.
MessageCaptureRoute strictMessageCaptureRoute(String classification) =>
    switch (classification) {
      'text' => MessageCaptureRoute.textOcr,
      'image' => MessageCaptureRoute.imageAnalysis,
      _ => MessageCaptureRoute.defer,
    };
