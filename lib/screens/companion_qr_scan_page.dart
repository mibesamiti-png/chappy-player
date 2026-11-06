import 'dart:async';

import 'package:chappy_player/core/companion_qr_invite.dart';
import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

/// Camera is started only when the user explicitly opens this trusted screen.
class CompanionQrScanPage extends StatefulWidget {
  const CompanionQrScanPage({super.key});

  @override
  State<CompanionQrScanPage> createState() => _CompanionQrScanPageState();
}

class _CompanionQrScanPageState extends State<CompanionQrScanPage>
    with WidgetsBindingObserver {
  final MobileScannerController _scanner = MobileScannerController(
    autoStart: false,
    formats: const [BarcodeFormat.qrCode],
  );
  bool _consumed = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // The caller tapped a dedicated, labeled QR camera button.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _start();
    });
  }

  void _start() {
    if (_consumed) return;
    unawaited(_scanner.start().catchError((Object error) {
      if (mounted) {
        setState(() => _error = 'カメラを起動できません: $error');
      }
    }));
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!_scanner.value.hasCameraPermission) return;
    if (state == AppLifecycleState.resumed && !_consumed) {
      _start();
    } else if (state != AppLifecycleState.resumed) {
      unawaited(_scanner.stop());
    }
  }

  void _onDetect(BarcodeCapture capture) {
    if (_consumed || !mounted) return;
    for (final barcode in capture.barcodes) {
      final raw = barcode.rawValue;
      if (raw == null) continue;
      try {
        final invite = CompanionQrInvite.parse(raw);
        _consumed = true;
        unawaited(_scanner.stop());
        Navigator.of(context).pop(invite);
        return;
      } on FormatException catch (error) {
        // Other QR codes are not links and are never auto-opened.
        if (mounted && _error != error.message) {
          setState(() => _error = error.message);
        }
      }
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _consumed = true;
    unawaited(_scanner.dispose());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('PCのQRコードを読み取る')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            const Text(
              '本人のPCで「Chappy Companion QR確認モード」を起動し、'
              'そのPC画面に表示されたQRを読み取ってください。'
              'このQRはPCへの通信を許可するものではなく、'
              '続いてPC画面側での確認が必要です。',
            ),
            const SizedBox(height: 12),
            AspectRatio(
              aspectRatio: 1,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: MobileScanner(
                  controller: _scanner,
                  onDetect: _onDetect,
                ),
              ),
            ),
            const SizedBox(height: 12),
            if (_error != null)
              Text(_error!,
                  key: const Key('qr_scan_error'),
                  style: const TextStyle(color: Colors.orangeAccent)),
            const Text(
              'カメラはQR画面の表示中だけ使い、画像は保存・送信しません。'
              'QRは専用形式以外を拒否し、IP・期限・証明書指紋・招待IDを検査します。',
              style: TextStyle(fontSize: 12, color: Colors.white60),
            ),
          ],
        ),
      ),
    );
  }
}
