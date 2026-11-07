import 'dart:async';

import 'package:chappy_player/core/companion_qr_invitation.dart';
import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

/// Camera starts only after the user explicitly opens this trusted host page.
/// This page never sends scanned QR contents to the network or to .chappy JS.
class CompanionQrScannerPage extends StatefulWidget {
  const CompanionQrScannerPage({super.key});

  @override
  State<CompanionQrScannerPage> createState() => _CompanionQrScannerPageState();
}

class _CompanionQrScannerPageState extends State<CompanionQrScannerPage>
    with WidgetsBindingObserver {
  final MobileScannerController _controller = MobileScannerController(
    autoStart: false,
    formats: <BarcodeFormat>[BarcodeFormat.qrCode],
    detectionSpeed: DetectionSpeed.noDuplicates,
  );
  bool _accepted = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(_start());
    });
  }

  Future<void> _start() async {
    if (!mounted || _accepted) return;
    try {
      await _controller.start();
    } catch (_) {
      if (mounted) {
        setState(() => _error =
            'カメラを開始できませんでした。Androidのカメラ権限を確認してください。');
      }
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(_start());
    } else {
      unawaited(_controller.stop());
    }
  }

  void _handleScan(BarcodeCapture capture) {
    if (_accepted || !mounted) return;
    for (final barcode in capture.barcodes) {
      final raw = barcode.rawValue;
      if (raw == null || raw.length > 384) continue;
      try {
        final invite = CompanionQrInvitation.parse(raw);
        _accepted = true;
        unawaited(_controller.stop());
        Navigator.of(context).pop(invite);
        return;
      } on FormatException {
        // Invalid codes cannot trigger connection or navigation.
        setState(() => _error = 'Chappy PCの有効な招待QRではありません。');
      }
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    unawaited(_controller.dispose());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Chappy PC QR読み取り')),
        body: SafeArea(
          child: Column(
            children: [
              const Padding(
                padding: EdgeInsets.all(16),
                child: Text(
                  '自分のPCに表示されたQRコードだけを読み取ってください。'
                  '接続前に、見つかったPCのIP・ポートと一致することを確認します。',
                ),
              ),
              Expanded(
                child: MobileScanner(
                  controller: _controller,
                  onDetect: _handleScan,
                ),
              ),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.all(12),
                  child: Text(
                    _error!,
                    key: const Key('qr_scan_error'),
                    style: const TextStyle(color: Colors.orangeAccent),
                  ),
                ),
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('読み取りをキャンセル'),
              ),
            ],
          ),
        ),
      );
}
