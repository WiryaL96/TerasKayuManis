class OrderSync {
  const OrderSync(
    this.revision,
    this.newOrders, {
    this.overflow = false,
    this.hasNewOrderFeed = true,
  });
  factory OrderSync.fromJson(Map<String, dynamic> json) {
    final revision = json['revision'];
    if (revision is! String || revision.isEmpty || revision.length > 100) {
      throw const FormatException('Invalid sync revision');
    }
    // Older servers support revision-based queue polling but no arrival feed.
    // Keep that capability explicit: an absent feed is not an empty snapshot.
    if (!json.containsKey('new_orders')) {
      return OrderSync(revision, const {}, hasNewOrderFeed: false);
    }
    final rows = json['new_orders'];
    if (rows is! List ||
        rows.length > 1000 ||
        rows.any((id) => id is! String || id.length > 64)) {
      throw const FormatException('Invalid new order feed');
    }
    return OrderSync(
      revision,
      Set.unmodifiable(rows.cast<String>()),
      overflow: json['overflow'] == true,
    );
  }
  final String revision;
  final Set<String> newOrders;
  final bool overflow;
  final bool hasNewOrderFeed;
}

class WatchLease {
  const WatchLease(this.token, this.expiresAt);
  factory WatchLease.fromJson(Map<String, dynamic> json) {
    final token = json['token'] as String;
    if (!RegExp(r'^[a-f0-9]{64}$').hasMatch(token)) {
      throw const FormatException('Invalid watch');
    }
    return WatchLease(token, DateTime.parse(json['expires_at'] as String));
  }
  final String token;
  final DateTime expiresAt;
}
