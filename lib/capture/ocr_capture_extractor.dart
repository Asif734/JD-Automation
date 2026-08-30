import 'dart:convert';

import 'package:crypto/crypto.dart';

import '../domain/capture_models.dart';
import '../platform/macos_capture_adapter.dart';

/// Converts one OCR diagnostic scan of an *open* Qianniu conversation into a
/// conservative capture candidate. All visible incoming and seller-authored
/// bubbles with a clear sender/body relationship are returned; durable IDs
/// remove older duplicates.
class OcrCaptureExtractor {
  const OcrCaptureExtractor();

  CapturedConversation? extract(OcrInspection inspection) =>
      analyze(inspection).capture;

  OcrExtractionAttempt analyze(OcrInspection inspection) {
    final observations = inspection.observations
        .where((item) => item.confidence >= 0.45 && item.text.trim().isNotEmpty)
        .toList(growable: false);
    final suppliedCustomer = inspection.activeCustomerId?.trim();
    final customerId = suppliedCustomer != null && suppliedCustomer.isNotEmpty
        ? suppliedCustomer
        : _customerId(observations);
    if (customerId == null) {
      return const OcrExtractionAttempt(
          reason: 'No unambiguous full customer ID was found.');
    }

    final messageLabels = observations
        .where((item) =>
            (_sameIdentity(item.text, customerId) ||
                _isSellerIdentity(item.text)) &&
            item.x >= 0.20 &&
            item.x < 0.64 &&
            item.y >= 0.18 &&
            item.y < 0.82)
        .map((item) => _MessageLabel(
              observation: item,
              direction: _sameIdentity(item.text, customerId)
                  ? 'incoming'
                  : 'outgoing',
            ))
        .toList()
      ..sort(
          (left, right) => left.observation.y.compareTo(right.observation.y));
    if (messageLabels.isEmpty) {
      return OcrExtractionAttempt(
          reason: 'Customer $customerId was identified, but no matching '
              'message sender label was visible in the chat area.');
    }
    final incomingLabels = messageLabels
        .where((label) => label.direction == 'incoming')
        .toList(growable: false);
    final sender = incomingLabels.isEmpty
        ? messageLabels.last.observation
        : incomingLabels.last.observation;
    final fallbackCopyTarget = OcrCopyTarget(
      x: (sender.x + 0.045).clamp(0.20, 0.63),
      y: (sender.y + 0.040).clamp(0.18, 0.81),
    );

    final capturedMessages = <CapturedMessage>[];
    OcrObservation? latestBodyObservation;
    for (var index = 0; index < messageLabels.length; index++) {
      final label = messageLabels[index];
      final currentSender = label.observation;
      final bottom = index + 1 < messageLabels.length
          ? messageLabels[index + 1].observation.y
          // JD can leave a larger vertical gap before the newest bottom
          // bubble. The next sender safely bounds older messages; the final
          // sender may use the remaining verified chat area above composer.
          : 0.82;
      final bodies = observations.where((item) {
        final text = item.text.trim();
        if (item.y <= currentSender.y + 0.006 || item.y >= bottom) {
          return false;
        }
        if (item.x < 0.20 || item.x >= 0.64) return false;
        if ((item.x - currentSender.x).abs() > 0.10) return false;
        return !_isMetadata(text, customerId);
      }).toList()
        ..sort((left, right) {
          final byY = left.y.compareTo(right.y);
          return byY != 0 ? byY : left.x.compareTo(right.x);
        });
      if (bodies.isEmpty) continue;
      final firstY = bodies.first.y;
      final body = bodies
          .where((item) => (item.y - firstY).abs() < 0.018)
          .map((item) => item.text.trim())
          .join(' ')
          .trim();
      if (body.isEmpty) continue;
      final timestamp = _timestamp.firstMatch(currentSender.text)?.group(0) ??
          observations
              .where((item) =>
                  (item.y - currentSender.y).abs() < 0.018 &&
                  item.x > currentSender.x &&
                  _timestamp.hasMatch(item.text))
              .map((item) => item.text.trim())
              .firstOrNull;
      final identity = '$customerId\u001f${label.direction}\u001f'
          '${_fingerprintTimestamp(timestamp)}\u001f${_fingerprintText(body)}';
      capturedMessages.add(CapturedMessage(
        stableId: 'ocr:${sha256.convert(utf8.encode(identity))}',
        direction: label.direction,
        body: body,
        sender: label.direction == 'incoming'
            ? customerId
            : currentSender.text.trim(),
        axPath: 'ocr:active-conversation',
      ));
      if (label.direction == 'incoming') latestBodyObservation = bodies.first;
    }
    if (capturedMessages.isEmpty) {
      return OcrExtractionAttempt(
          reason: 'Customer $customerId was identified, but no message '
              'body was recognized beneath the visible sender labels.',
          customerId: customerId,
          copyTarget: fallbackCopyTarget);
    }
    final latestBody = latestBodyObservation;
    final latestIncomingSender =
        incomingLabels.isEmpty ? null : incomingLabels.last.observation;
    // An image-only customer turn has a sender label but no OCR body. Aim the
    // clipboard classification just below that newest label instead of at an
    // older text body, so JD can confirm that the new bubble is an image.
    final latestIncomingHasNoBody = latestIncomingSender != null &&
        (latestBody == null ||
            latestIncomingSender.y > latestBody.y + latestBody.height + 0.006);
    return OcrExtractionAttempt(
      reason:
          'Extracted ${capturedMessages.length} visible message(s) for $customerId.',
      customerId: customerId,
      copyTarget: latestIncomingHasNoBody
          ? fallbackCopyTarget
          : latestBody == null
              ? null
              : OcrCopyTarget(
                  x: (latestBody.x + latestBody.width / 2).clamp(0.20, 0.63),
                  y: (latestBody.y + latestBody.height / 2).clamp(0.18, 0.81),
                ),
      capture: CapturedConversation(
        stableKey: 'customer:${sha256.convert(utf8.encode(customerId))}',
        customerName: customerId,
        customerExternalId: customerId,
        capturedAt: inspection.capturedAt,
        messages: capturedMessages,
      ),
    );
  }

  String? _customerId(List<OcrObservation> observations) {
    final candidates = <String, double>{};
    for (final item in observations) {
      final text = item.text.trim();
      if (!_accountId.hasMatch(text) || text.contains('...')) continue;
      if (_ignoredIdentifiers.contains(text.toLowerCase())) continue;
      var score = candidates[text] ?? 0;
      score +=
          10; // Repetition across the header, messages and profile is strong.
      if (item.x >= 0.58 && item.x < 0.85 && item.y >= 0.14 && item.y < 0.36) {
        score += 30; // Full identity in the customer-information header.
      }
      if (item.x >= 0.15 && item.x < 0.58 && item.y >= 0.18 && item.y < 0.82) {
        score += 8; // Sender label in the message history.
      }
      candidates[text] = score;
    }
    if (candidates.isEmpty) return null;
    final ranked = candidates.entries.toList()
      ..sort((left, right) => right.value.compareTo(left.value));
    // Refuse a tie: saving a message under the wrong customer is worse than
    // requiring another diagnostic scan.
    if (ranked.length > 1 && ranked[0].value == ranked[1].value) return null;
    return ranked.first.key;
  }

  bool _sameIdentity(String value, String customerId) {
    final full = customerId.trim().toLowerCase();
    final raw = value.trim().toLowerCase();
    if (raw == full) return true;
    // Vision sometimes merges the sender and timestamp into one observation,
    // for example "stoneshishininger 2026-08-26 11:03:13".
    if (raw.startsWith(full)) {
      final suffix = raw.substring(full.length).trim();
      if (suffix.isEmpty || _timestamp.hasMatch(suffix)) return true;
    }
    final visiblePrefix = raw
        .replaceAll('...', '')
        .replaceAll('…', '')
        .replaceAll(RegExp(r'\s+'), '');
    // Qianniu truncates sender labels. A long visible prefix is accepted only
    // after AX has supplied the exact active customer identity.
    return visiblePrefix.length >= 6 && full.startsWith(visiblePrefix);
  }

  bool _isMetadata(String value, String customerId) {
    final lower = value.toLowerCase();
    return _sameIdentity(value, customerId) ||
        _timestamp.hasMatch(value) ||
        _sidebarRecency.hasMatch(value.trim()) ||
        lower.contains('已读') ||
        lower.contains('未读') ||
        lower.contains('新消息') ||
        lower.contains('加普威旗舰店') ||
        lower == '客服' ||
        lower == '营销';
  }

  bool _isSellerIdentity(String value) {
    final text = value.trim();
    if (text.contains('旗舰店') && (text.contains(':') || text.contains('：'))) {
      return true;
    }
    // Current JD builds display the signed-in support identity as names such
    // as "格志打印机小甘", often with the timestamp merged into the same Vision
    // observation. These are seller labels, not customer message bodies.
    final withoutTimestamp = text.replaceAll(_timestamp, '').trim();
    return RegExp(r'^格志打印机[\u3400-\u9fffA-Za-z0-9_-]{1,12}$')
        .hasMatch(withoutTimestamp);
  }

  String _fingerprintText(String value) => value
      .toLowerCase()
      .replaceAll(RegExp(r'\s+'), '')
      .replaceAll(RegExp(r'''[.,!?;:'"`~，。！？；：“”‘’（）()\[\]{}、]'''), '');

  String _fingerprintTimestamp(String? value) {
    if (value == null) return '-';
    return RegExp(r'\d+')
        .allMatches(value)
        .map((match) => int.parse(match.group(0)!))
        .join(':');
  }

  static final _accountId = RegExp(r'^[A-Za-z][A-Za-z0-9_.-]{3,63}$');
  static final _timestamp = RegExp(
      r'(?:20\d{2}[-/.]\d{1,2}[-/.]\d{1,2}\s+)?\d{1,2}:\d{2}(?::\d{2})?');
  static final _sidebarRecency = RegExp(
      r'^\d+\s*(?:秒|分钟|分|小时|天|second|seconds|min|mins)$',
      caseSensitive: false);
  static const _ignoredIdentifiers = {
    'hello',
    'customer',
    'service',
    'mac',
    'wifi',
  };
}

class _MessageLabel {
  const _MessageLabel({required this.observation, required this.direction});

  final OcrObservation observation;
  final String direction;
}

class OcrExtractionAttempt {
  const OcrExtractionAttempt({
    required this.reason,
    this.capture,
    this.customerId,
    this.copyTarget,
  });

  final String reason;
  final CapturedConversation? capture;
  final String? customerId;
  final OcrCopyTarget? copyTarget;
}

class OcrCopyTarget {
  const OcrCopyTarget({required this.x, required this.y});
  final double x;
  final double y;
}

extension<T> on Iterable<T> {
  T? get firstOrNull {
    final iterator = this.iterator;
    return iterator.moveNext() ? iterator.current : null;
  }
}
