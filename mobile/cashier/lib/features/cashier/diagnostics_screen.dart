import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/diagnostics.dart';

class DiagnosticsScreen extends StatelessWidget {
  const DiagnosticsScreen({super.key});
  @override
  Widget build(BuildContext context) {
    final report = Diagnostics.instance.report();
    return Scaffold(
      appBar: AppBar(title: const Text('Diagnostik perangkat')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            const Text(
              'Catatan lokal terbatas untuk pemeriksaan koneksi. Tidak berisi nama, token, atau isi pesanan.',
            ),
            FilledButton(
              onPressed: () async {
                await Clipboard.setData(ClipboardData(text: report));
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Diagnostik disalin')),
                  );
                }
              },
              child: const Text('Salin diagnostik'),
            ),
            SelectableText(report),
          ],
        ),
      ),
    );
  }
}
