import 'models.dart';

/// Arrival detection for servers that expose only a revision, not an event feed.
/// Always observe the newest, unfiltered active page, never the visible filter.
class OrderArrivals {
  final _seen = <String>{};
  DateTime? _newestCreatedAt;
  bool _initialized = false;

  Set<String> observe(List<OrderRecord> newest) {
    final fresh = <String>{};
    final cutoff = _newestCreatedAt;
    for (final order in newest) {
      final created = order.createdAt;
      final alreadySeen = _seen.contains(order.id);
      // When rows leave a full page, older unseen rows can enter it. Their
      // creation time keeps them from being mistaken for a new checkout.
      if (_initialized &&
          !alreadySeen &&
          (cutoff == null || (created != null && !created.isBefore(cutoff)))) {
        fresh.add(order.id);
      }
      _seen.remove(order.id);
      _seen.add(order.id);
      if (created != null &&
          (_newestCreatedAt == null || created.isAfter(_newestCreatedAt!))) {
        _newestCreatedAt = created;
      }
    }
    while (_seen.length > 1000) {
      _seen.remove(_seen.first);
    }
    _initialized = true;
    return fresh;
  }

  void reset() {
    _seen.clear();
    _newestCreatedAt = null;
    _initialized = false;
  }
}
