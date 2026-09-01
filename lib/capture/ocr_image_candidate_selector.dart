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
  }) {
    final senderLabels = inspection.observations
        .where(
            (item) => _isCustomer(item.text, customer) || _isSeller(item.text))
        .toList()
      ..sort((left, right) => left.y.compareTo(right.y));
    final selected = <OcrVisualRegion>[];
    for (var index = 0; index < senderLabels.length; index++) {
      final label = senderLabels[index];
      if (!_isCustomer(label.text, customer)) continue;
      final nextSenderY =
          index + 1 < senderLabels.length ? senderLabels[index + 1].y : .90;
      final matches = inspection.visualRegions
          .where(_validGeometry)
          .where((region) => !_isTextDense(region, inspection.observations))
          .where((region) =>
              label.y <= region.y &&
              region.y - label.y <= .13 &&
              region.y + region.height < nextSenderY - .002)
          .toList()
        ..sort((left, right) =>
            (right.width * right.height).compareTo(left.width * left.height));
      if (matches.isNotEmpty) selected.add(matches.first);
    }

    if (selected.isEmpty && allowUnlabeledLatestImage && senderLabels.isEmpty) {
      final unlabeled = inspection.visualRegions
          .where(_validGeometry)
          .where((region) => !_isTextDense(region, inspection.observations))
          .where((region) =>
              region.x >= .15 &&
              region.x < .50 &&
              region.x + region.width <= .64 &&
              region.width >= .12 &&
              region.width <= .38 &&
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

  bool _validGeometry(OcrVisualRegion region) =>
      region.x >= .15 &&
      region.x + region.width <= .68 &&
      region.y >= .14 &&
      region.y + region.height <= .90 &&
      region.width >= .035 &&
      region.height >= .065 &&
      region.width <= .48 &&
      region.height <= .76;

  bool _isTextDense(OcrVisualRegion region, List<OcrObservation> observations) {
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
}
