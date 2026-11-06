import 'package:chappy_player/core/companion_pairing_client.dart';
import 'package:chappy_player/core/companion_qr_invite.dart';
import 'package:chappy_player/core/lan_discovery_client.dart';
import 'package:flutter/material.dart';

/// A one-session PC ownership confirmation; no reusable credentials.
class CompanionPairingPage extends StatefulWidget {
  final LanDiscoveredService service;
  final LanDiscoveryClient discoveryClient;
  final CompanionQrInvite? invitation;
  const CompanionPairingPage({
    super.key,
    required this.service,
    this.discoveryClient = const LanDiscoveryClient(),
    this.invitation,
  });
  @override
  State<CompanionPairingPage> createState() => _CompanionPairingPageState();
}

class _CompanionPairingPageState extends State<CompanionPairingPage>
    with WidgetsBindingObserver {
  final _fingerprint = TextEditingController();
  final _pairing = CompanionPairingClient();
  bool _busy = false;
  bool _verified = false;
  String? _code;
  String? _error;
  int _generation = 0;

  @override
  void initState() {
    super.initState();
    _fingerprint.text = widget.invitation?.fingerprint ?? '';
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) {
      _generation++;
      _pairing.cancel();
      if (mounted) {
        setState(() {
          _busy = false;
          _verified = false;
          _code = null;
        });
      }
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _generation++;
    _pairing.cancel();
    _fingerprint.dispose();
    super.dispose();
  }

  Future<void> _confirm() async {
    if (_busy || ModalRoute.of(context)?.isCurrent != true) return;
    final generation = ++_generation;
    try {
      CompanionPairingClient.validateTarget(
        widget.service.address, widget.service.port, _fingerprint.text,
      );
      if (widget.invitation?.isExpired() ?? false) {
        throw const FormatException('QRの有効期限が切れています');
      }
      if (!await widget.discoveryClient.pairingAllowed()) {
        throw StateError('Wi-Fi接続中の前面画面のみ対応しています');
      }
      if (!mounted || generation != _generation) return;
      final nonce = CompanionPairingClient.newNonce();
      final code = CompanionPairingClient.confirmationCode(nonce);
      setState(() {
        _busy = true;
        _error = null;
        _verified = false;
        _code = code;
      });
      final approved = await _pairing.confirm(
        ip: widget.service.address,
        port: widget.service.port,
        fingerprint: _fingerprint.text,
        nonce: nonce,
        invitationTicket: widget.invitation?.ticket,
        expiresAt: widget.invitation?.expiresAt,
      );
      if (!mounted || generation != _generation) return;
      setState(() {
        _verified = approved;
        _busy = false;
      });
    } catch (error) {
      if (!mounted || generation != _generation) return;
      setState(() {
        _busy = false;
        _verified = false;
        _error = '接続確認に失敗: $error';
      });
    }
  }

  void _stop() {
    _generation++;
    _pairing.cancel();
    setState(() {
      _busy = false;
      _verified = false;
      _code = null;
      _error = '確認をキャンセルしました';
    });
  }

  @override
  Widget build(BuildContext context) {
    final device = widget.service;
    return Scaffold(
      appBar: AppBar(title: const Text('Chappy PC 接続確認')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            const Text('PCとスマホを相互確認（試作版）',
                style: TextStyle(fontSize: 19, fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),
            Text(device.name, key: const Key('pair_service_name')),
            Text('接続先: ${device.address}:${device.port}'),
            const SizedBox(height: 12),
            const Text(
              'PCでChappy Companionの --start --pair を起動してください。\n'
              'PC画面に表示される証明書SHA-256指紋64文字を入力します。'
              'この指紋は毎回変わり、端末名だけでは本人確認できません。',
            ),
            if (widget.invitation != null)
              const Card(
                child: Padding(
                  padding: EdgeInsets.all(12),
                  child: Text(
                    'PC画面のQRから接続先と証明書指紋を読み取りました。'
                    '期限付き招待IDも確認要求へ含めます。'
                    '続いてPC側の6文字コードを照合してYESを入力してください。',
                    key: Key('pair_qr_imported'),
                  ),
                ),
              ),
            const SizedBox(height: 16),
            TextField(
              key: const Key('pair_fingerprint'),
              controller: _fingerprint,
              maxLength: 95,
              autocorrect: false,
              enableSuggestions: false,
              decoration: const InputDecoration(
                labelText: 'PC画面のSHA-256指紋（64桁）',
                hintText: 'abcdef...（コロン区切りも可）',
                border: OutlineInputBorder(),
              ),
              enabled: !_busy,
              readOnly: widget.invitation != null,
            ),
            FilledButton.icon(
              key: const Key('pair_confirm'),
              onPressed: _busy ? null : _confirm,
              icon: const Icon(Icons.verified_user_outlined),
              label: const Text('このPCとの接続を確認'),
            ),
            if (_busy) ...[
              const SizedBox(height: 12),
              const LinearProgressIndicator(),
              const Text('PC画面で以下のコードを確認し、YESと入力してください。'),
            ],
            if (_code != null) ...[
              const SizedBox(height: 12),
              const Text('スマホ側の確認コード'),
              SelectableText(
                _code!,
                key: const Key('pair_confirmation_code'),
                style: Theme.of(context).textTheme.headlineMedium,
              ),
            ],
            if (_busy)
              OutlinedButton.icon(
                onPressed: _stop,
                icon: const Icon(Icons.cancel_outlined),
                label: const Text('確認を中止'),
              ),
            if (_verified)
              const Card(
                child: Padding(
                  padding: EdgeInsets.all(16),
                  child: Text(
                    '証明書指紋が一致し、PC側でも確認されました。'
                    'この1回の確認だけが成功した状態です。'
                    '永続的なペアリングやPC操作権限はまだありません。',
                    key: Key('pair_verified'),
                  ),
                ),
              ),
            if (_error != null)
              SelectableText(
                _error!,
                key: const Key('pair_error'),
                style: const TextStyle(color: Colors.orangeAccent),
              ),
            const SizedBox(height: 20),
            const Text(
              '本人のPCだけに使用してください。'
              '指紋を照合せずに接続する機能はありません。'
              '通信監視・ファイル取得・遠隔操作・証明書保存は行いません。'
              'アプリが裏に回ると接続をキャンセルします。',
              style: TextStyle(fontSize: 12, color: Colors.white60),
            ),
          ],
        ),
      ),
    );
  }
}
