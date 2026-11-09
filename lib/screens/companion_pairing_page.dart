import 'package:chappy_player/core/companion_pairing_client.dart';
import 'package:chappy_player/core/pc_pairing_failure.dart';
import 'package:chappy_player/core/pc_pairing_stage.dart';
import 'package:chappy_player/core/pc_pairing_diagnostic_report.dart';
import 'package:chappy_player/core/pc_pairing_recovery_guidance.dart';
import 'package:flutter/services.dart';
import 'package:chappy_player/core/companion_identity_client.dart';
import 'package:chappy_player/core/companion_identity_exchange.dart';
import 'package:chappy_player/core/pc_status_once.dart';
import 'package:chappy_player/core/remote_traffic_report.dart';
import 'package:chappy_player/core/pc_file_upload.dart';
import 'package:chappy_player/core/pc_media_once.dart';
import 'package:file_picker/file_picker.dart';
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
  bool _trafficAttempted = false;
  RemoteTrafficReport? _trafficReport;
  bool _statusAttempted = false;
  PcStatusOnceMetrics? _statusMetrics;
  bool _mediaAttempted = false;
  String? _mediaMessage;
  bool _fileAttempted = false;
  bool _fileSaving = false;
  double _fileProgress = 0;
  String? _fileMessage;
  bool _uploadAttempted = false;
  double _uploadProgress = 0;
  String? _uploadMessage;
  // A QR invitation can be submitted at most once, even after failure.
  bool _qrConsumed = false;
  String? _code;
  String? _error;
  // Visible progress only; never persisted or used for authentication.
  PcPairingStage? _progressStage;
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
      // Android's Save As may briefly pause the app AFTER transfer completes.
      if (_fileSaving) return;
      _generation++;
      _pairing.cancel();
      _identityExchange.cancel();
      if (mounted) {
        setState(() {
          _busy = false;
          _savingHistory = false;
          _verified = false;
          _statusMetrics = null;
          _statusAttempted = false;
          _trafficReport = null;
          _trafficAttempted = false;
          _mediaAttempted = false;
          _mediaMessage = null;
          _fileAttempted = false;
          _fileProgress = 0;
          _fileMessage = null;
          _uploadAttempted = false;
          _uploadProgress = 0;
          _uploadMessage = null;
          _savedHistory = false;
          _code = null;
          _progressStage = null;
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
      setState(() => _error = '確認履歴を安全に読み込めません [HISTORY-READ]。端末の保存状態を確認してください。');
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
      _uploadAttempted = false;
      _uploadProgress = 0;
      _uploadMessage = null;
      _statusMetrics = null;
      _statusAttempted = false;
      _trafficReport = null;
      _trafficAttempted = false;
      _mediaAttempted = false;
      _mediaMessage = null;
      _fileAttempted = false;
      _fileProgress = 0;
      _fileMessage = null;
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
    // Attempt-local diagnostic only; never persisted or used for trust.
    var stage = PcPairingStage.qr;
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
      _statusMetrics = null;
      _statusAttempted = false;
      _trafficReport = null;
      _trafficAttempted = false;
      _mediaAttempted = false;
      _mediaMessage = null;
      _fileAttempted = false;
      _fileProgress = 0;
      _fileMessage = null;
      _savedHistory = false;
      _error = null;
      _code = null;
      _progressStage = PcPairingStage.qr;
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
      stage = identityMode ? PcPairingStage.identity : PcPairingStage.network;
      setState(() => _progressStage = stage);
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
              onStage: (current) {
                stage = current;
                if (mounted && generation == _generation && _busy) {
                  setState(() => _progressStage = current);
                }
              },
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
        _progressStage = null;
      });
    } catch (error) {
      if (!mounted || generation != _generation) return;
      setState(() {
        _busy = false;
        _verified = false;
        _progressStage = null;
        _error = '${stage.safeSummary}。'
            '${PcPairingFailure.classify(error).safeMessage}';
      });
    }
  }

  Future<void> _readTrafficOnce() async {
    final invite = _invite;
    if (_busy || _savingHistory || !_verified || _trafficAttempted ||
        invite == null || !invite.trafficOnce ||
        invite.pcIdentityFingerprint == null ||
        ModalRoute.of(context)?.isCurrent != true) {
      return;
    }
    final generation = ++_generation;
    setState(() {
      _busy = true;
      _trafficAttempted = true; // Consumed before any await or Wi-Fi access.
      _trafficReport = null;
      _error = null;
    });
    try {
      if (!await widget.discoveryClient.trafficPairingAllowed()) {
        throw StateError('本人PCとのWi-Fi接続がありません');
      }
      if (!mounted || generation != _generation) return;
      final result = await _identityExchange.readPcTrafficOnce(
        ip: widget.service.address,
        port: widget.service.port,
        tlsFingerprint: invite.fingerprint,
        pcFingerprint: invite.pcIdentityFingerprint!,
        invitation: invite.invitation,
        qrExpires: invite.expiresUnix,
        approvePhoneTraffic: (seconds) async {
          if (!mounted || generation != _generation ||
              ModalRoute.of(context)?.isCurrent != true ||
              !await widget.discoveryClient.trafficPairingAllowed()) {
            return false;
          }
          if (!mounted || generation != _generation) return false;
          final ok = await showDialog<bool>(
            context: context,
            barrierDismissible: false,
            builder: (ctx) => AlertDialog(
              title: const Text('このPCの通信量を今回だけ取得しますか？'),
              content: Text(
                'Windows本人のTRAFFIC別承認と、専用PC署名を確認しました。\n\n'
                '計測: $seconds秒 / 全ネットワークアダプター合計の送受信量。\n'
                'Wi-Fiだけの通信量とは限りません。'
                '通信先、IP、SSID、パケット内容、ほかの端末の情報は取得しません。'
                '保存や継続監視も行いません。',
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx, false),
                  child: const Text('拒否する'),
                ),
                FilledButton(
                  onPressed: () => Navigator.pop(ctx, true),
                  child: const Text('今回だけ計測して取得'),
                ),
              ],
            ),
          );
          return ok == true && mounted && generation == _generation &&
              ModalRoute.of(context)?.isCurrent == true &&
              await widget.discoveryClient.trafficPairingAllowed();
        },
      );
      if (!mounted || generation != _generation ||
          ModalRoute.of(context)?.isCurrent != true) {
        return;
      }
      if (!await widget.discoveryClient.trafficPairingAllowed()) {
        throw StateError('ネットワーク経路が変わりました');
      }
      if (!mounted || generation != _generation) {
        return;
      }
      setState(() => _trafficReport = result);
    } catch (_) {
      if (mounted && generation == _generation) {
        setState(() => _error = 'PC通信量の直接取得に失敗しました [TRAFFIC-ONCE]。'
            'Wi-Fi・本人確認・TRAFFIC別承認・期限を確認し、新しいQRを発行してください。');
      }
    } finally {
      if (mounted && generation == _generation) {
        setState(() => _busy = false);
      }
    }
  }

  static String _trafficBytes(num value) {
    var scaled = value.toDouble();
    const units = ['B', 'KiB', 'MiB', 'GiB', 'TiB'];
    var idx = 0;
    while (scaled >= 1024 && idx < units.length - 1) {
      scaled /= 1024;
      idx++;
    }
    return '${scaled.toStringAsFixed(idx == 0 ? 0 : 1)} ${units[idx]}';
  }

  Future<void> _readStatusOnce() async {
    final invite = _invite;
    if (_busy || !_verified || _statusAttempted ||
        invite == null || !invite.statusOnce ||
        invite.pcIdentityFingerprint == null ||
        ModalRoute.of(context)?.isCurrent != true) {
      return;
    }
    final generation = ++_generation;
    setState(() {
      _busy = true;
      _statusAttempted = true;
      _statusMetrics = null;
      _error = null;
    });
    try {
      final metrics = await _identityExchange.readStatusOnce(
        ip: widget.service.address,
        port: widget.service.port,
        tlsFingerprint: invite.fingerprint,
        pcFingerprint: invite.pcIdentityFingerprint!,
        invitation: invite.invitation,
        qrExpires: invite.expiresUnix,
        approvePhoneStatus: () async {
          if (!mounted || generation != _generation ||
              ModalRoute.of(context)?.isCurrent != true) {
            return false;
          }
          final approved = await showDialog<bool>(
            context: context,
            barrierDismissible: false,
            builder: (ctx) => AlertDialog(
              title: const Text('PC状態を今回だけ読み取りますか？'),
              content: const Text(
                'PCで本人確認とは別のSTATUS承認を行った後、'
                'PCの専用署名を検証しました。\n\n'
                'CPU論理コア数、メモリ合計・空き容量、起動時間だけを'
                'この1回取得します。ファイル・アプリ・通信内容・'
                'PC操作は対象外です。表示は保存しません。',
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx, false),
                  child: const Text('拒否する'),
                ),
                FilledButton(
                  onPressed: () => Navigator.pop(ctx, true),
                  child: const Text('この1回だけ取得'),
                ),
              ],
            ),
          );
          return approved == true && mounted && generation == _generation;
        },
      );
      if (!mounted || generation != _generation) return;
      setState(() => _statusMetrics = metrics);
    } catch (_) {
      if (!mounted || generation != _generation) return;
      setState(() => _error = 'PC状態を取得できませんでした [STATUS-ONCE]。'
          '別承認の拒否・署名違い・期限切れ・切断を確認して、'
          '新しいQRを発行してください。');
    } finally {
      if (mounted && generation == _generation) {
        setState(() => _busy = false);
      }
    }
  }

  Future<void> _executeMediaOnce(String command) async {
    final invite = _invite;
    if (_busy || _savingHistory || !_verified || _mediaAttempted ||
        invite == null || !invite.mediaOnce ||
        invite.pcIdentityFingerprint == null ||
        ModalRoute.of(context)?.isCurrent != true) {
      return;
    }
    final generation = ++_generation;
    setState(() {
      _busy = true;
      _mediaAttempted = true; // Consume before awaiting; no QR reuse.
      _mediaMessage = null;
      _error = null;
    });
    try {
      await _identityExchange.executePcMediaOnce(
        ip: widget.service.address,
        port: widget.service.port,
        tlsFingerprint: invite.fingerprint,
        pcFingerprint: invite.pcIdentityFingerprint!,
        invitation: invite.invitation,
        qrExpires: invite.expiresUnix,
        command: command,
        approvePhoneMedia: (exactCommand) async {
          if (!mounted || generation != _generation ||
              ModalRoute.of(context)?.isCurrent != true) {
            return false;
          }
          final approved = await showDialog<bool>(
            context: context,
            barrierDismissible: false,
            builder: (ctx) => AlertDialog(
              title: const Text('PCのメディア操作を1回だけ許可しますか？'),
              content: Text(
                'PC側で本人確認と別のCONTROL承認を行い、'
                '操作を限定したPC署名を検証しました。\n\n'
                '操作: ${PcMediaOnce.label(exactCommand)}\n\n'
                'この1キーだけ実行します。任意のキー入力、'
                'ファイルアクセスや継続的なPC制御は許可しません。',
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx, false),
                  child: const Text('拒否する'),
                ),
                FilledButton(
                  onPressed: () => Navigator.pop(ctx, true),
                  child: const Text('この1回だけ実行'),
                ),
              ],
            ),
          );
          return approved == true && mounted && generation == _generation;
        },
      );
      if (!mounted || generation != _generation) return;
      setState(() => _mediaMessage =
          '${PcMediaOnce.label(command)}：PC側から実行応答を受信しました。');
    } catch (_) {
      if (mounted && generation == _generation) {
        setState(() => _error = 'PCメディア操作に失敗しました [MEDIA-ONCE]。'
            'PC側で新しいQRを表示して承認と期限を再確認してください。');
      }
    } finally {
      if (mounted && generation == _generation) {
        setState(() => _busy = false);
      }
    }
  }

  /// This short-lived transfer scope never grants files to mini-app JavaScript.
  Future<void> _receiveFileOnce() async {
    final invite = _invite;
    if (_busy || _savingHistory || !_verified || _fileAttempted ||
        invite == null || !invite.fileOnce ||
        invite.pcIdentityFingerprint == null ||
        ModalRoute.of(context)?.isCurrent != true) {
      return;
    }
    final generation = ++_generation;
    setState(() {
      _busy = true;
      _fileAttempted = true;
      _fileProgress = 0;
      _fileMessage = null;
      _error = null;
    });
    try {
      final received = await _identityExchange.receivePcFileOnce(
        ip: widget.service.address,
        port: widget.service.port,
        tlsFingerprint: invite.fingerprint,
        pcFingerprint: invite.pcIdentityFingerprint!,
        invitation: invite.invitation,
        qrExpires: invite.expiresUnix,
        approvePhoneFile: (offer) async {
          if (!mounted || generation != _generation ||
              ModalRoute.of(context)?.isCurrent != true) {
            return false;
          }
          final answer = await showDialog<bool>(
            context: context,
            barrierDismissible: false,
            builder: (ctx) => AlertDialog(
              title: const Text('PCで選択されたファイルを1回だけ受信'),
              content: Text(
                'Windows側でYESと別のSEND承認が済み、'
                '専用のPC署名を検証しました。\n\n'
                'ファイル名: ${offer.fileName}\n'
                '容量: ${offer.sizeBytes} バイト（最大4MiB）\n\n'
                '受信後にSHA-256を検証して、'
                'Androidの標準保存画面で保存先を選びます。'
                '他のPCファイルやフォルダにはアクセスできません。',
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx, false),
                  child: const Text('拒否する'),
                ),
                FilledButton(
                  onPressed: () => Navigator.pop(ctx, true),
                  child: const Text('この1ファイルだけ受信'),
                ),
              ],
            ),
          );
          return answer == true && mounted && generation == _generation;
        },
        onProgress: (count, total) {
          if (mounted && generation == _generation) {
            setState(() => _fileProgress = count / total);
          }
        },
      );
      if (!mounted || generation != _generation) return;
      // Network session has ended. Only the verified 4 MiB buffer enters SAF.
      setState(() {
        _fileSaving = true;
        _fileProgress = 1;
      });
      final destination = await FilePicker.platform.saveFile(
        dialogTitle: 'PCから受信したファイルを保存',
        fileName: received.offer.fileName,
        bytes: received.bytes,
      );
      if (!mounted || generation != _generation) return;
      setState(() => _fileMessage = destination == null
          ? '保存をキャンセルしました。再転送には新しいQRが必要です。'
          : 'SHA-256を確認して、選択した保存先に保存しました。');
    } catch (_) {
      if (mounted && generation == _generation) {
        setState(() => _error = 'PCファイル受信を完了できませんでした [FILE-ONCE]。'
            '容量・署名・期限・接続・保存先の許可を確認して、'
            'Windowsで新しいQRを発行してください。');
      }
    } finally {
      if (mounted && generation == _generation) {
        setState(() {
          _fileSaving = false;
          _busy = false;
        });
      }
    }
  }

  /// Trusted host-only file selection, never a mini-app JS capability.
  Future<void> _uploadFileOnce() async {
    final invite = _invite;
    if (_busy || _savingHistory || !_verified || _uploadAttempted ||
        invite == null || !invite.uploadOnce ||
        invite.pcIdentityFingerprint == null ||
        ModalRoute.of(context)?.isCurrent != true) {
      return;
    }
    final generation = ++_generation;
    setState(() {
      _busy = true;
      _uploadAttempted = true;
      _uploadProgress = 0;
      _uploadMessage = null;
      _error = null;
    });
    try {
      final selection = await FilePicker.platform.pickFiles(
        dialogTitle: 'Windowsに送信する1ファイル（最大4MiB）',
        type: FileType.any,
        allowMultiple: false,
        withData: true,
      );
      if (!mounted || generation != _generation) return;
      if (selection == null || selection.files.length != 1) {
        setState(() => _uploadMessage = '選択をキャンセルしました。次は新しいQRを発行してください。');
        return;
      }
      final selected = selection.files.single;
      if (selected.bytes == null) {
        throw StateError('選択ファイルを読み取れません');
      }
      final file = PcUploadFile(fileName: selected.name, bytes: selected.bytes!);
      await _identityExchange.uploadPcFileOnce(
        ip: widget.service.address,
        port: widget.service.port,
        tlsFingerprint: invite.fingerprint,
        pcFingerprint: invite.pcIdentityFingerprint!,
        invitation: invite.invitation,
        qrExpires: invite.expiresUnix,
        file: file,
        approvePhoneUpload: (offered) async {
          if (!mounted || generation != _generation ||
              ModalRoute.of(context)?.isCurrent != true) {
            return false;
          }
          final approved = await showDialog<bool>(
            context: context,
            barrierDismissible: false,
            builder: (ctx) => AlertDialog(
              title: const Text('1ファイルをWindowsに送信'),
              content: Text(
                'PCのQR-v3 YESと追加のRECEIVEが済み、'
                '送信専用署名が確認できました。\n\n'
                'ファイル名: ${offered.fileName}\n'
                '容量: ${offered.bytes.length} バイト\n\n'
                'Windowsで事前指定された同名の新規ファイルにだけ保存します。'
                '既存ファイルへの上書きは禁止。最大4MiB、1回限りです。',
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx, false),
                  child: const Text('拒否する'),
                ),
                FilledButton(
                  onPressed: () => Navigator.pop(ctx, true),
                  child: const Text('この1ファイルを送信'),
                ),
              ],
            ),
          );
          return approved == true && mounted && generation == _generation;
        },
        onProgress: (sent, total) {
          if (mounted && generation == _generation) {
            setState(() => _uploadProgress = sent / total);
          }
        },
      );
      if (!mounted || generation != _generation) return;
      setState(() => _uploadMessage = 'Windowsで新規保存とSHA-256の照合が完了しました。');
    } catch (_) {
      if (mounted && generation == _generation) {
        setState(() => _error = 'PCファイル送信に失敗しました [UPLOAD-ONCE]。'
            'ファイル名・容量・承認・接続を確認し、Windowsで新しいQRを発行してください。');
      }
    } finally {
      if (mounted && generation == _generation) {
        setState(() => _busy = false);
      }
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
      setState(() => _error = '確認履歴を保存できません [HISTORY-SAVE]。端末の保存状態を確認してください。');
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
      _statusMetrics = null;
      _statusAttempted = false;
      _trafficReport = null;
      _trafficAttempted = false;
      _mediaAttempted = false;
      _mediaMessage = null;
      _fileAttempted = false;
      _fileSaving = false;
      _fileProgress = 0;
      _fileMessage = null;
      _savedHistory = false;
      _code = null;
      _progressStage = null;
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
              '最新のQR-v3相互認証はWindowsで'
              ' Start-ChappyPairingV3.cmd を起動してください。\n'
              'PCの端末鍵が未作成なら、先に'
              ' Start-ChappyIdentitySetup.cmd で明示的に準備します。\n'
              '以前確認したスマホ鍵を比較する場合は'
              ' Start-ChappyKnownPhoneV3.cmd を使えます。\n'
              '旧QR-v2のStart-ChappyPairing.cmdとは別モードです。\n'
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
                  _trafficReport = null;
                  _trafficAttempted = false;
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
              if (_progressStage != null)
                Text(
                  '確認中：${_progressStage!.label} [${_progressStage!.code}]',
                  key: const Key('pair_progress_stage'),
                ),
              const Text('PC側の確認画面とコードを照合してください。'
                  '端末署名の承認が必要な場合は別画面で確認します。'),
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
            if (_verified && _invite?.mediaOnce == true) ...[
              const SizedBox(height: 8),
              const Text('新しいQRで1つだけ実行できます。PCとスマホでそれぞれ追加承認が必要です。'),
              for (final command in PcMediaOnce.commands)
                OutlinedButton.icon(
                  key: Key('pair_media_$command'),
                  onPressed: _busy || _mediaAttempted
                      ? null : () => _executeMediaOnce(command),
                  icon: const Icon(Icons.music_note_outlined),
                  label: Text('PCの${PcMediaOnce.label(command)}'),
                ),
              if (_mediaMessage != null)
                Text(_mediaMessage!, key: const Key('pair_media_result')),
            ],
            if (_verified && _invite?.uploadOnce == true) ...[
              const SizedBox(height: 8),
              OutlinedButton.icon(
                key: const Key('pair_upload_once'),
                onPressed: _busy || _uploadAttempted ? null : _uploadFileOnce,
                icon: const Icon(Icons.upload_file_outlined),
                label: const Text('Windowsへ1ファイルを送信（追加承認）'),
              ),
              if (_busy && _uploadAttempted)
                LinearProgressIndicator(value: _uploadProgress),
              if (_uploadMessage != null)
                Text(_uploadMessage!, key: const Key('pair_upload_result')),
            ],
            if (_verified && _invite?.fileOnce == true) ...[
              const SizedBox(height: 8),
              OutlinedButton.icon(
                key: const Key('pair_file_once'),
                onPressed: _busy || _fileAttempted ? null : _receiveFileOnce,
                icon: const Icon(Icons.file_download_outlined),
                label: const Text('PCで選択した1ファイルを受信する'),
              ),
              if (_busy && _fileAttempted)
                LinearProgressIndicator(value: _fileProgress),
              if (_fileMessage != null)
                Text(_fileMessage!, key: const Key('pair_file_result')),
            ],
            if (_verified && _invite?.trafficOnce == true) ...[
              const SizedBox(height: 8),
              const Text('NETLAB-04B: 本人Windows PCの通信カウンターのみ。'
                  '毎回QR-v3相互署名、Windows TRAFFIC、Android別承認が必要です。'),
              OutlinedButton.icon(
                key: const Key('pair_traffic_once'),
                onPressed: _busy || _trafficAttempted ? null : _readTrafficOnce,
                icon: const Icon(Icons.network_check_outlined),
                label: const Text('追加承認してPC通信量を1回だけ直接取得'),
              ),
              if (_trafficReport != null)
                Card(
                  key: const Key('pair_traffic_card'),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('PC通信量（RAMのみ・全アダプター合計）'),
                        Text('計測: ${_trafficReport!.seconds}秒'),
                        Text('受信合計: ${_trafficBytes(_trafficReport!.totalRxBytes)}'),
                        Text('送信合計: ${_trafficBytes(_trafficReport!.totalTxBytes)}'),
                        Text('平均受信/秒: ${_trafficBytes(_trafficReport!.avgRxBytesPerSecond)}'),
                        Text('平均送信/秒: ${_trafficBytes(_trafficReport!.avgTxBytesPerSecond)}'),
                        Text('最大受信/秒: ${_trafficBytes(_trafficReport!.peakRxBytesPerSecond)}'),
                        Text('最大送信/秒: ${_trafficBytes(_trafficReport!.peakTxBytesPerSecond)}'),
                        const SizedBox(height: 8),
                        const Text('受信推移（1秒間隔）'),
                        for (final point in _trafficReport!.samples)
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 3),
                            child: LinearProgressIndicator(
                              value: _trafficReport!.peakRxBytesPerSecond == 0
                                  ? 0.0
                                  : point.rxBytes /
                                      _trafficReport!.peakRxBytesPerSecond,
                              minHeight: 8,
                            ),
                          ),
                        TextButton.icon(
                          key: const Key('pair_traffic_clear'),
                          onPressed: () => setState(() => _trafficReport = null),
                          icon: const Icon(Icons.delete_outline),
                          label: const Text('通信量の結果を消去'),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
            if (_verified && _invite?.statusOnce == true) ...[
              OutlinedButton.icon(
                key: const Key('pair_status_once'),
                onPressed: _busy || _statusAttempted ? null : _readStatusOnce,
                icon: const Icon(Icons.memory_outlined),
                label: const Text('追加承認してPCの状態を一度だけ読む'),
              ),
              if (_statusMetrics != null)
                Card(
                  key: const Key('pair_status_card'),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('取得したPC状態（保存なし）'),
                        Text('論理CPU: ${_statusMetrics!.logicalCpusText}'),
                        Text('メモリ合計: ${_statusMetrics!.memoryTotalText}'),
                        Text('メモリ空き: ${_statusMetrics!.memoryAvailableText}'),
                        Text('起動時間: ${_statusMetrics!.uptimeText}'),
                      ],
                    ),
                  ),
                ),
            ],
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
            if (_error != null) ...[
              SelectableText(
                _error!,
                key: const Key('pair_error'),
                style: const TextStyle(color: Colors.orangeAccent),
              ),
              if (PcPairingRecoveryGuidance.fromMessage(_error!) case final hint?)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    '次に確認すること：$hint',
                    key: const Key('pair_recovery_hint'),
                  ),
                ),
              if (PcPairingDiagnosticReport.fromMessage(_error!) case final report?)
                TextButton.icon(
                  key: const Key('pair_copy_diagnostic'),
                  icon: const Icon(Icons.copy_outlined),
                  label: const Text('診断コードだけをコピー'),
                  onPressed: () async {
                    await Clipboard.setData(ClipboardData(text: report));
                    if (!context.mounted) return;
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('秘密情報を含まない診断コードをコピーしました')),
                    );
                  },
                ),
            ],
            const SizedBox(height: 20),
            const Text(
              '本人のPCだけに使用してください。'
              '指紋を照合せずに接続する機能はありません。'
              '無断監視・任意のPC操作・証明書保存は行いません。'
              'アプリが裏に回ると接続をキャンセルします。',
              style: TextStyle(fontSize: 12, color: Colors.white60),
            ),
          ],
        ),
      ),
    );
  }
}
