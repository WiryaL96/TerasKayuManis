// Read-only staging contract. Mutation/cleanup coverage lives in isolated Go/SQL
// tests and scripts/staging-rush.mjs; never fabricate POS confirmations on prod.
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:cashier/core/app_config.dart';
import 'package:cashier/data/auth_session.dart';
import 'package:cashier/data/cashier_api.dart';

void main() {
  final path = Platform.environment['TKM_FLUTTER_LIVE_FIXTURE'];
  test('staging Auth and read-only mobile API contract', () async {
    final fixture =
        jsonDecode(await File(path!).readAsString()) as Map<String, dynamic>;
    final config = stagingConfig(fixture);
    final client = SupabaseClient(config.supabaseUrl, config.supabaseKey);
    final auth = SupabaseAuthSession(client);
    final api = CashierApi(config: config, auth: auth);
    try {
      await auth.signIn(
        fixture['email'] as String,
        fixture['password'] as String,
      );
      expect((await api.me()).fullName.trim(), isNotEmpty);
      expect((await api.sync()).revision, isNotEmpty);
      final orders = await api.listOrders();
      if (orders.isNotEmpty) {
        expect(
          (await api.detail(
            orders.first.id,
            orderNumber: orders.first.orderNumber,
          )).id,
          orders.first.id,
        );
      }
      await api.listOrders(tab: 'history', day: DateTime.now());
      await api.menu();
    } finally {
      api.close();
      try {
        await auth.signOut();
      } finally {
        await client.dispose();
      }
    }
  }, skip: path == null ? 'Explicit staging fixture required' : false);
}

AppConfig stagingConfig(Map<String, dynamic> fixture) {
  if (fixture['environment'] != 'staging') {
    throw const FormatException('Staging required');
  }
  final api = Uri.parse(fixture['apiBase'] as String);
  final auth = Uri.parse(fixture['supabaseUrl'] as String);
  final approvedHost = fixture['stagingHost'] as String;
  final project = fixture['stagingProjectRef'] as String;
  const forbidden = {
    'teraskayumanis.vercel.app',
    'teraskayumanis.alrizky.me',
    'aiptdjypuccoakyfvdyl.supabase.co',
  };
  if (forbidden.contains(api.host) ||
      forbidden.contains(auth.host) ||
      project == 'aiptdjypuccoakyfvdyl' ||
      api.host != approvedHost ||
      auth.host != '$project.supabase.co' ||
      !RegExp(r'^[a-z]{20}$').hasMatch(project)) {
    throw const FormatException('Production or unapproved staging target');
  }
  return AppConfig(
    apiBase: api,
    wsUrl: api.replace(scheme: 'wss', path: '/ws'),
    wsOrigin: api.origin,
    supabaseUrl: auth.origin,
    supabaseKey: fixture['publicKey'] as String,
    pollingOnly: true,
  );
}
