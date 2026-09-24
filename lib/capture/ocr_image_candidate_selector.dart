import '../platform/macos_capture_adapter.dart';

/// Selects only visual regions owned by a customer message block. A region
/// cannot cross the next customer/seller sender label, which prevents outgoing
/// text bubbles from being promoted to incoming images.
class OcrImageCandidateSelector {
  const OcrImageCandidateSelector();

  List<OcrVisualRegion> select(
    OcrInspection inspection,
    String customer, {
    bool allowUnlabeledLatestImage = false,
    bool includeTextDense = false,
  }) {
    final left = inspection.chatLeft ?? .15;
    final right = inspection.chatRight ?? .68;
    final bottom = inspection.chatBottom ?? .90;
    final senderLabels = inspection.observations
        .where((item) =>
            item.x + item.width / 2 >= left &&
            item.x + item.width / 2 < right &&
            (_isCustomer(item.text, customer) || _isSeller(item.text)))
        .toList()
      ..sort((left, right) => left.y.compareTo(right.y));
    final selected = <OcrVisualRegion>[];
    for (var index = 0; index < senderLabels.length; index++) {
      final label = senderLabels[index];
      if (!_isCustomer(label.text, customer)) continue;
      final nextSenderY =
          index + 1 < senderLabels.length ? senderLabels[index + 1].y : .90;
      final matches = inspection.visualRegions
          .where((region) => _validGeometry(region, left, right))
          .where((region) =>
              includeTextDense || !isTextDense(region, inspection.observations))
          .where((region) =>
              label.y <= region.y &&
              region.y - label.y <= .13 &&
              region.y + region.height < nextSenderY - .002 &&
              region.y + region.height <= bottom)
          .toList()
        ..sort((left, right) =>
            (right.width * right.height).compareTo(left.width * left.height));
      if (matches.isNotEmpty) selected.add(matches.first);
    }

    if (selected.isEmpty && allowUnlabeledLatestImage && senderLabels.isEmpty) {
      final unlabeled = inspection.visualRegions
          .where((region) => _validGeometry(region, left, right))
          .where((region) =>
              includeTextDense || !isTextDense(region, inspection.observations))
          .where((region) =>
              region.x >= left &&
              // Customer media is left aligned. An unlabeled rectangle on the
              // seller side cannot be safely attributed to the customer.
              region.x <= left + (right - left) * .25 &&
              region.x + region.width <= right &&
              region.width >= .12 &&
              region.width <= .60 &&
              region.height >= .12)
          .toList();
      final outer = unlabeled.where((candidate) {
        return !unlabeled.any((container) {
          if (identical(candidate, container)) return false;
          const tolerance = .008;
          return container.x <= candidate.x + tolerance &&
              container.y <= candidate.y + tolerance &&
              container.x + container.width >=
                  candidate.x + candidate.width - tolerance &&
              container.y + container.height >=
                  candidate.y + candidate.height - tolerance &&
              container.width * container.height >
                  candidate.width * candidate.height * 1.25;
        });
      }).toList()
        ..sort((left, right) =>
            (right.y + right.height).compareTo(left.y + left.height));
      if (outer.isNotEmpty) selected.add(outer.first);
    }
    selected.sort((left, right) => right.y.compareTo(left.y));
    return selected;
  }

  /// Last-resort screenshot region for an incoming block when Vision did not
  /// emit a rectangle. This is bounded by sender labels, stays on the customer
  /// side, and rejects blocks containing ordinary message text.
  OcrVisualRegion? fallbackLatestCustomerBlock(
    OcrInspection inspection,
    String customer, {
    bool allowTextInsideBlock = false,
  }) =>
      fallbackRecentCustomerBlocks(
        inspection,
        customer,
        allowTextInsideBlock: allowTextInsideBlock,
        limit: 1,
      ).firstOrNull;

  /// Returns recent sender-bounded customer blocks, newest first. This lets
  /// recovery inspect an image immediately followed by a short message such
  /// as "check this" instead of looking only at that final text bubble.
  List<OcrVisualRegion> fallbackRecentCustomerBlocks(
    OcrInspection inspection,
    String customer, {
    bool allowTextInsideBlock = false,
    int limit = 3,
  }) {
    final left = inspection.chatLeft ?? .15;
    final right = inspection.chatRight ?? .68;
    final bottom = inspection.chatBottom ?? .90;
    final labels = inspection.observations
        .where((item) =>
            item.x + item.width / 2 >= left &&
            item.x + item.width / 2 < right &&
            (_isCustomer(item.text, customer) || _isSeller(item.text)))
        .toList()
      ..sort((a, b) => a.y.compareTo(b.y));

    final candidates = <OcrVisualRegion>[];
    for (var index = labels.length - 1;
        index >= 0 && candidates.length < limit;
        index--) {
      final label = labels[index];
      if (!_isCustomer(label.text, customer)) continue;
      final start = label.y + label.height + .004;
      final end =
          index + 1 < labels.length ? labels[index + 1].y - .004 : bottom;
      final height = end - start;
      if (height < .07) continue;
      final width = (right - left).clamp(.12, .42).toDouble();
      final candidate = OcrVisualRegion(
        x: left,
        y: start,
        width: width,
        height: height.clamp(.07, .60).toDouble(),
        confidence: 0,
      );
      final bodyCharacters = inspection.observations.where((item) {
        final centerX = item.x + item.width / 2;
        final centerY = item.y + item.height / 2;
        if (centerX < candidate.x ||
            centerX > candidate.x + candidate.width ||
            centerY < candidate.y ||
            centerY > candidate.y + candidate.height) {
          return false;
        }
        final text = item.text.trim();
        return !RegExp(r'^\d{1,2}:\d{2}(?::\d{2})?$').hasMatch(text) &&
            !text.contains('格志打印机');
      }).fold<int>(
          0,
          (total, item) =>
              total + item.text.replaceAll(RegExp(r'\s+'), '').length);
      // Text inside a screenshot belongs to the media, not necessarily to a
      // chat bubble. During unread recovery the caller can retain this whole
      // sender-bounded block and pass its screenshot to visual analysis.
      if (allowTextInsideBlock || bodyCharacters < 4) {
        candidates.add(candidate);
      }
    }
    return candidates;
  }

  /// Builds one crop containing the preceding customer block and the latest
  /// customer message. The visible batch is preserved even when pale media
  /// boundaries are not emitted as Vision rectangles.
  OcrVisualRegion? fallbackRecentCompanionBatch(
    OcrInspection inspection,
    String customer, {
    Duration maximumGap = const Duration(seconds: 20),
  }) =>
      fallbackRecentCustomerBatch(
        inspection,
        customer,
        maximumSpan: maximumGap,
        requireMultipleBlocks: true,
      );

  /// Returns one screenshot region for the newest customer event batch. The
  /// batch is derived from sender timestamps and layout, so image-only, text,
  /// video, and mixed turns follow the same recovery path.
  OcrVisualRegion? fallbackRecentCustomerBatch(
    OcrInspection inspection,
    String customer, {
    Duration maximumSpan = const Duration(seconds: 30),
    int maximumBlocks = 4,
    bool requireMultipleBlocks = false,
  }) {
    final left = inspection.chatLeft ?? .15;
    final right = inspection.chatRight ?? .68;
    final bottom = inspection.chatBottom ?? .90;
    final labels = inspection.observations.where((item) {
      final centerX = item.x + item.width / 2;
      return centerX >= left &&
          centerX < right &&
          (_isCustomer(item.text, customer) || _isSeller(item.text));
    }).toList()
      ..sort((a, b) => a.y.compareTo(b.y));
    final customerLabels = labels
        .where((label) => _isCustomer(label.text, customer))
        .toList(growable: false);
    if (customerLabels.isEmpty ||
        (requireMultipleBlocks && customerLabels.length < 2)) {
      return null;
    }

    final latest = customerLabels.last;
    final latestAt = _sentAtForLabel(inspection, latest);
    var firstIndex = customerLabels.length - 1;
    if (latestAt != null) {
      final minimumIndex = (customerLabels.length - maximumBlocks)
          .clamp(0, customerLabels.length);
      for (var index = customerLabels.length - 2;
          index >= minimumIndex;
          index--) {
        final candidateAt = _sentAtForLabel(inspection, customerLabels[index]);
        if (candidateAt == null) break;
        final span = latestAt.difference(candidateAt);
        if (span.isNegative || span > maximumSpan) break;
        firstIndex = index;
      }
    }
    if (requireMultipleBlocks && firstIndex == customerLabels.length - 1) {
      return null;
    }

    final first = customerLabels[firstIndex];
    final start = first.y + first.height + .004;
    final followingLabel =
        labels.where((label) => label.y > latest.y + .002).firstOrNull;
    final end = (followingLabel?.y ?? bottom) - .004;
    if (end - start < .07) return null;
    return OcrVisualRegion(
      x: left,
      y: start,
      width: (right - left).clamp(.12, .42).toDouble(),
      height: (end - start).clamp(.07, .76).toDouble(),
      confidence: 0,
    );
  }

  /// Absolute last resort for an unread event when OCR finds neither a sender
  /// label nor a media rectangle. The active customer is verified separately;
  /// this region is limited to that customer's transcript and excludes the
  /// sidebar, details panel, emoji toolbar, and composer.
  OcrVisualRegion? fallbackVerifiedChatViewport(OcrInspection inspection) {
    final left = inspection.chatLeft;
    final right = inspection.chatRight;
    final bottom = inspection.chatBottom;
    if (left == null || right == null || bottom == null) return null;
    const top = .14;
    final width = right - left;
    final height = bottom - top;
    if (width < .12 || height < .12) return null;
    return OcrVisualRegion(
      x: left,
      y: top,
      width: width.clamp(.12, .60).toDouble(),
      height: height.clamp(.12, .76).toDouble(),
      confidence: 0,
    );
  }

  bool _validGeometry(OcrVisualRegion region, double left, double right) =>
      region.x >= left &&
      region.x + region.width <= right &&
      region.y >= .14 &&
      region.y + region.height <= .90 &&
      region.width >= .035 &&
      region.height >= .065 &&
      // JD's video previews can occupy about half of the captured window.
      // Rejecting them here prevents both capture and the unanswered-message
      // recovery path from ever seeing the new customer turn.
      region.width <= .60 &&
      region.height <= .76;

  bool isTextDense(OcrVisualRegion region, List<OcrObservation> observations) {
    final contained = observations.where((text) {
      final centerX = text.x + text.width / 2;
      final centerY = text.y + text.height / 2;
      return centerX >= region.x &&
          centerX <= region.x + region.width &&
          centerY >= region.y &&
          centerY <= region.y + region.height;
    }).toList(growable: false);
    if (contained.length < 2) return false;
    final characters = contained.fold<int>(
        0, (total, item) => total + item.text.replaceAll(' ', '').length);
    if (characters < 20) return false;
    final textArea = contained.fold<double>(
        0, (total, item) => total + item.width * item.height);
    final regionArea = region.width * region.height;
    return regionArea > 0 && textArea / regionArea >= .12;
  }

  int textCharacterCount(
      OcrVisualRegion region, List<OcrObservation> observations) {
    return observations.where((text) {
      final centerX = text.x + text.width / 2;
      final centerY = text.y + text.height / 2;
      return centerX >= region.x &&
          centerX <= region.x + region.width &&
          centerY >= region.y &&
          centerY <= region.y + region.height;
    }).fold<int>(
        0,
        (total, item) =>
            total + item.text.replaceAll(RegExp(r'\s+'), '').length);
  }

  String? ownerKeyForRegion(
      OcrInspection inspection, String customer, OcrVisualRegion region) {
    final label = _ownerLabelForRegion(inspection, customer, region);
    if (label == null) return null;
    return '${label.text}\u001f${label.x.toStringAsFixed(4)}\u001f'
        '${label.y.toStringAsFixed(4)}';
  }

  DateTime? ownerSentAtForRegion(
      OcrInspection inspection, String customer, OcrVisualRegion region) {
    final label = _ownerLabelForRegion(inspection, customer, region);
    if (label == null) return null;
    return _sentAtForLabel(inspection, label);
  }

  DateTime? _sentAtForLabel(OcrInspection inspection, OcrObservation label) {
    final timestamp = _timestamp.firstMatch(label.text)?.group(0) ??
        inspection.observations
            .where((item) =>
                (item.y - label.y).abs() < .018 &&
                item.x > label.x &&
                _timestamp.hasMatch(item.text))
            .map((item) => _timestamp.firstMatch(item.text)!.group(0))
            .firstOrNull;
    return _parseTimestamp(timestamp, inspection.capturedAt);
  }

  OcrObservation? _ownerLabelForRegion(
      OcrInspection inspection, String customer, OcrVisualRegion region) {
    final left = inspection.chatLeft ?? .15;
    final right = inspection.chatRight ?? .68;
    final labels = inspection.observations
        .where((item) =>
            item.x + item.width / 2 >= left &&
            item.x + item.width / 2 < right &&
            (_isCustomer(item.text, customer) || _isSeller(item.text)))
        .toList()
      ..sort((a, b) => a.y.compareTo(b.y));
    for (var index = labels.length - 1; index >= 0; index--) {
      final label = labels[index];
      if (!_isCustomer(label.text, customer)) continue;
      final nextY = index + 1 < labels.length ? labels[index + 1].y : .91;
      if (label.y <= region.y + .010 && region.y < nextY) return label;
    }
    return null;
  }

  DateTime? _parseTimestamp(String? value, DateTime capturedAt) {
    if (value == null) return null;
    final numbers = RegExp(r'\d+')
        .allMatches(value)
        .map((match) => int.parse(match.group(0)!))
        .toList(growable: false);
    if (numbers.length < 2) return null;
    const jdOffset = Duration(hours: 8);
    final capturedUtc = capturedAt.toUtc();
    final jdCapture = capturedUtc.add(jdOffset);
    var result = DateTime.utc(
      jdCapture.year,
      jdCapture.month,
      jdCapture.day,
      numbers[0],
      numbers[1],
      numbers.length >= 3 ? numbers[2] : 0,
    ).subtract(jdOffset);
    if (result.difference(capturedUtc) > const Duration(minutes: 1)) {
      result = result.subtract(const Duration(days: 1));
    }
    return result;
  }

  bool _isCustomer(String value, String customer) {
    final raw = value.toLowerCase().trim();
    final expected = customer.toLowerCase();
    if (raw == expected) return true;
    if (raw.startsWith(expected)) {
      final suffix = raw.substring(expected.length).trim();
      if (suffix.isEmpty || RegExp(r'\d{1,2}:\d{2}').hasMatch(suffix)) {
        return true;
      }
    }
    final prefix = raw
        .replaceAll('...', '')
        .replaceAll('…', '')
        .replaceAll(RegExp(r'\s+'), '');
    return prefix.length >= 6 && expected.startsWith(prefix);
  }

  bool _isSeller(String value) {
    final text = value.trim();
    return (text.contains('旗舰店') &&
            (text.contains(':') || text.contains('：'))) ||
        RegExp(r'格志打印机[\u3400-\u9fffA-Za-z0-9_-]{1,12}').hasMatch(text);
  }

  static final _timestamp = RegExp(
      r'(?:20\d{2}[-/.]\d{1,2}[-/.]\d{1,2}\s+)?\d{1,2}:\d{2}(?::\d{2})?');
}
