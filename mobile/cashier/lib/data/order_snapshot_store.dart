import 'package:flutter/foundation.dart';

import '../domain/models.dart';

class DetailSnapshot {
  const DetailSnapshot({
    this.order,
    this.checkedAt,
    this.error,
    this.loading = false,
  });
  final OrderRecord? order;
  final DateTime? checkedAt;
  final String? error;
  final bool loading;
  bool get usable =>
      order != null && checkedAt != null && error == null && !loading;
}

class OrderSnapshotStore {
  final _queries = <String, ({String revision, List<OrderRecord> orders})>{};
  final details = <String, ValueNotifier<DetailSnapshot>>{};
  ({String revision, List<OrderRecord> orders})? query(String key) =>
      _queries[key];
  List<OrderRecord> save(String key, String revision, List<OrderRecord> rows) {
    final old = {
      for (final row in _queries[key]?.orders ?? <OrderRecord>[]) row.id: row,
    };
    final stable = List<OrderRecord>.unmodifiable(
      rows.map(
        (row) =>
            (old[row.id]?.version ?? 0) >= row.version ? old[row.id]! : row,
      ),
    );
    _queries.remove(key);
    _queries[key] = (revision: revision, orders: stable);
    while (_queries.length > 6) {
      _queries.remove(_queries.keys.first);
    }
    return stable;
  }

  void invalidate() => _queries.clear();
  void clear() {
    _queries.clear();
    for (final detail in details.values) {
      detail.value = const DetailSnapshot(error: 'Sesi berakhir');
    }
  }

  void dispose() {
    for (final detail in details.values) {
      detail.dispose();
    }
    details.clear();
  }
}
