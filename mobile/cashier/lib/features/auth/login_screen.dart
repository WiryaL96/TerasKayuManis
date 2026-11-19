import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/app_theme.dart';
import '../cashier/cashier_controller.dart';
import '../cashier/ui_common.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key, required this.controller, this.startupError});
  final CashierController controller;
  final String? startupError;
  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _form = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _pin = TextEditingController();
  String? _selectedCashierId;
  bool _pinMode = false;
  bool _loadingRoster = false;
  bool _submitting = false;
  bool _obscure = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    unawaited(_loadRoster());
  }

  Future<void> _loadRoster() async {
    if (_loadingRoster) return;
    setState(() => _loadingRoster = true);
    try {
      final list = await widget.controller.loadCashiers();
      if (mounted &&
          _selectedCashierId != null &&
          !list.any((c) => c.id == _selectedCashierId)) {
        setState(() => _selectedCashierId = null);
      }
    } finally {
      if (mounted) setState(() => _loadingRoster = false);
    }
  }

  Future<void> _login() async {
    if (_submitting ||
        widget.controller.busy ||
        !_form.currentState!.validate()) {
      return;
    }
    FocusScope.of(context).unfocus();
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      if (_pinMode) {
        final cashierId = _selectedCashierId;
        if (cashierId == null || cashierId.isEmpty) {
          setState(() => _error = 'Pilih akun kasir terlebih dahulu.');
          return;
        }
        await widget.controller.loginPin(cashierId, _pin.text.trim());
      } else {
        await widget.controller.login(_email.text.trim(), _password.text);
      }
    } catch (_) {
      if (mounted) {
        setState(
          () => _error = 'Tidak dapat masuk. Periksa koneksi dan akun staf.',
        );
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    _pin.dispose();
    super.dispose();
  }

  static final _emailPattern = RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$');
  static final _usernamePattern = RegExp(r'^[a-z0-9][a-z0-9._-]{2,31}$');

  String? _validateIdentifier(String? value) {
    final text = value?.trim() ?? '';
    if (text.isEmpty) return 'Masukkan email atau username staf';
    if (text.contains('@')) {
      return _emailPattern.hasMatch(text) ? null : 'Masukkan email yang valid';
    }
    return _usernamePattern.hasMatch(text.toLowerCase())
        ? null
        : 'Masukkan email atau username yang valid';
  }

  @override
  Widget build(BuildContext context) {
    final disabled =
        _submitting || widget.controller.busy || widget.controller.loading;
    final error = _error ?? widget.controller.error ?? widget.startupError;
    return Scaffold(
      backgroundColor: AppColors.backgroundAlt,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(AppSpacing.xl),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: SectionCard(
                padding: const EdgeInsets.all(AppSpacing.xxl),
                child: Form(
                  key: _form,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          const RestaurantLogo(size: 48, radius: 14),
                          const SizedBox(width: AppSpacing.md),
                          const Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'TerasKayuManis',
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    color: AppColors.textPrimary,
                                    fontSize: 20,
                                    fontWeight: FontWeight.w700,
                                    height: 1.2,
                                  ),
                                ),
                                Text(
                                  'Kasir • Input pesanan ke POS',
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    color: AppColors.textSecondary,
                                    fontSize: 13,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: AppSpacing.xl),
                      const Text(
                        'Masuk untuk mulai menangani pesanan.',
                        style: TextStyle(
                          color: AppColors.textSecondary,
                          fontSize: 14,
                        ),
                      ),
                      const SizedBox(height: AppSpacing.xl),
                      if (_pinMode) ...[
                        DropdownButtonFormField<String>(
                          key: const ValueKey('login-cashier-select'),
                          initialValue: _selectedCashierId,
                          decoration: InputDecoration(
                            labelText: 'Pilih kasir',
                            prefixIcon: const Icon(Icons.badge_outlined),
                            suffixIcon: IconButton(
                              tooltip: 'Muat ulang daftar kasir',
                              onPressed: disabled || _loadingRoster
                                  ? null
                                  : _loadRoster,
                              icon: const Icon(Icons.refresh, size: 20),
                            ),
                          ),
                          items: [
                            for (final c in widget.controller.cashiers)
                              DropdownMenuItem(
                                value: c.id,
                                child: Text(
                                  c.name,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                          ],
                          onChanged: disabled
                              ? null
                              : (val) =>
                                    setState(() => _selectedCashierId = val),
                          validator: (val) => val == null || val.isEmpty
                              ? 'Pilih akun kasir'
                              : null,
                        ),
                        const SizedBox(height: AppSpacing.lg),
                        TextFormField(
                          key: const ValueKey('login-pin'),
                          controller: _pin,
                          enabled: !disabled,
                          obscureText: true,
                          keyboardType: TextInputType.number,
                          inputFormatters: [
                            FilteringTextInputFormatter.digitsOnly,
                            LengthLimitingTextInputFormatter(6),
                          ],
                          onFieldSubmitted: (_) => _login(),
                          decoration: const InputDecoration(
                            labelText: 'PIN kasir (6 angka)',
                            prefixIcon: Icon(Icons.pin_outlined),
                          ),
                          validator: (value) =>
                              value == null ||
                                  !RegExp(r'^\d{6}$').hasMatch(value.trim())
                              ? 'Masukkan PIN 6 angka'
                              : null,
                        ),
                      ] else ...[
                        TextFormField(
                          key: const ValueKey('login-email'),
                          controller: _email,
                          enabled: !disabled,
                          keyboardType: TextInputType.emailAddress,
                          autofillHints: const [AutofillHints.username],
                          textInputAction: TextInputAction.next,
                          decoration: const InputDecoration(
                            labelText: 'Email atau username staf',
                            hintText: 'nama@contoh.com',
                            prefixIcon: Icon(Icons.mail_outline),
                          ),
                          validator: _validateIdentifier,
                        ),
                        const SizedBox(height: AppSpacing.lg),
                        TextFormField(
                          key: const ValueKey('login-password'),
                          controller: _password,
                          enabled: !disabled,
                          obscureText: _obscure,
                          autofillHints: const [AutofillHints.password],
                          onFieldSubmitted: (_) => _login(),
                          decoration: InputDecoration(
                            labelText: 'Kata sandi',
                            prefixIcon: const Icon(Icons.lock_outline),
                            suffixIcon: IconButton(
                              tooltip: _obscure
                                  ? 'Tampilkan kata sandi'
                                  : 'Sembunyikan kata sandi',
                              onPressed: () =>
                                  setState(() => _obscure = !_obscure),
                              icon: Icon(
                                _obscure
                                    ? Icons.visibility
                                    : Icons.visibility_off,
                              ),
                            ),
                          ),
                          validator: (value) => value == null || value.isEmpty
                              ? 'Masukkan kata sandi'
                              : null,
                        ),
                      ],
                      if (error != null) ...[
                        const SizedBox(height: AppSpacing.lg),
                        ErrorNotice(message: error),
                      ],
                      const SizedBox(height: AppSpacing.xl),
                      FilledButton(
                        key: const ValueKey('login-submit'),
                        style: FilledButton.styleFrom(
                          minimumSize: const Size.fromHeight(48),
                        ),
                        onPressed: disabled ? null : _login,
                        child: Text(disabled ? 'Memeriksa sesi…' : 'Masuk'),
                      ),
                      const SizedBox(height: AppSpacing.sm),
                      TextButton(
                        key: const ValueKey('login-mode-toggle'),
                        onPressed: disabled
                            ? null
                            : () {
                                setState(() {
                                  _pinMode = !_pinMode;
                                  _error = null;
                                  _pin.clear();
                                  _password.clear();
                                });
                                if (_pinMode &&
                                    widget.controller.cashiers.isEmpty) {
                                  unawaited(_loadRoster());
                                }
                              },
                        child: Text(
                          _pinMode
                              ? 'Masuk dengan email / kata sandi'
                              : 'Masuk dengan PIN kasir',
                        ),
                      ),
                      const SizedBox(height: AppSpacing.sm),
                      const Text(
                        'Hanya untuk staf berwenang. Pesanan dimuat setelah masuk.',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: AppColors.textSecondary,
                          fontSize: 12,
                          height: 1.5,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
