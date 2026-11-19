import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/app_theme.dart';
import '../../core/visible_clock.dart';
import '../../domain/models.dart';
import 'cashier_controller.dart';
import 'order_detail_screen.dart';
import 'ui_common.dart';
import 'diagnostics_screen.dart';

class CashierScreen extends StatefulWidget {
  const CashierScreen({
    super.key,
    required this.controller,
    required this.sound,
    required this.onSoundChanged,
    this.demo = false,
    this.watchStatus,
    this.onEnableNotifications,
  });
  final CashierController controller;
  final bool sound;
  final ValueChanged<bool> onSoundChanged;
  final bool demo;
  final ValueListenable<String>? watchStatus;
  final VoidCallback? onEnableNotifications;
  @override
  State<CashierScreen> createState() => _CashierScreenState();
}

class _CashierScreenState extends State<CashierScreen> {
  String? _error;
  bool _working = false;
  bool _opening = false;
  final _search = TextEditingController();

  /// Ticks once per second. Only widgets listening to it rebuild, so the order
  /// list never rebuilds just to refresh a countdown.
  final _now = VisibleClock();
  Timer? _searchTimer;

  @override
  void initState() {
    super.initState();
    _search.text = widget.controller.search;
  }

  @override
  void dispose() {
    _now.dispose();
    _searchTimer?.cancel();
    _search.dispose();
    super.dispose();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _now.attach(context);
  }

  Future<void> _run(Future<void> Function() action) async {
    if (_working || widget.controller.busy) return;
    setState(() {
      _working = true;
      _error = null;
    });
    try {
      await action();
    } catch (_) {
      if (mounted) {
        setState(
          () => _error = 'Permintaan gagal. Periksa koneksi lalu coba lagi.',
        );
      }
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  void _onSearchChanged(String value) {
    _searchTimer?.cancel();
    _searchTimer = Timer(const Duration(milliseconds: 350), () {
      if (mounted) unawaited(widget.controller.setSearch(value));
    });
  }

  Future<void> _clearFilters() async {
    _searchTimer?.cancel();
    _search.text = '';
    await _run(widget.controller.clearFilters);
  }

  Future<void> _pickDay() async {
    final c = widget.controller;
    final now = DateTime.now().toUtc().add(const Duration(hours: 7));
    final picked = await showDatePicker(
      context: context,
      initialDate: c.selectedDay ?? now,
      firstDate: DateTime(2024),
      lastDate: now,
      helpText: 'Filter Tanggal',
      cancelText: 'Batal',
      confirmText: 'Pilih',
    );
    if (picked != null) await _run(() => c.setSelectedDay(picked));
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.controller,
    builder: (context, _) => _build(context),
  );
  Widget _build(BuildContext context) {
    final c = widget.controller;
    final disabled = c.busy || _working;
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            Expanded(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final available = AppBreakpoints.contentMaxWidth(
                    constraints.maxWidth,
                  );
                  final columns = AppBreakpoints.gridColumns(
                    constraints.maxWidth,
                  );
                  final initialLoad = c.loading && c.orders.isEmpty;
                  final showPagination = c.orders.isNotEmpty || initialLoad;
                  final rows = columns <= 1 || c.orders.isEmpty
                      ? c.orders.length
                      : (c.orders.length + columns - 1) ~/ columns;
                  return Center(
                    child: ConstrainedBox(
                      constraints: BoxConstraints(maxWidth: available),
                      child: RefreshIndicator(
                        onRefresh: () => c.refresh(force: true),
                        // Lazy list: only visible order cards are built. The
                        // previous Column/ListView(children:) built every card
                        // in the queue on each frame, which made scrolling and
                        // typing in the search field drop frames.
                        child: ListView.builder(
                          key: const ValueKey('order-list'),
                          padding: const EdgeInsets.fromLTRB(
                            AppSpacing.lg,
                            AppSpacing.lg,
                            AppSpacing.lg,
                            AppSpacing.xxl,
                          ),
                          physics: const AlwaysScrollableScrollPhysics(),
                          itemCount: 1 + rows + (showPagination ? 1 : 0),
                          itemBuilder: (context, index) {
                            if (index == 0) {
                              return Column(
                                children: [
                                  _buildHeader(context, c, disabled),
                                  _buildTabs(c, disabled),
                                  _buildFilters(c, disabled),
                                  SizedBox(
                                    height: 3,
                                    child: c.loading && c.orders.isEmpty
                                        ? const LinearProgressIndicator()
                                        : null,
                                  ),
                                  ValueListenableBuilder<DateTime?>(
                                    valueListenable: c.lastSync,
                                    builder: (_, value, _) => Align(
                                      alignment: Alignment.centerLeft,
                                      child: Text(
                                        value == null
                                            ? 'Belum tersinkron'
                                            : 'Sinkron terakhir ${formatTime(value.toUtc().add(const Duration(hours: 7)))} WIB',
                                        style: const TextStyle(fontSize: 12),
                                      ),
                                    ),
                                  ),
                                  _buildListHeader(c),
                                ],
                              );
                            }
                            if (index <= rows) {
                              final rowIndex = index - 1;
                              if (columns <= 1) {
                                return _buildCard(c, c.orders[rowIndex]);
                              }
                              final start = rowIndex * columns;
                              final row = c.orders.skip(start).take(columns);
                              return Padding(
                                padding: const EdgeInsets.only(
                                  bottom: AppSpacing.md,
                                ),
                                child: Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    for (final order in row)
                                      Expanded(
                                        child: Padding(
                                          padding: EdgeInsets.only(
                                            right: order == row.last
                                                ? 0
                                                : AppSpacing.md,
                                          ),
                                          child: _buildCard(c, order),
                                        ),
                                      ),
                                    for (var i = row.length; i < columns; i++)
                                      const Expanded(child: SizedBox()),
                                  ],
                                ),
                              );
                            }
                            return _buildPagination(c, disabled);
                          },
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _open(CashierController c, OrderRecord order) {
    if (_opening) return;
    _opening = true;
    Navigator.of(context)
        .push(
          MaterialPageRoute<void>(
            builder: (_) => OrderDetailScreen(controller: c, order: order),
          ),
        )
        .whenComplete(() => _opening = false);
  }

  Widget _buildListHeader(CashierController c) {
    final initialLoad = c.loading && c.orders.isEmpty;
    final headerError = _error ?? c.error;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        PendingRecovery(controller: c),
        if (c.staff != null && !c.staff!.hasName)
          InfoBanner.warning(
            'Nama staf pada profil kosong. Lengkapi profil sebelum menangani '
            'pesanan.',
            title: 'Profil belum lengkap',
          ),
        if (headerError != null)
          ErrorNotice(
            message: headerError,
            onClose: () {
              setState(() => _error = null);
              c.clearError();
            },
          ),
        if (initialLoad)
          const LoadingView(message: 'Memuat pesanan...')
        else if (c.orders.isEmpty)
          _emptyState(c),
      ],
    );
  }

  Widget _buildCard(CashierController c, OrderRecord order) => RepaintBoundary(
    child: _OrderCard(
      order: order,
      enabled: !c.busy,
      onTap: c.busy ? null : () => _open(c, order),
      now: _now,
    ),
  );

  Widget _buildHeader(
    BuildContext context,
    CashierController c,
    bool disabled,
  ) {
    final profile = c.staff;
    final staffLine = profile == null
        ? 'Kasir • Input pesanan ke POS'
        : profile.hasName
        ? '${profile.fullName} • ${profile.role}'
        : 'Nama staf belum diisi • ${profile.role}';
    return Container(
      decoration: const BoxDecoration(
        color: AppColors.card,
        border: Border(bottom: BorderSide(color: AppColors.border)),
      ),
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        AppSpacing.sm,
        AppSpacing.sm,
        AppSpacing.sm,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (widget.demo)
            const Padding(
              padding: EdgeInsets.only(bottom: AppSpacing.sm),
              child: InfoBanner(
                icon: Icons.science_outlined,
                tone: BadgeStyle(
                  '',
                  AppColors.warning,
                  AppColors.warningSurface,
                ),
                message:
                    'DEMO • Data lokal — perubahan tidak disimpan ke server.',
              ),
            ),
          Row(
            children: [
              const RestaurantLogo(size: 36),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'TerasKayuManis',
                      style: TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        height: 1.25,
                      ),
                    ),
                    Text(
                      staffLine,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                key: const ValueKey('refresh'),
                tooltip: 'Muat ulang pesanan',
                onPressed: disabled
                    ? null
                    : () => _run(() => c.refresh(force: true)),
                icon: const Icon(Icons.refresh),
              ),
              IconButton(
                tooltip: 'Diagnostik',
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => const DiagnosticsScreen(),
                  ),
                ),
                icon: const Icon(Icons.info_outline),
              ),
              IconButton(
                tooltip: 'Keluar',
                onPressed: disabled
                    ? null
                    : () async {
                        if (await confirmAction(
                          context,
                          title: 'Keluar dari kasir?',
                          message:
                              'Percobaan pesanan ulang yang belum pasti tetap '
                              'tersimpan untuk akun ini.',
                          action: 'Keluar',
                        )) {
                          await _run(c.logout);
                        }
                      },
                icon: const Icon(Icons.logout),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          Wrap(
            spacing: AppSpacing.md,
            runSpacing: AppSpacing.xs,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              ConnectionStatusIndicator(status: c.realtimeStatus),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    widget.sound ? Icons.volume_up : Icons.volume_off,
                    size: 16,
                    color: AppColors.textSecondary,
                  ),
                  const SizedBox(width: 6),
                  Flexible(
                    child: Text(
                      'Suara pesanan baru',
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 12,
                      ),
                    ),
                  ),
                  SizedBox(
                    height: 28,
                    child: Switch(
                      key: const ValueKey('sound-toggle'),
                      value: widget.sound,
                      onChanged: disabled ? null : widget.onSoundChanged,
                    ),
                  ),
                ],
              ),
            ],
          ),
          if (c.latestSync?.hasNewOrderFeed == false)
            const Text(
              'Suara pesanan baru tersedia saat aplikasi terbuka. Nyalakan suara untuk mencoba bunyi; periksa volume notifikasi perangkat. Pemantauan saat aplikasi ditutup belum didukung server.',
              style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
            )
          else
            const Text(
              'Suara mengikuti pengaturan perangkat. Pemantauan latar bergantung izin dan Android.',
              style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
            ),
          if (widget.watchStatus != null &&
              c.latestSync?.hasNewOrderFeed != false)
            ValueListenableBuilder<String>(
              valueListenable: widget.watchStatus!,
              builder: (_, status, _) =>
                  Text(status, style: const TextStyle(fontSize: 12)),
            ),
          if (widget.onEnableNotifications != null &&
              c.latestSync?.hasNewOrderFeed != false)
            TextButton(
              onPressed: widget.onEnableNotifications,
              child: const Text('Periksa izin notifikasi'),
            ),
        ],
      ),
    );
  }

  Widget _buildTabs(CashierController c, bool disabled) => Container(
    decoration: const BoxDecoration(
      color: AppColors.card,
      border: Border(bottom: BorderSide(color: AppColors.border)),
    ),
    child: Row(
      children: [
        _TabButton(
          key: const ValueKey('tab-active'),
          label: 'Aktif',
          selected: c.tab == 'active',
          onPressed: disabled ? null : () => _run(() => c.changeTab('active')),
        ),
        _TabButton(
          key: const ValueKey('tab-history'),
          label: 'Riwayat',
          selected: c.tab == 'history',
          onPressed: disabled ? null : () => _run(() => c.changeTab('history')),
        ),
      ],
    ),
  );

  static const _activeStatuses = <({String value, String label})>[
    (value: '', label: 'Semua'),
    (value: 'pending', label: 'Menunggu'),
    (value: 'ready', label: 'Siap ditangani'),
    (value: 'pos_input', label: 'Ditangani'),
    (value: 'confirmed', label: 'Terkonfirmasi'),
  ];
  static const _historyStatuses = <({String value, String label})>[
    (value: '', label: 'Semua'),
    (value: 'forwarded', label: 'Masuk aplikasi kasir'),
    (value: 'completed', label: 'Selesai'),
    (value: 'expired', label: 'Kedaluwarsa'),
    (value: 'cancelled', label: 'Dibatalkan'),
  ];

  Widget _buildFilters(CashierController c, bool disabled) {
    final statuses = c.tab == 'active' ? _activeStatuses : _historyStatuses;
    // Listening to the controller rebuilds only the field's decoration, so
    // typing never rebuilds the header, filters and order list behind it.
    final searchField = ValueListenableBuilder<TextEditingValue>(
      valueListenable: _search,
      builder: (context, value, _) => TextField(
        key: const ValueKey('order-search'),
        controller: _search,
        enabled: !disabled,
        textInputAction: TextInputAction.search,
        inputFormatters: [LengthLimitingTextInputFormatter(80)],
        decoration: InputDecoration(
          hintText: 'Cari nomor, nama, atau produk…',
          prefixIcon: const Icon(Icons.search, size: 20),
          suffixIcon: value.text.isEmpty
              ? null
              : IconButton(
                  key: const ValueKey('search-clear'),
                  tooltip: 'Hapus pencarian',
                  onPressed: disabled
                      ? null
                      : () {
                          _search.clear();
                          _searchTimer?.cancel();
                          unawaited(c.setSearch(''));
                        },
                  icon: const Icon(Icons.clear, size: 18),
                ),
          isDense: true,
        ),
        onChanged: _onSearchChanged,
      ),
    );
    final filterControls = Wrap(
      spacing: AppSpacing.sm,
      runSpacing: AppSpacing.xs,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        if (c.tab == 'history')
          OutlinedButton.icon(
            key: const ValueKey('date-filter'),
            onPressed: disabled ? null : _pickDay,
            icon: const Icon(Icons.event, size: 18),
            label: Text(
              c.selectedDay == null
                  ? 'Filter Tanggal'
                  : formatDayID(c.selectedDay!),
            ),
          ),
        if (c.tab == 'history' && c.selectedDay != null)
          IconButton(
            key: const ValueKey('date-clear'),
            tooltip: 'Hapus filter tanggal',
            onPressed: disabled
                ? null
                : () => _run(() => c.setSelectedDay(null)),
            icon: const Icon(Icons.event_busy, size: 20),
          ),
        Container(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.md,
            vertical: 2,
          ),
          decoration: BoxDecoration(
            border: Border.all(color: AppColors.border),
            borderRadius: BorderRadius.circular(AppRadius.badge),
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              key: const ValueKey('sort-order'),
              value: c.sort,
              isDense: true,
              items: const [
                DropdownMenuItem(value: 'newest', child: Text('Terbaru')),
                DropdownMenuItem(value: 'oldest', child: Text('Terlama')),
              ],
              onChanged: disabled
                  ? null
                  : (value) {
                      if (value != null) {
                        _run(() => c.setSort(value));
                      }
                    },
            ),
          ),
        ),
        if (c.isFiltering)
          TextButton.icon(
            key: const ValueKey('clear-filters'),
            onPressed: disabled ? null : _clearFilters,
            icon: const Icon(Icons.filter_alt_off, size: 18),
            label: const Text('Hapus filter'),
          ),
      ],
    );
    return Container(
      color: AppColors.card,
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        AppSpacing.md,
        AppSpacing.lg,
        AppSpacing.md,
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final compact = AppBreakpoints.isCompact(constraints.maxWidth);
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (compact) ...[
                searchField,
                const SizedBox(height: AppSpacing.sm),
                filterControls,
              ] else
                Row(
                  children: [
                    Expanded(child: searchField),
                    const SizedBox(width: AppSpacing.md),
                    Flexible(child: filterControls),
                  ],
                ),
              const SizedBox(height: AppSpacing.sm),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    for (final status in statuses)
                      Padding(
                        padding: const EdgeInsets.only(right: AppSpacing.xs),
                        child: ChoiceChip(
                          key: ValueKey(
                            'status-filter-'
                            '${status.value.isEmpty ? 'all' : status.value}',
                          ),
                          label: Text(status.label),
                          selected: c.statusFilter == status.value,
                          onSelected: disabled
                              ? null
                              : (_) =>
                                    _run(() => c.setStatusFilter(status.value)),
                        ),
                      ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _emptyState(CashierController c) {
    final title = c.isFiltering
        ? 'Tidak ada pesanan yang cocok'
        : c.tab == 'active'
        ? 'Belum ada pesanan aktif'
        : 'Riwayat masih kosong';
    final message = c.selectedDay != null
        ? 'Tidak ada pesanan pada tanggal ini '
              '(${formatDayID(c.selectedDay!)}).'
        : c.isFiltering
        ? 'Ubah kata kunci atau filter status untuk melihat pesanan lain.'
        : c.tab == 'active'
        ? 'Pesanan baru dari pelanggan akan muncul di sini secara langsung.'
        : 'Pesanan yang sudah masuk aplikasi kasir, selesai, batal, dan '
              'kedaluwarsa tampil di sini.';
    return Column(
      children: [
        EmptyStateView(
          icon: c.tab == 'active' ? Icons.receipt_long : Icons.history,
          title: title,
          message: message,
        ),
        if (c.isFiltering)
          TextButton.icon(
            key: const ValueKey('empty-clear-filters'),
            onPressed: _clearFilters,
            icon: const Icon(Icons.filter_alt_off),
            label: const Text('Hapus semua filter'),
          ),
      ],
    );
  }

  Widget _buildPagination(CashierController c, bool disabled) => Padding(
    padding: const EdgeInsets.only(top: AppSpacing.lg),
    child: Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        IconButton(
          key: const ValueKey('previous-page'),
          tooltip: 'Halaman sebelumnya',
          onPressed: disabled || c.offset == 0
              ? null
              : () => _run(c.previousPage),
          icon: const Icon(Icons.chevron_left),
        ),
        Text(
          c.selectedDay == null
              ? 'Halaman ${c.offset ~/ CashierController.pageSize + 1}'
              : 'Hasil filter tanggal',
          style: const TextStyle(color: AppColors.textSecondary, fontSize: 13),
        ),
        IconButton(
          key: const ValueKey('next-page'),
          tooltip: 'Halaman berikutnya',
          onPressed: disabled || !c.hasMore ? null : () => _run(c.nextPage),
          icon: const Icon(Icons.chevron_right),
        ),
      ],
    ),
  );
}

class _TabButton extends StatelessWidget {
  const _TabButton({
    super.key,
    required this.label,
    required this.selected,
    required this.onPressed,
  });
  final String label;
  final bool selected;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) => Expanded(
    child: InkWell(
      onTap: onPressed,
      child: Container(
        height: 46,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(
              color: selected ? AppColors.primary : Colors.transparent,
              width: 2.5,
            ),
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: selected ? AppColors.primary : AppColors.textSecondary,
            fontSize: 14,
            fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
          ),
        ),
      ),
    ),
  );
}

class _OrderCard extends StatelessWidget {
  const _OrderCard({
    required this.order,
    required this.enabled,
    this.onTap,
    this.now,
  });
  final OrderRecord order;
  final bool enabled;
  final VoidCallback? onTap;

  /// Shared one-second ticker. Only the countdown line listens to it so a
  /// ticking clock never rebuilds the whole card (and therefore the list).
  final ValueListenable<DateTime>? now;

  @override
  Widget build(BuildContext context) {
    final badge = statusBadge(order);
    final customer = order.customerName.isEmpty
        ? 'Tanpa nama'
        : order.customerName;
    final pending =
        order.status == 'pending' && order.paymentStatus == 'unpaid';
    final timeParts = <String>[
      if (order.itemCount > 0) '${order.itemCount} item',
      if (order.createdAt != null)
        'Dibuat ${formatDateTime(order.createdAt!.toLocal())}',
      if (pending) 'Batas ${formatDateTime(order.expiresAt.toLocal())}',
    ];
    final handoff = order.posHandoff;
    return Card(
      margin: const EdgeInsets.only(bottom: AppSpacing.md),
      child: InkWell(
        key: ValueKey('order-${order.id}'),
        borderRadius: BorderRadius.circular(AppRadius.card),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Text(
                      order.orderNumber,
                      style: const TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        height: 1.3,
                      ),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  StatusBadge(
                    label: badge.label,
                    foreground: badge.foreground,
                    background: badge.background,
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.xs),
              Row(
                children: [
                  const Icon(
                    Icons.person_outline,
                    size: 15,
                    color: AppColors.textSecondary,
                  ),
                  const SizedBox(width: 5),
                  Expanded(
                    child: Text(
                      customer,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 14,
                      ),
                    ),
                  ),
                ],
              ),
              if (timeParts.isNotEmpty) ...[
                const SizedBox(height: 2),
                Text(
                  timeParts.join(' • '),
                  style: const TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 12,
                  ),
                ),
              ],
              if (pending && !order.isExpired) ...[
                const SizedBox(height: 2),
                _CountdownText(order: order, now: now),
              ],
              if (order.status == 'pos_input' && handoff != null) ...[
                const SizedBox(height: 2),
                Text(
                  'Ditangani ${handoff.cashierName}',
                  style: const TextStyle(
                    color: AppColors.info,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
              if (order.status == 'forwarded' && handoff != null) ...[
                const SizedBox(height: 2),
                Text(
                  handoff.posReference.isEmpty
                      ? 'Masuk aplikasi kasir'
                      : 'Masuk aplikasi kasir • ${handoff.posReference}',
                  style: const TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 12,
                  ),
                ),
              ],
              const SizedBox(height: AppSpacing.md),
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Total',
                          style: TextStyle(
                            color: AppColors.textSecondary,
                            fontSize: 11,
                          ),
                        ),
                        Text(
                          rupiah(order.total),
                          style: const TextStyle(
                            color: AppColors.textPrimary,
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                            height: 1.2,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Text(
                    'Detail',
                    style: TextStyle(
                      color: enabled ? AppColors.primary : AppColors.disabled,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  Icon(
                    Icons.chevron_right,
                    size: 20,
                    color: enabled ? AppColors.primary : AppColors.disabled,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Rebuilds once per tick, not the whole card or list.
class _CountdownText extends StatelessWidget {
  const _CountdownText({required this.order, this.now});
  final OrderRecord order;
  final ValueListenable<DateTime>? now;

  @override
  Widget build(BuildContext context) {
    final listenable = now;
    if (listenable == null) return _label(order.isReviewed, DateTime.now());
    return ValueListenableBuilder<DateTime>(
      valueListenable: listenable,
      builder: (context, value, _) => _label(order.isReviewed, value),
    );
  }

  Widget _label(bool reviewed, DateTime at) => Text(
    reviewed
        ? 'Siap ditangani - sisa '
              '${countdownLabel(order.expiresAt.difference(at))}'
        : 'Perlu ditinjau - sisa '
              '${countdownLabel(order.expiresAt.difference(at))}',
    style: TextStyle(
      color: reviewed ? AppColors.info : AppColors.warning,
      fontSize: 12,
      fontWeight: FontWeight.w600,
    ),
  );
}
