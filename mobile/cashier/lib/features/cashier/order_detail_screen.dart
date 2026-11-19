import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/app_theme.dart';
import '../../core/visible_clock.dart';
import '../../data/order_snapshot_store.dart';
import '../../domain/models.dart';
import 'cashier_controller.dart';
import 'order_editor_screen.dart';
import 'ui_common.dart';

class OrderDetailScreen extends StatefulWidget {
  const OrderDetailScreen({
    super.key,
    required this.controller,
    required this.order,
  });
  final CashierController controller;
  final OrderRecord order;
  @override
  State<OrderDetailScreen> createState() => _OrderDetailScreenState();
}

class _OrderDetailScreenState extends State<OrderDetailScreen> {
  late OrderRecord _order = widget.order;
  final _reference = TextEditingController();
  final _takeoverReason = TextEditingController();
  bool _working = false;
  bool _enteredInPos = false;
  bool _paidInPos = false;
  String? _error;
  final _clock = VisibleClock();
  late final ValueNotifier<DetailSnapshot> _detail;
  bool _verified = false;
  bool _confirming = false;

  @override
  void initState() {
    super.initState();
    _detail = widget.controller.watchDetail(widget.order);
    _detail.addListener(_snapshotChanged);
    _verified = _detail.value.usable;
  }

  void _snapshotChanged() {
    if (!mounted) return;
    final state = _detail.value;
    final next = state.order;
    if (next != null &&
        next.version >= _order.version &&
        (next.version != _order.version ||
            (_order.items.isEmpty && next.items.isNotEmpty) ||
            next.posHandoff?.cashierId != _order.posHandoff?.cashierId)) {
      setState(() {
        _order = next;
        _enteredInPos = false;
        _paidInPos = false;
        _reference.clear();
        _verified = state.usable;
      });
    } else if (_verified != state.usable) {
      setState(() => _verified = state.usable);
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _clock.attach(context);
  }

  @override
  void dispose() {
    _clock.dispose();
    _detail.removeListener(_snapshotChanged);
    widget.controller.releaseDetail(widget.order.id);
    _reference.dispose();
    _takeoverReason.dispose();
    super.dispose();
  }

  bool get _countdownVisible =>
      _order.status == 'pending' && _order.paymentStatus == 'unpaid';

  String? _countdownText() {
    if (!_countdownVisible) return null;
    return countdownLabel(_order.expiresAt.difference(DateTime.now()));
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
          () => _error =
              'Tindakan gagal. Muat ulang dan periksa status sebelum mencoba '
              'lagi.',
        );
      }
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  Future<void> _edit({bool reorder = false}) async {
    if (_working || _confirming || widget.controller.busy) return;
    final snapshot = _order;
    Catalog? catalog;
    ReorderDraft? draft;
    await _run(() async {
      draft = reorder ? await widget.controller.prepareReorder(snapshot) : null;
      catalog = await widget.controller.menu();
    });
    if (!mounted || !widget.controller.signedIn || catalog == null) return;
    final result = await Navigator.of(context).push<OrderRecord>(
      MaterialPageRoute(
        builder: (_) => OrderEditorScreen(
          controller: widget.controller,
          catalog: catalog!,
          order: snapshot,
          reorderDraft: draft,
        ),
      ),
    );
    if (mounted && result != null) {
      if (result.id != widget.order.id) {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute<void>(
            builder: (_) =>
                OrderDetailScreen(controller: widget.controller, order: result),
          ),
        );
      } else {
        setState(() => _order = result);
      }
    }
  }

  Future<bool> _confirm({
    required String title,
    required String message,
    required String action,
  }) async {
    setState(() => _confirming = true);
    try {
      return await confirmAction(
        context,
        title: title,
        message: message,
        action: action,
      );
    } finally {
      if (mounted) setState(() => _confirming = false);
    }
  }

  Future<void> _claim() async {
    if (_working || _confirming || widget.controller.busy) return;
    final snapshot = _order;
    if (!await _confirm(
      title: 'Tangani pesanan?',
      message:
          '${snapshot.orderNumber} • ${_customer(snapshot)}\n\n'
          'Setelah ditangani, hitung mundur berhenti. Input pesanan ini ke '
          'aplikasi kasir restoran.',
      action: 'Ya, tangani',
    )) {
      return;
    }
    if (!mounted || !widget.controller.signedIn) return;
    if (!_verified || _order.version != snapshot.version) {
      setState(
        () => _error = 'Pesanan berubah. Periksa kembali sebelum menangani.',
      );
      return;
    }
    await _run(() async {
      final result = await widget.controller.claim(snapshot);
      if (mounted && result != null) {
        setState(() => _order = result);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '${result.orderNumber} siap diinput ke aplikasi kasir.',
            ),
          ),
        );
      }
    });
  }

  Future<void> _takeOver() async {
    if (_working || _confirming || widget.controller.busy) return;
    final reason = _takeoverReason.text.trim();
    if (reason.runes.length < 5 || reason.runes.length > 200) {
      setState(() => _error = 'Alasan pengambilalihan harus 5–200 karakter.');
      return;
    }
    final snapshot = _order;
    final handler = snapshot.posHandoff?.cashierName ?? 'kasir lain';
    if (!await _confirm(
      title: 'Ambil alih pesanan?',
      message:
          '${snapshot.orderNumber} saat ini ditangani $handler.\n'
          'Alasan: $reason\n\n'
          'Pengambilalihan akan dicatat pada audit staf.',
      action: 'Ya, ambil alih',
    )) {
      return;
    }
    if (!mounted || !widget.controller.signedIn) return;
    if (!_verified || _order.version != snapshot.version) {
      setState(
        () => _error = 'Pesanan berubah. Periksa POS dan konfirmasi kembali.',
      );
      return;
    }
    await _run(() async {
      final result = await widget.controller.claim(
        snapshot,
        takeoverReason: reason,
      );
      if (mounted && result != null) {
        setState(() => _order = result);
        _takeoverReason.clear();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${result.orderNumber} diambil alih.')),
        );
      }
    });
  }

  Future<void> _forward() async {
    if (_working || _confirming || widget.controller.busy) return;
    if (!_enteredInPos || !_paidInPos) {
      setState(
        () => _error =
            'Centang kedua konfirmasi: pesanan sudah diinput dan pembayaran '
            'sudah diterima di aplikasi kasir.',
      );
      return;
    }
    final snapshot = _order;
    final reference = _reference.text.trim();
    if (!await _confirm(
      title: 'Konfirmasi pesanan masuk aplikasi kasir?',
      message:
          '${snapshot.orderNumber} • ${_customer(snapshot)}\n'
          '${reference.isEmpty ? '' : 'Referensi POS: $reference\n'}\n'
          'Pastikan pesanan sudah diinput dan pembayaran diterima di aplikasi '
          'kasir restoran. Tindakan ini tidak mencatat pembayaran di aplikasi '
          'ini.',
      action: 'Ya, sudah masuk',
    )) {
      return;
    }
    if (!mounted || !widget.controller.signedIn) return;
    if (!_verified ||
        _order.version != snapshot.version ||
        !_enteredInPos ||
        !_paidInPos) {
      setState(
        () => _error = 'Penanganan berubah. Periksa POS dan centang kembali.',
      );
      return;
    }
    await _run(() async {
      final result = await widget.controller.forward(
        snapshot,
        enteredInPos: _enteredInPos,
        paidInPos: _paidInPos,
        reference: reference,
      );
      if (mounted && result != null) {
        setState(() {
          _order = result;
          _enteredInPos = false;
          _paidInPos = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '${result.orderNumber} ditandai masuk aplikasi kasir.',
            ),
          ),
        );
      }
    });
  }

  String _customer(OrderRecord order) =>
      order.customerName.isEmpty ? 'Tanpa nama' : order.customerName;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.controller,
    builder: (context, _) {
      final c = widget.controller;
      if (!c.signedIn) return const Scaffold(body: SizedBox.shrink());
      final disabled = c.busy || _working || _confirming || !_verified;
      return Scaffold(
        backgroundColor: AppColors.background,
        appBar: AppBar(
          actions: [
            IconButton(
              tooltip: 'Muat ulang status pesanan',
              onPressed: _working || c.busy
                  ? null
                  : () => c.refreshDetail(_order.id),
              icon: const Icon(Icons.refresh),
            ),
          ],
          title: Text(
            _order.orderNumber,
            style: const TextStyle(
              color: AppColors.textPrimary,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        body: SafeArea(
          child: Column(
            children: [
              if (c.busy || _working) const LinearProgressIndicator(),
              Expanded(
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final left = _buildLeft(c);
                    final right = <Widget>[
                      ValueListenableBuilder<DateTime>(
                        valueListenable: _clock,
                        builder: (_, now, _) => Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: _buildRight(c, disabled),
                        ),
                      ),
                    ];
                    final width = constraints.maxWidth;
                    if (!AppBreakpoints.isWide(width)) {
                      return Center(
                        child: ConstrainedBox(
                          constraints: BoxConstraints(
                            maxWidth: AppBreakpoints.contentMaxWidth(width),
                          ),
                          child: ListView.builder(
                            padding: const EdgeInsets.all(AppSpacing.lg),
                            itemCount: left.length + right.length,
                            itemBuilder: (_, index) => index < left.length
                                ? left[index]
                                : right[index - left.length],
                          ),
                        ),
                      );
                    }
                    return Center(
                      child: ConstrainedBox(
                        constraints: BoxConstraints(
                          maxWidth: AppBreakpoints.contentMaxWidth(width),
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              flex: 3,
                              child: ListView.builder(
                                padding: const EdgeInsets.all(AppSpacing.lg),
                                itemCount: left.length,
                                itemBuilder: (_, index) => left[index],
                              ),
                            ),
                            const VerticalDivider(width: 1),
                            Expanded(
                              flex: 2,
                              child: ListView(
                                padding: const EdgeInsets.all(AppSpacing.lg),
                                children: right,
                              ),
                            ),
                          ],
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
    },
  );

  List<Widget> _buildLeft(CashierController c) => [
    ValueListenableBuilder<DateTime>(
      valueListenable: _clock,
      builder: (_, now, _) =>
          _SummaryCard(order: _order, countdown: _countdownText()),
    ),
    ValueListenableBuilder<DetailSnapshot>(
      valueListenable: _detail,
      builder: (_, state, _) => state.usable
          ? const SizedBox.shrink()
          : InfoBanner.warning(
              state.error ?? 'Memeriksa status terbaru sebelum tindakan.',
            ),
    ),
    const SizedBox(height: AppSpacing.lg),
    PendingRecovery(controller: c),
    if (_error ?? c.error case final String error)
      ErrorNotice(
        message: error,
        onClose: () {
          setState(() => _error = null);
          c.clearError();
        },
      ),
    if (_order.items.isNotEmpty) ...[
      const SizedBox(height: AppSpacing.md),
      const SectionTitle('Item pesanan'),
      for (final item in _order.items)
        RepaintBoundary(
          child: SectionCard(child: _ItemRow(line: item)),
        ),
    ],
    const SizedBox(height: AppSpacing.md),
    SectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SectionTitle('Total pesanan'),
          Row(
            children: [
              const Expanded(
                child: Text(
                  'Estimasi dari server',
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 14,
                  ),
                ),
              ),
              Flexible(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerRight,
                  child: Text(
                    rupiah(_order.total),
                    style: const TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 24,
                      fontWeight: FontWeight.w700,
                      height: 1.2,
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.xs),
          const Text(
            'Tagihan akhir dan pembayaran mengikuti POS restoran.',
            style: TextStyle(
              color: AppColors.textSecondary,
              fontSize: 12,
              height: 1.45,
            ),
          ),
        ],
      ),
    ),
    const SizedBox(height: AppSpacing.xxl),
  ];

  List<Widget> _buildRight(CashierController c, bool disabled) => [
    if (_order.status == 'pending')
      _reviewActions(disabled)
    else if (_order.isPosInput)
      _posActions(c, disabled)
    else if (_order.isForwarded)
      InfoBanner.success(
        _forwardedMessage(_order),
        title: 'Sudah masuk aplikasi kasir',
      )
    else if (_order.status == 'confirmed')
      const InfoBanner(
        icon: Icons.info_outline,
        tone: BadgeStyle('', AppColors.info, AppColors.infoSurface),
        message:
            'Pesanan ini tercatat pada alur lama. Gunakan riwayat untuk '
            'keperluan audit.',
      ),
    if (_order.isExpired) ...[
      const SizedBox(height: AppSpacing.md),
      FilledButton.icon(
        key: const ValueKey('reorder-order'),
        onPressed: disabled || c.hasPendingAttempt
            ? null
            : () => _edit(reorder: true),
        icon: const Icon(Icons.replay),
        label: const Text('Buat draf pesanan ulang'),
      ),
      const SizedBox(height: AppSpacing.sm),
      const Text(
        'Pesanan lama tetap kedaluwarsa. Pesanan baru hanya dibuat setelah '
        'konfirmasi draf.',
        style: TextStyle(
          color: AppColors.textSecondary,
          fontSize: 13,
          height: 1.45,
        ),
      ),
    ],
    const SizedBox(height: AppSpacing.xxl),
  ];

  String _forwardedMessage(OrderRecord order) {
    final handoff = order.posHandoff;
    final parts = <String>[
      if (handoff?.forwardedAt != null)
        'Ditandai masuk ${formatDateTime(handoff!.forwardedAt!.toLocal())}',
      if (handoff != null && handoff.posReference.isNotEmpty)
        'Referensi POS: ${handoff.posReference}',
      if (handoff != null) 'Kasir: ${handoff.cashierName}',
    ];
    return parts.isEmpty
        ? 'Pesanan sudah ditandai masuk ke aplikasi kasir restoran.'
        : parts.join('\n');
  }

  Widget _reviewActions(bool disabled) {
    final canReview = _order.canReview(DateTime.now());
    final reviewed = _order.isReviewed;
    return SectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SectionTitle('Tinjau pesanan'),
          Text(
            reviewed
                ? 'Pesanan sudah ditinjau dan siap ditangani. Setelah '
                      'ditangani, hitung mundur berhenti.'
                : 'Cek ketersediaan menu bersama pelanggan, sesuaikan item '
                      'bila perlu, lalu simpan tinjauan sebelum menangani '
                      'pesanan.',
            style: const TextStyle(
              color: AppColors.textSecondary,
              fontSize: 13,
              height: 1.45,
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          if (reviewed && canReview) ...[
            FilledButton(
              key: const ValueKey('claim-order'),
              onPressed: disabled ? null : _claim,
              child: const Text('Tangani pesanan ini'),
            ),
            const SizedBox(height: AppSpacing.sm),
            TextButton(
              key: const ValueKey('open-review'),
              onPressed: disabled ? null : () => _edit(),
              child: const Text('Ubah tinjauan pesanan'),
            ),
          ] else if (canReview) ...[
            FilledButton(
              key: const ValueKey('open-review'),
              onPressed: disabled ? null : () => _edit(),
              child: const Text('Proses Pemesanan'),
            ),
            const SizedBox(height: AppSpacing.sm),
            const Text(
              'Tombol menangani pesanan muncul setelah tinjauan disimpan.',
              style: TextStyle(
                color: AppColors.textSecondary,
                fontSize: 12,
                height: 1.45,
              ),
            ),
          ] else
            InfoBanner.warning(
              'Batas waktu pesanan sudah lewat. Pesanan tidak dapat ditangani '
              'lagi.',
            ),
        ],
      ),
    );
  }

  Widget _posActions(CashierController c, bool disabled) {
    final handoff = _order.posHandoff;
    final profile = c.staff;
    final owned = _order.canForwardFor(profile?.id);
    final canTakeOver = _order.canTakeOverFor(
      staffId: profile?.id,
      isAdmin: profile?.isAdmin ?? false,
    );
    final stale = _order.isStalePosClaim(DateTime.now());
    if (owned) {
      final ready = _enteredInPos && _paidInPos && !disabled;
      return SectionCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SectionTitle('Input ke aplikasi kasir'),
            if (stale) ...[
              InfoBanner.warning(
                'Pesanan ini sudah ditangani lebih dari 10 menit. Periksa '
                'transaksi di aplikasi kasir sebelum melanjutkan.',
              ),
              const SizedBox(height: AppSpacing.md),
            ],
            InfoBanner(
              icon: Icons.timer_off_outlined,
              tone: const BadgeStyle('', AppColors.info, AppColors.infoSurface),
              title: 'Hitung mundur berhenti',
              message:
                  'Pesanan ini ditangani oleh '
                  '${handoff?.cashierName ?? profile?.fullName ?? 'Anda'}. '
                  'Input ke aplikasi kasir restoran, lalu konfirmasi bahwa '
                  'pesanan sudah masuk.',
            ),
            const SizedBox(height: AppSpacing.md),
            TextField(
              key: const ValueKey('pos-reference'),
              controller: _reference,
              enabled: !disabled,
              inputFormatters: [LengthLimitingTextInputFormatter(80)],
              decoration: const InputDecoration(
                labelText: 'Referensi POS (opsional)',
                helperText: 'Nomor struk atau ID pesanan di aplikasi kasir.',
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            CheckboxListTile(
              key: const ValueKey('entered-in-pos'),
              value: _enteredInPos,
              onChanged: disabled
                  ? null
                  : (value) => setState(() => _enteredInPos = value ?? false),
              contentPadding: EdgeInsets.zero,
              controlAffinity: ListTileControlAffinity.leading,
              title: const Text(
                'Pesanan sudah dimasukkan ke aplikasi kasir',
                style: TextStyle(fontSize: 14),
              ),
            ),
            CheckboxListTile(
              key: const ValueKey('paid-in-pos'),
              value: _paidInPos,
              onChanged: disabled
                  ? null
                  : (value) => setState(() => _paidInPos = value ?? false),
              contentPadding: EdgeInsets.zero,
              controlAffinity: ListTileControlAffinity.leading,
              title: const Text(
                'Pembayaran sudah diterima di aplikasi kasir',
                style: TextStyle(fontSize: 14),
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            FilledButton(
              key: const ValueKey('forward-order'),
              onPressed: ready ? _forward : null,
              child: const Text('Sudah masuk aplikasi kasir'),
            ),
            const SizedBox(height: AppSpacing.sm),
            const Text(
              'Aplikasi ini tidak mencatat pembayaran. Status forwarded hanya '
              'menandai serah-terima ke POS restoran.',
              style: TextStyle(
                color: AppColors.textSecondary,
                fontSize: 12,
                height: 1.45,
              ),
            ),
          ],
        ),
      );
    }
    if (canTakeOver) {
      return SectionCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SectionTitle('Pesanan ditangani kasir lain'),
            if (stale) ...[
              InfoBanner.warning(
                'Pesanan ini sudah ditangani lebih dari 10 menit. Periksa '
                'aplikasi kasir sebelum mengambil alih.',
              ),
              const SizedBox(height: AppSpacing.sm),
            ],
            InfoBanner.warning(
              '${handoff?.cashierName ?? 'Kasir lain'} sedang menangani '
              'pesanan ini. Sebagai ${profile?.role ?? 'admin'}, Anda dapat '
              'mengambil alih dengan alasan yang tercatat.',
            ),
            const SizedBox(height: AppSpacing.md),
            TextField(
              key: const ValueKey('takeover-reason'),
              controller: _takeoverReason,
              enabled: !disabled,
              maxLines: 3,
              minLines: 2,
              inputFormatters: [LengthLimitingTextInputFormatter(200)],
              decoration: const InputDecoration(
                labelText: 'Alasan pengambilalihan',
                helperText: 'Wajib 5–200 karakter.',
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            FilledButton(
              key: const ValueKey('takeover-order'),
              onPressed: disabled ? null : _takeOver,
              child: const Text('Ambil alih pesanan'),
            ),
          ],
        ),
      );
    }
    return InfoBanner.warning(
      'Pesanan sedang ditangani ${handoff?.cashierName ?? 'kasir lain'}. '
      'Hanya kasir tersebut atau admin yang dapat melanjutkan.',
      title: 'Pesanan sedang ditangani',
    );
  }
}

class _SummaryCard extends StatelessWidget {
  const _SummaryCard({required this.order, required this.countdown});
  final OrderRecord order;
  final String? countdown;

  @override
  Widget build(BuildContext context) {
    final expired = order.isExpired;
    final stateStyle = orderStateBadge(order);
    final cd = countdown;
    final handoff = order.posHandoff;
    return SectionCard(
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
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                    height: 1.25,
                  ),
                ),
              ),
              StatusBadge(
                label: stateStyle.label,
                foreground: stateStyle.foreground,
                background: stateStyle.background,
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            order.customerName.isEmpty
                ? 'Tanpa nama pelanggan'
                : order.customerName,
            style: const TextStyle(
              color: AppColors.textPrimary,
              fontSize: 16,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.sm,
            children: [
              if (order.status != 'completed' && order.status != 'cancelled')
                StatusBadge.of(order, payment: true),
              if (order.status == 'pending')
                order.reviewedVersion == order.version
                    ? const StatusBadge(
                        label: 'Sudah ditinjau',
                        foreground: AppColors.info,
                        background: AppColors.infoSurface,
                      )
                    : const StatusBadge(
                        label: 'Perlu ditinjau',
                        foreground: AppColors.warning,
                        background: AppColors.warningSurface,
                      ),
              if (order.isPosInput)
                const StatusBadge(
                  label: 'Ditangani kasir',
                  foreground: AppColors.info,
                  background: AppColors.infoSurface,
                ),
              if (order.isForwarded)
                const StatusBadge(
                  label: 'Masuk aplikasi kasir',
                  foreground: AppColors.info,
                  background: AppColors.infoSurface,
                ),
              if (expired && order.status == 'pending')
                const StatusBadge(
                  label: 'Kedaluwarsa',
                  foreground: AppColors.errorText,
                  background: AppColors.errorSurface,
                ),
              if (order.paymentStatus == 'paid')
                const StatusBadge(
                  label: 'Lunas',
                  foreground: AppColors.success,
                  background: AppColors.successSurface,
                ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          _MetaRow(
            icon: Icons.schedule,
            text: order.createdAt == null
                ? 'Batas: ${formatDateTime(order.expiresAt.toLocal())}'
                : 'Dibuat ${formatDateTime(order.createdAt!.toLocal())} • '
                      'Batas ${formatDateTime(order.expiresAt.toLocal())}',
          ),
          if (order.legacyCashierName != null &&
              order.legacyCashierName!.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.xs),
            _MetaRow(
              icon: Icons.verified_user_outlined,
              text: 'Konfirmasi oleh ${order.legacyCashierName}',
            ),
          ],
          if (handoff != null) ...[
            const SizedBox(height: AppSpacing.xs),
            _MetaRow(
              icon: Icons.point_of_sale,
              text: handoff.forwardedAt == null
                  ? 'Ditangani ${handoff.cashierName} sejak '
                        '${formatDateTime(handoff.claimedAt.toLocal())}'
                  : 'Masuk aplikasi kasir '
                        '${formatDateTime(handoff.forwardedAt!.toLocal())} • '
                        '${handoff.cashierName}'
                        '${handoff.posReference.isEmpty ? '' : ' • ${handoff.posReference}'}',
            ),
          ],
          if (cd != null) ...[
            const SizedBox(height: AppSpacing.sm),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.md,
                vertical: AppSpacing.sm,
              ),
              decoration: BoxDecoration(
                color: cd == '00:00'
                    ? AppColors.errorSurface
                    : AppColors.warningSurface,
                borderRadius: BorderRadius.circular(AppRadius.badge),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.timer_outlined,
                    size: 16,
                    color: cd == '00:00'
                        ? AppColors.errorText
                        : AppColors.warning,
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: Text(
                      'Sisa waktu sebelum kedaluwarsa',
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: cd == '00:00'
                            ? AppColors.errorText
                            : AppColors.warning,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Text(
                    cd,
                    style: TextStyle(
                      color: cd == '00:00'
                          ? AppColors.errorText
                          : AppColors.warning,
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                ],
              ),
            ),
          ],
          if (order.isPosInput) ...[
            const SizedBox(height: AppSpacing.sm),
            const InfoBanner(
              icon: Icons.timer_off_outlined,
              tone: BadgeStyle('', AppColors.info, AppColors.infoSurface),
              message:
                  'Waktu pembayaran dijeda • Hitung mundur berhenti karena '
                  'pesanan sedang ditangani kasir.',
            ),
          ],
        ],
      ),
    );
  }
}

class _MetaRow extends StatelessWidget {
  const _MetaRow({required this.icon, required this.text});
  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      Icon(icon, size: 15, color: AppColors.textSecondary),
      const SizedBox(width: 6),
      Expanded(
        child: Text(
          text,
          style: const TextStyle(
            color: AppColors.textSecondary,
            fontSize: 13,
            height: 1.4,
          ),
        ),
      ),
    ],
  );
}

class _ItemRow extends StatelessWidget {
  const _ItemRow({required this.line});
  final OrderLine line;

  @override
  Widget build(BuildContext context) {
    final addons = line.addonNames.isNotEmpty
        ? line.addonNames.join(', ')
        : line.addonIds.join(', ');
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            constraints: const BoxConstraints(minWidth: 36),
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.sm,
              vertical: 4,
            ),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: AppColors.neutralSurface,
              borderRadius: BorderRadius.circular(AppRadius.badge),
            ),
            child: Text(
              '${line.quantity}×',
              style: const TextStyle(
                color: AppColors.textPrimary,
                fontSize: 13,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  line.name,
                  style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    height: 1.35,
                  ),
                ),
                if (line.variantName.isNotEmpty)
                  Text(
                    'Varian: ${line.variantName}',
                    style: const TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 13,
                      height: 1.4,
                    ),
                  ),
                if (addons.isNotEmpty)
                  Text(
                    'Tambahan: $addons',
                    style: const TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 13,
                      height: 1.4,
                    ),
                  ),
                if (line.notes.isNotEmpty)
                  Text(
                    'Catatan: ${line.notes}',
                    style: const TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 13,
                      height: 1.4,
                    ),
                  ),
                Text(
                  '${rupiah(line.unitPrice)} / item',
                  style: const TextStyle(
                    color: AppColors.disabled,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                rupiah(line.subtotal),
                style: const TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
