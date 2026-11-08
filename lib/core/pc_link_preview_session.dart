/// R4B offline-only future PC Link session/capability contract.
///
/// This is NOT wired to the network, QR-v3 handler, mini-app JavaScript or a
/// production permission mechanism. A boolean passed to [verify] is a fixture
/// input, NOT cryptographic evidence. Real channel binding is future R4C work.
enum PcLinkPreviewPhase {
  fresh('new'),
  verified('verified'),
  awaitingConsent('awaiting_consent'),
  active('active'),
  closed('closed');

  const PcLinkPreviewPhase(this.wire);
  final String wire;
}

class PcLinkPreviewSession {
  static const protocol = 'pc-link-session-preview-v1';
  static const readStatus = 'pc.status.read';
  static const maxLifetimeSeconds = 120;
  static const _requestFields = <String>{
    'protocol', 'kind', 'sequence', 'capability',
  };
  static const _responseFields = <String>{
    'protocol', 'kind', 'sequence', 'capability', 'online',
  };

  PcLinkPreviewSession({
    required int nowEpochSeconds,
    required int expiresAt,
  }) : _expiresAt = expiresAt {
    if (expiresAt <= nowEpochSeconds ||
        expiresAt - nowEpochSeconds > maxLifetimeSeconds) {
      throw ArgumentError('Invalid bounded preview lifetime');
    }
  }

  final int _expiresAt;
  PcLinkPreviewPhase _phase = PcLinkPreviewPhase.fresh;
  String? _requestedScope;
  bool _pcConsent = false;
  bool _androidConsent = false;
  int _lastSequence = 0;

  bool _alive(int nowEpochSeconds) {
    if (nowEpochSeconds >= _expiresAt) {
      _phase = PcLinkPreviewPhase.closed;
    }
    return _phase != PcLinkPreviewPhase.closed;
  }

  PcLinkPreviewPhase phase(int nowEpochSeconds) {
    _alive(nowEpochSeconds);
    return _phase;
  }

  bool verify({
    required bool identityVerified,
    required int nowEpochSeconds,
  }) {
    if (!_alive(nowEpochSeconds) ||
        _phase != PcLinkPreviewPhase.fresh ||
        !identityVerified) {
      cancel();
      return false;
    }
    _phase = PcLinkPreviewPhase.verified;
    // Note: successful QR verification is NOT a capability grant.
    return true;
  }

  bool requestReadOnly({
    required String capability,
    required int nowEpochSeconds,
  }) {
    if (!_alive(nowEpochSeconds) ||
        _phase != PcLinkPreviewPhase.verified ||
        capability != readStatus) {
      cancel();
      return false;
    }
    _requestedScope = capability;
    _phase = PcLinkPreviewPhase.awaitingConsent;
    return true;
  }

  bool consent({
    required String side,
    required bool approved,
    required int nowEpochSeconds,
  }) {
    if (!_alive(nowEpochSeconds) ||
        _phase != PcLinkPreviewPhase.awaitingConsent ||
        !approved ||
        (side != 'pc' && side != 'android')) {
      cancel();
      return false;
    }
    if (side == 'pc' && !_pcConsent) {
      _pcConsent = true;
    } else if (side == 'android' && !_androidConsent) {
      _androidConsent = true;
    } else {
      cancel(); // duplicate or conflicting consent
      return false;
    }
    if (_pcConsent && _androidConsent) {
      _phase = PcLinkPreviewPhase.active;
    }
    return true;
  }

  bool allows({
    required String capability,
    required int nowEpochSeconds,
  }) =>
      _alive(nowEpochSeconds) &&
      _phase == PcLinkPreviewPhase.active &&
      capability == _requestedScope &&
      capability == readStatus;

  /// Only accept a strict test fixture request after two explicit approvals.
  /// This function contains no socket, file or device access.
  Map<String, Object>? acceptFixtureRequest({
    required Map<String, dynamic> message,
    required int nowEpochSeconds,
  }) {
    if (!_alive(nowEpochSeconds) ||
        _phase != PcLinkPreviewPhase.active) {
      return null;
    }
    final seq = message['sequence'];
    if (message.keys.toSet().length != _requestFields.length ||
        !message.keys.toSet().containsAll(_requestFields) ||
        message['protocol'] != protocol ||
        message['kind'] != 'status-request' ||
        message['capability'] != readStatus ||
        seq is! int ||
        seq <= _lastSequence ||
        seq > 1000) {
      cancel();
      return null;
    }
    _lastSequence = seq;
    // Fake fixture data, never actual PC status.
    return <String, Object>{
      'protocol': protocol,
      'kind': 'status-fixture',
      'sequence': seq,
      'capability': readStatus,
      'online': true,
    };
  }

  static bool validateFixtureResponse({
    required Map<String, dynamic> message,
    required int sequence,
  }) {
    final seq = message['sequence'];
    return message.keys.toSet().length == _responseFields.length &&
        message.keys.toSet().containsAll(_responseFields) &&
        message['protocol'] == protocol &&
        message['kind'] == 'status-fixture' &&
        message['capability'] == readStatus &&
        sequence > 0 && sequence <= 1000 &&
        seq is int && seq == sequence &&
        message['online'] is bool;
  }

  /// Cancel on foreground loss, network change, user denial, or explicit stop.
  /// Never persist approval or issue credentials.
  void cancel() {
    _phase = PcLinkPreviewPhase.closed;
    _requestedScope = null;
    _pcConsent = false;
    _androidConsent = false;
  }
}
