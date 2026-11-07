import 'package:chappy_player/core/companion_pairing_client.dart';
import 'package:chappy_player/core/pc_pairing_failure.dart';
import 'package:chappy_player/core/companion_identity_client.dart';
import 'package:chappy_player/core/companion_identity_exchange.dart';
import 'package:chappy_player/core/verified_pc_history_client.dart';
import 'package:chappy_player/core/companion_qr_invitation.dart';
import 'package:chappy_player/screens/companion_qr_scanner_page.dart';
import 'package:chappy_player/core/lan_discovery_client.dart';
import 'package:flutter/material.dart';

/// A one-session PC ownership confirmation; no reusable credentials.
class CompanionPairingPage extends StatefulWidget {
  final LanDiscoveredService service;
  final LanDiscoveryClient discoveryClient;
  /// Explicit, read-only history access. Never an authentication decision.
  final VerifiedPcHistoryClient historyClient;
  /// Optional host-side QR reader injection for deterministic widget tests.
  final Future<CompanionQrInvitation?> Function(BuildContext)? qrReader;
  const CompanionPairingPage({
    super.key,
    required this.service,
    this.discoveryClient = const LanDiscoveryClient(),
    this.historyClient = const VerifiedPcHistoryClient(),
    this.qrReader,
  });
  @override
  State<CompanionPairingPage> createState() => _CompanionPairingPageState();
}

class _CompanionPairingPageState extends State<CompanionPairingPage>
    with WidgetsBindingObserver {
  final _fingerprint = TextEditingController();
  final _pairing = CompanionPairingClient();
  final _identityExchange = CompanionIdentityExchange();
  bool _savingHistory = false;
  // Optional user-chosen expected PC key; never selected from device names.
  String? _expectedPcFingerprint;
  // A comparison-rejected invite cannot be scanned again on this page.
  String? _rejectedQrInvitation;
  bool _savedHistory = false;
  bool _busy = false;
  bool _verified = false;
  // A QR invitation can be submitted at most once, even after failure.
  bool _qrConsumed = false;
  String? _code;
  String? _error;
  CompanionQrInvitation? _invite;
  int _generation = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) {
      _generation++;
      _pairing.cancel();
      _identityExchange.cancel();
      if (mounted) {
        setState(() {
          _busy = false;
          _savingHistory = false;
          _verified = false;
          _savedHistory = false;
          _code = null;
          _qrConsumed = false;
          _expectedPcFingerprint = null;
          // The short-lived, single-use QR cannot survive an app pause/lock.
          if (_invite != null) _fingerprint.clear();
          _invite = null;
          _error = '画面を離れたため確認を中止しました。QRは再読取してください。';
        });
      }
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _generation++;
    _pairing.cancel();
    _identityExchange.cancel();
    _fingerprint.dispose();
    super.dispose();
  }


  /// Optional user-initiated local fingerprint comparison. A remembered key
  /// has NO authority: every matching QR still needs fresh proof and consent.
  Future<void> _chooseKnownPc() async {
    if (_busy || _savingHistory || _verified || _invite != null ||
        ModalRoute.of(context)?.isCurrent != true) {
      return;
    }
    final generation = _generation;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      // No network, no pairing approval, no write to AndroidKeyStore.
      final records = await widget.historyClient.list();
      if (!mounted || generation != _generation) return;
      if (records.isEmpty) {
        setState(() => _error = '確認履歴が空です。QR-v3での相互認証後に、'
            '保存を明示承認したPCだけが表示されます。');
        return;
      }
      // The modal barrier prevents interaction with the parent page;
      // the loading animation must not run behind an open dialog.
      setState(() => _busy = false);
      final selected = await showDialog<String>(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => AlertDialog(
          title: const Text('比較するPCの公開鍵指紋を選択'),
          content: SizedBox(
            width: double.maxFinite,
            height: 300,
            child: ListView(
              children: [
                const Text(
                  '以前に確認したPCの指紋を手動選択します。'
                  '同じPC名でも鍵が変わる可能性があるため、'
                  '一致しなければ接続確認は進めません。',
                ),
                for (final record in records)
                  TextButton(
                    key: Key('pair_choose_fp_${record.fingerprint}'),
                    onPressed: () => Navigator.of(ctx).pop(record.fingerprint),
                    child: Text(
                      record.fingerprint,
                      style: const TextStyle(fontSize: 12),
                    ),
                  ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('比較しない'),
            ),
          ],
        ),
      );
      if (!mounted || generation != _generation || selected == null) return;
      setState(() {
        _expectedPcFingerprint = selected;
        _verified = false;
        _savedHistory = false;
        _code = null;
      });
    } catch (error) {
      if (!mounted || generation != _generation) return;
      setState(() => _error = '確認履歴を安全に読み込めません: $error');
    } finally {
      if (mounted && generation == _generation) {
        setState(() => _busy = false);
      }
    }
  }

  void _clearKnownPc() {
    if (_busy || _savingHistory || _verified) return;
    // Clearing an expected key must not cause a previously scanned QR to
    // become valid. Require the user to physically scan a NEW invitation.
    _generation++;
    _pairing.cancel();
    _identityExchange.cancel();
    setState(() {
      _expectedPcFingerprint = null;
      _invite = null;
      _qrConsumed = false;
      _fingerprint.clear();
      _code = null;
      _verified = false;
      _savedHistory = false;
      _error = '比較を解除しました。PCで新しいQRを表示して読み取ってください。';
    });
  }

  Future<void> _scanQr() async {
    if (_busy || ModalRoute.of(context)?.isCurrent != true) return;
    final generation = _generation;
    final invite = widget.qrReader != null
        ? await widget.qrReader!(context)
        : await Navigator.of(context).push<CompanionQrInvitation>(
            MaterialPageRoute(builder: (_) => const CompanionQrScannerPage()),
          );
    if (!mounted || generation != _generation || invite == null) return;
    if (_rejectedQrInvitation == invite.invitation) {
      setState(() {
        _invite = null;
        _fingerprint.clear();
        _qrConsumed = false;
        _code = null;
        _verified = false;
        _savedHistory = false;
        _error = 'このQR招待は公開鍵の不一致で既に拒否されました。'
            'PCで新しいQRを発行して再読取してください。';
      });
      return;
    }
    // Do not silently accept a changed key for the PC the user explicitly
    // chose from prior verified public-fingerprint history.
    if (_expectedPcFingerprint != null &&
        invite.pcIdentityFingerprint != _expectedPcFingerprint) {
      setState(() {
        _rejectedQrInvitation = invite.invitation;
        _invite = null;
        _qrConsumed = false;
        _verified = false;
        _savedHistory = false;
        _code = null;
        _fingerprint.clear();
        _error = '保存済みPCの公開鍵指紋とQRが一致しません。'
            '別PCまたは端末キー変更の可能性があります。'
            'PC側の鍵を確認してから新しいQRを発行してください。'
            '履歴の比較をやめる場合も、比較解除後に新しいQRが必要です。';
      });
      return;
    }
    // mDNS is never an identity provider. Refuse an invitation that changes
    // the endpoint selected by the user from the discovery result.
    if (invite.ip != widget.service.address ||
        invite.port != widget.service.port) {
      setState(() {
        _invite = null;
        _qrConsumed = false;
        _verified = false;
        _savedHistory = false;
        _code = null;
        _fingerprint.clear();
        _error = 'QRのPCと発見したPCの接続先が違います。再確認してください。';
      });
      return;
    }
    setState(() {
      _fingerprint.text = invite.fingerprint;
      _invite = invite;
      _qrConsumed = false;
      _code = null;
      _error = null;
      _verified = false;
      _savedHistory = false;
    });
  }

  Future<void> _confirm() async {
    if (_busy || _savingHistory ||
        ModalRoute.of(context)?.isCurrent != true) {
      return;
    }
    final generation = ++_generation;
    final invite = _invite;
    // Optional pinned-to-history check blocks manual/v1/v2 downgrades too.
    if (_expectedPcFingerprint != null &&
        invite?.pcIdentityFingerprint != _expectedPcFingerprint) {
      setState(() => _error = '保存済みのPC公開鍵指紋とQR-v3を照合してください。');
      return;
    }
    if (invite != null && _qrConsumed) return;
    // Consume the scanned one-shot invite before any awaited operation.
    // Do not allow a second attempt using the same QR even after an error.
    if (invite != null) _qrConsumed = true;
    // Lock the page before the first await so another QR cannot replace
    // this invitation while Wi-Fi eligibility is being checked.
    setState(() {
      _busy = true;
      _verified = false;
      _savedHistory = false;
      _error = null;
      _code = null;
    });
    try {
      CompanionPairingClient.validateTarget(
        widget.service.address, widget.service.port, _fingerprint.text,
      );
      if (invite != null) {
        final current = DateTime.now().millisecondsSinceEpoch ~/ 1000;
        if (invite.expiresUnix <= current ||
            invite.fingerprint != _fingerprint.text) {
          throw const FormatException('QR招待の期限が切れたか内容が変更されました');
        }
      }
      if (!await widget.discoveryClient.pairingAllowed()) {
        throw StateError('Wi-Fi接続中の前面画面のみ対応しています');
      }
      if (!mounted || generation != _generation) return;
      final identityMode = invite?.pcIdentityFingerprint != null;
      final nonce = identityMode
          ? CompanionIdentityClient.newNonce()
          : CompanionPairingClient.newNonce();
      final code = identityMode
          ? CompanionIdentityClient.confirmationCode(nonce)
          : CompanionPairingClient.confirmationCode(nonce);
      setState(() {
        _busy = true;
        _error = null;
        _verified = false;
        _savedHistory = false;
        _code = code;
      });
      final approved = identityMode
          ? await _identityExchange.confirm(
              ip: widget.service.address,
              port: widget.service.port,
              tlsFingerprint: _fingerprint.text,
              pcFingerprint: invite!.pcIdentityFingerprint!,
              invitation: invite.invitation,
              qrExpires: invite.expiresUnix,
              phoneNonce: nonce,
              approvePhoneProof: () async {
                if (!mounted || generation != _generation ||
                    ModalRoute.of(context)?.isCurrent != true) {
                  return false;
                }
                final consent = await showDialog<bool>(
                  context: context,
                  barrierDismissible: false,
                  builder: (dialogContext) => AlertDialog(
                    title: const Text('PCの端末鍵を確認しました'),
                    content: Text(
                      'QRで指定したPCの署名を検証できました。\n'
                      'PC公開鍵SHA-256:\n${invite.pcIdentityFingerprint!}\n\n'
                      'このスマホの秘密鍵で使い捨ての認証要求に'
                      '署名してPCへ返しますか？'
                      '永続登録やPC操作の許可はまだ行われません。',
                    ),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.of(dialogContext).pop(false),
                        child: const Text('拒否する'),
                      ),
                      FilledButton(
                        onPressed: () => Navigator.of(dialogContext).pop(true),
                        child: const Text('この1回だけ署名する'),
                      ),
                    ],
                  ),
                );
                return consent == true && mounted &&
                    generation == _generation;
              },
            )
          : await _pairing.confirm(
              ip: widget.service.address,
              port: widget.service.port,
              fingerprint: _fingerprint.text,
              nonce: nonce,
              invitation: invite?.invitation,
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
        _error = PcPairingFailure.classify(error).safeMessage;
      });
    }
  }

  Future<void> _rememberPc() async {
    final fp = _invite?.pcIdentityFingerprint;
    if (_busy || _savingHistory || _savedHistory || !_verified ||
        fp == null || ModalRoute.of(context)?.isCurrent != true) {
      return;
    }
    final generation = _generation;
    final consent = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: const Text('PCの確認履歴を記録'),
        content: Text(
          'QR-v3で署名を確認したPCの公開鍵指紋を、'
          'このスマホに暗号化して保存しますか？\n'
          '$fp\n\n'
          '保存はメモだけです。自動接続、PC操作、通信監視の'
          '許可にはなりません。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('保存しない'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('確認履歴だけ保存'),
          ),
        ],
      ),
    );
    if (!mounted || consent != true || generation != _generation ||
        !_verified || fp != _invite?.pcIdentityFingerprint ||
        ModalRoute.of(context)?.isCurrent != true) {
      return;
    }
    setState(() {
      _savingHistory = true;
      _error = null;
    });
    try {
      await widget.historyClient.remember(fp);
      if (!mounted || generation != _generation) return;
      setState(() => _savedHistory = true);
    } catch (error) {
      if (!mounted || generation != _generation) return;
      setState(() => _error = '確認履歴を保存できません: $error');
    } finally {
      if (mounted && generation == _generation) {
        setState(() => _savingHistory = false);
      }
    }
  }

  void _stop() {
    _generation++;
    _pairing.cancel();
    _identityExchange.cancel();
    setState(() {
      _busy = false;
      _savingHistory = false;
      _verified = false;
      _savedHistory = false;
      _code = null;
      // A cancelled QR challenge must never be re-used.
      if (_invite != null) _fingerprint.clear();
      _invite = null;
      _qrConsumed = false;
      _expectedPcFingerprint = null;
      _error = '確認をキャンセルしました。QRは再読取してください。';
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
              'QR-v3の端末相互認証はPCで'
              ' --start --pair --qr --identity-pair を起動。\n'
              '旧QR-v2は --start --pair --qr を起動。\n'
              '旧手入力モードの場合は --start --pair で起動してください。\n'
              'PC画面に表示される証明書SHA-256指紋64文字を入力します。'
              'この指紋は毎回変わり、端末名だけでは本人確認できません。',
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              key: const Key('pair_choose_known_pc'),
              onPressed: _busy || _savingHistory || _verified ||
                      _invite != null
                  ? null : _chooseKnownPc,
              icon: const Icon(Icons.fact_check_outlined),
              label: const Text('以前確認したPCの公開鍵指紋を選んで照合'),
            ),
            if (_expectedPcFingerprint != null) ...[
              const SizedBox(height: 8),
              const Text('今回のQR-v3に期待するPC公開鍵指紋：'),
              SelectableText(
                _expectedPcFingerprint!,
                key: const Key('pair_expected_pc_fingerprint'),
              ),
              const Text(
                '一致しても自動接続・端末の信頼登録はしません。'
                '必ず新しいQRとPCのYES、双方の署名確認が必要です。',
              ),
              TextButton(
                key: const Key('pair_clear_known_pc'),
                onPressed: _busy || _savingHistory || _verified
                    ? null : _clearKnownPc,
                child: const Text('過去の指紋との比較を解除（次は新しいQRが必要）'),
              ),
            ],
            const SizedBox(height: 8),
            OutlinedButton.icon(
              key: const Key('pair_scan_qr'),
              onPressed: _busy || _savingHistory ? null : _scanQr,
              icon: const Icon(Icons.qr_code_scanner),
              label: const Text('PCの招待QRをカメラで読み取る'),
            ),
            if (_expectedPcFingerprint != null &&
                _invite?.pcIdentityFingerprint == _expectedPcFingerprint)
              const Text(
                '選択した保存済みPCの指紋とQRが一致。'
                'ただし本人認証は未完了です。',
                key: Key('pair_known_pc_matched'),
              ),
            if (_invite != null)
              Text(
                _invite!.pcIdentityFingerprint != null
                    ? 'QR-v3：PC固有の端末鍵を双方の署名で確認します。'
                    : 'QR-v2：1回だけPCの承認を確認します。',
                key: const Key('pair_qr_mode'),
              ),
            const SizedBox(height: 16),
            TextField(
              key: const Key('pair_fingerprint'),
              controller: _fingerprint,
              onChanged: (_) {
                setState(() {
                  _invite = null;
                  _qrConsumed = false;
                  _verified = false;
                  _savedHistory = false;
                  _code = null;
                });
              },
              maxLength: 95,
              autocorrect: false,
              enableSuggestions: false,
              decoration: const InputDecoration(
                labelText: 'PC画面のSHA-256指紋（64桁）',
                hintText: 'abcdef...（コロン区切りも可）',
                border: OutlineInputBorder(),
              ),
              enabled: !_busy && !_savingHistory,
            ),
            FilledButton.icon(
              key: const Key('pair_confirm'),
              onPressed: _busy || _savingHistory ||
                  (_invite != null && _qrConsumed) ||
                  (_expectedPcFingerprint != null &&
                   _invite?.pcIdentityFingerprint != _expectedPcFingerprint)
                  ? null : _confirm,
              icon: const Icon(Icons.verified_user_outlined),
              label: const Text('このPCとの接続を確認'),
            ),
            if (_invite != null && _qrConsumed && !_busy)
              const Text(
                'このQRは一度使用しました。再確認にはPCで新しいQRを表示して再読取してください。',
                key: Key('pair_qr_consumed'),
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
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(
                    _invite?.pcIdentityFingerprint == null
                        ? '証明書指紋が一致し、PC側でも確認されました。'
                          'この1回の確認だけが成功した状態です。'
                          '永続的なペアリングやPC操作権限はまだありません。'
                        : 'PCとAndroid双方の署名が検証されました。'
                          '認証はこの1回限り。'
                          '信頼済み端末としての保存やPC操作権限はまだありません。',
                    key: const Key('pair_verified'),
                  ),
                ),
              ),
            if (_verified && _invite?.pcIdentityFingerprint != null) ...[
              const SizedBox(height: 10),
              OutlinedButton.icon(
                key: const Key('pair_save_verified_pc'),
                onPressed: _savedHistory || _savingHistory
                    ? null
                    : _rememberPc,
                icon: const Icon(Icons.bookmark_add_outlined),
                label: const Text('このPCの公開鍵を確認履歴に記録'),
              ),
              if (_savedHistory)
                const Text(
                  'このスマホに暗号化して記録しました（接続権限なし）。',
                  key: Key('pair_verified_pc_saved'),
                ),
            ],
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
