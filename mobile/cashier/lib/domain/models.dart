export 'catalog.dart';
export 'order_draft.dart';
import 'order_draft.dart';

class PosHandoff {
  PosHandoff.fromJson(Map<String, dynamic> json)
    : cashierId = json['cashier_id'] as String,
      cashierName = json['cashier_name'] as String? ?? '',
      claimedAt = DateTime.parse(json['claimed_at'] as String),
      forwardedAt = json['forwarded_at'] == null
          ? null
          : DateTime.parse(json['forwarded_at'] as String),
      posReference = json['pos_reference'] as String? ?? '';
  final String cashierId, cashierName, posReference;
  final DateTime claimedAt;
  final DateTime? forwardedAt;
}

class StaffProfile {
  const StaffProfile({
    required this.id,
    required this.fullName,
    required this.role,
  });
  StaffProfile.fromJson(Map<String, dynamic> json)
    : id = json['id'] as String,
      fullName = json['full_name'] as String? ?? '',
      role = json['role'] as String? ?? '';
  final String id, fullName, role;
  bool get hasName => fullName.trim().isNotEmpty;
  bool get isAdmin => role == 'admin' || role == 'superadmin';
}

class CashierRosterEntry {
  const CashierRosterEntry({required this.id, required this.name, this.photo});
  CashierRosterEntry.fromJson(Map<String, dynamic> json)
    : id = json['id'] as String,
      name = json['name'] as String? ?? '',
      photo = json['photo'] as String?;
  final String id, name;
  final String? photo;
}

class OrderRecord {
  OrderRecord.fromJson(Map<String, dynamic> json)
    : id = json['id'] as String,
      orderNumber = json['order_number'].toString(),
      customerName = json['customer_name'] as String? ?? '',
      status = json['status'] as String,
      paymentStatus = json['payment_status'] as String,
      version = json['version'] as int,
      reviewedVersion = json['reviewed_version'] as int?,
      _summaryItemCount = (json['item_count'] as num?)?.toInt(),
      total = json['total'] as int,
      expiresAt = DateTime.parse(json['expires_at'] as String),
      createdAt = json['created_at'] == null
          ? null
          : DateTime.parse(json['created_at'] as String),
      posHandoff = json['pos_handoff'] is Map
          ? PosHandoff.fromJson(
              Map<String, dynamic>.from(json['pos_handoff'] as Map),
            )
          : null,
      legacyCashierName = json['cashier'] is Map
          ? (json['cashier'] as Map)['full_name'] as String?
          : null,
      items = List.unmodifiable(
        (json['order_items'] as List? ?? []).map(
          (v) => OrderLine.fromJson(Map<String, dynamic>.from(v as Map)),
        ),
      );
  final String id, orderNumber, customerName, status, paymentStatus;
  final int version, total;
  final int? reviewedVersion;
  final int? _summaryItemCount;
  final DateTime expiresAt;
  final DateTime? createdAt;
  final PosHandoff? posHandoff;
  final String? legacyCashierName;
  final List<OrderLine> items;
  int get itemCount =>
      _summaryItemCount ??
      items.fold<int>(0, (sum, item) => sum + item.quantity);
  bool canReview(DateTime now) =>
      status == 'pending' &&
      paymentStatus == 'unpaid' &&
      now.isBefore(expiresAt);
  bool get isReviewed => reviewedVersion == version;
  bool canClaim(DateTime now) => canReview(now) && reviewedVersion == version;
  bool get isPosInput => status == 'pos_input';
  bool get isForwarded => status == 'forwarded';
  bool isStalePosClaim(DateTime now) =>
      isPosInput &&
      posHandoff != null &&
      now.difference(posHandoff!.claimedAt) > const Duration(minutes: 10);
  Duration? get pausedRemaining => isPosInput && posHandoff != null
      ? expiresAt.difference(posHandoff!.claimedAt)
      : null;
  bool canForwardFor(String? staffId) =>
      isPosInput &&
      paymentStatus == 'unpaid' &&
      posHandoff != null &&
      staffId != null &&
      posHandoff!.cashierId == staffId;
  bool canTakeOverFor({required String? staffId, required bool isAdmin}) =>
      isPosInput &&
      paymentStatus == 'unpaid' &&
      isAdmin &&
      staffId != null &&
      posHandoff != null &&
      posHandoff!.cashierId != staffId;
  bool get isExpired =>
      status == 'expired' ||
      (status == 'pending' &&
          paymentStatus == 'unpaid' &&
          !DateTime.now().isBefore(expiresAt));
}

class OrderLine {
  OrderLine.fromJson(Map<String, dynamic> json)
    : productId = json['product_id'] as String? ?? '',
      name = json['product_name'] as String? ?? '',
      quantity = json['quantity'] as int,
      unitPrice = json['unit_price'] as int,
      subtotal = json['subtotal'] as int,
      variantIds = List.unmodifiable(
        (json['variant_ids'] as List? ?? []).cast<String>(),
      ),
      addonIds = List.unmodifiable(
        (json['addon_ids'] as List? ?? []).cast<String>(),
      ),
      variantName = json['variant_name'] as String? ?? '',
      addonNames = List.unmodifiable(
        (json['order_item_addons'] as List? ?? [])
            .map((v) => Map<String, dynamic>.from(v as Map))
            .map((v) => v['addon_name'] as String? ?? '')
            .where((name) => name.isNotEmpty),
      ),
      notes = json['notes'] as String? ?? '';
  final String productId, name, notes, variantName;
  final int quantity, unitPrice, subtotal;
  final List<String> variantIds, addonIds, addonNames;
  OrderDraftLine toDraft() => OrderDraftLine(
    productId: productId,
    quantity: quantity,
    variantIds: variantIds,
    addonIds: addonIds,
    notes: notes,
  );
}
