import 'catalog.dart';
import 'order_draft.dart';

String? validateDraftLine(OrderDraftLine line, CatalogProduct? product) {
  if (product == null || !product.available) {
    return 'Produk tidak tersedia. Hapus atau ganti produk.';
  }
  if (line.quantity < 1 || line.quantity > 50) return 'Jumlah harus 1–50.';
  if (line.notes.runes.length > 200) return 'Catatan maksimal 200 karakter.';
  if (line.variantIds.length > 20 || line.addonIds.length > 20) {
    return 'Maksimal 20 varian dan 20 tambahan.';
  }
  if (line.addonIds.toSet().length != line.addonIds.length) {
    return 'Tambahan tidak boleh ganda.';
  }
  final groups = <String>{};
  for (final id in line.variantIds) {
    final variant = product.variants
        .where((v) => v.id == id && v.available)
        .firstOrNull;
    if (variant == null) return 'Ada varian tidak tersedia.';
    if (!groups.add(variant.groupName)) {
      return 'Pilih satu varian setiap kelompok.';
    }
  }
  for (final group
      in product.variants
          .where((v) => v.available)
          .map((v) => v.groupName)
          .toSet()) {
    if (!groups.contains(group)) {
      return 'Pilih satu varian pada kelompok $group.';
    }
  }
  if (line.addonIds.any(
    (id) => !product.addons.any((a) => a.id == id && a.available),
  )) {
    return 'Ada tambahan tidak tersedia.';
  }
  return null;
}

String? validateDraft(
  List<OrderDraftLine> items,
  Catalog catalog, {
  String? customerName,
  bool reorder = false,
}) {
  if (reorder && !catalog.ordersEnabled) {
    return 'Restoran sedang menutup pesanan baru.';
  }
  if (items.isEmpty || items.length > 50) {
    return 'Pesanan harus berisi 1–50 baris.';
  }
  if (customerName != null &&
      (customerName.runes.length > 100 ||
          (catalog.requireCustomerName && customerName.trim().isEmpty))) {
    return 'Isi nama pelanggan, maksimal 100 karakter.';
  }
  for (var index = 0; index < items.length; index++) {
    final error = validateDraftLine(
      items[index],
      catalog.byId[items[index].productId],
    );
    if (error != null) return 'Item ${index + 1}: $error';
  }
  return null;
}
