import 'dart:convert';

class PosAttempt {
  const PosAttempt(
    this.orderId,
    this.version,
    this.reference, {
    this.orderNumber,
  });
  final String orderId, reference;
  final String? orderNumber;
  final int version;
  String encode() => jsonEncode({
    'id': orderId,
    'version': version,
    'reference': reference,
    if (orderNumber != null) 'order_number': orderNumber,
  });
  factory PosAttempt.decode(String raw) {
    final data = jsonDecode(raw) as Map<String, dynamic>;
    final attempt = PosAttempt(
      data['id'] as String,
      data['version'] as int,
      data['reference'] as String,
      orderNumber: data['order_number'] as String?,
    );
    if (!RegExp(r'^[a-f0-9-]{36}$').hasMatch(attempt.orderId) ||
        attempt.version < 1 ||
        attempt.reference.runes.length > 80 ||
        (attempt.orderNumber != null &&
            (attempt.orderNumber!.trim().isEmpty ||
                attempt.orderNumber!.runes.length > 80 ||
                attempt.orderNumber!.contains(RegExp(r'[\x00-\x1f\x7f]'))))) {
      throw const FormatException('Invalid stored POS attempt');
    }
    return attempt;
  }
}
