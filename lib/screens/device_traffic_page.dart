import 'dart:async';
import 'dart:math' as math;

import 'package:chappy_player/core/device_traffic_client.dart';
import 'package:flutter/material.dart';

/// Trusted host UI; the .chappy runtime cannot start or read this monitor.
/// No history is saved and collection stops on navigation or backgrounding.
class DeviceTrafficPage extends StatefulWidget {
  final DeviceTrafficClient client;

  const DeviceTrafficPage({
    super.key,
    this.client = const DeviceTrafficClient(),
  });

  @override
  State<DeviceTrafficPage> createState() => _DeviceTrafficPageState();
}

class _DeviceTrafficPageState extends State<DeviceTrafficPage>
    with WidgetsBindingObserver {
  static const _sessionLength = Duration(seconds: 60);
  static const _sampleInterval = Duration(seconds: 1);
  static const _maxSamples = 60;

  Timer? _timer;
  Timer? _deadline;
  DeviceTrafficSnapshot? _first;
  DeviceTrafficSnapshot? _last;
  DeviceTrafficRate? _rate;
  final List<DeviceTrafficRate> _history = <DeviceTrafficRate>[];
  bool _running = false;
  bool _sampling = false;
  int _generation = 0;
  String? _error;
  String? _notice;
  DateTime? _expires;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) {
      _stop('バックグラウンド移行のため計測を停止しました');
    }
  }

  void _stop([String? reason]) {
    _generation++;
    _timer?.cancel();
    _timer = null;
    _deadline?.cancel();
    _deadline = null;
    _expires = null;
    final wasRunning = _running;
    _running = false;
    if (mounted && (wasRunning || reason != null)) {
      setState(() {
        if (reason != null) _notice = reason;
      });
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _generation++;
    _timer?.cancel();
    _deadline?.cancel();
    _running = false;
    super.dispose();
  }

  Future<void> _start() async {
    if (_running) return;
    final accepted = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialog) => AlertDialog(
        title: const Text('このスマホの通信量を測定'),
        content: const Text(
          'Androidの端末全体の累積送受信カウンターを読みます。'
          '全アプリ・複数の通信経路を含む値で、Wi-Fiだけの通信量ではありません。'
          '再起動すると累積値はリセットされます。\n\n'
          '計測開始後の変化を1秒ごとに最大60秒間だけ表示します。'
          '画面を閉じる・アプリが裏に回る・停止ボタンを押すと終了します。'
          'データは保存・外部送信しません。'
          'ほかの機器の通信量や通信内容は取得できません。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialog, false),
            child: const Text('キャンセル'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialog, true),
            child: const Text('60秒間計測する'),
          ),
        ],
      ),
    );
    if (!mounted || accepted != true || _running) return;

    final generation = ++_generation;
    _timer?.cancel();
    _deadline?.cancel();
    setState(() {
      _running = true;
      _sampling = false;
      _first = null;
      _last = null;
      _rate = null;
      _history.clear();
      _error = null;
      _notice = null;
      _expires = DateTime.now().add(_sessionLength);
    });

    _deadline = Timer(_sessionLength, () {
      if (mounted && generation == _generation) {
        _stop('60秒経過したため自動停止しました');
      }
    });
    await _sample(generation);
    if (!mounted || generation != _generation || !_running) return;
    _timer = Timer.periodic(_sampleInterval, (_) {
      unawaited(_sample(generation));
    });
  }

  Future<void> _sample(int generation) async {
    if (_sampling || !_running || generation != _generation) return;
    _sampling = true;
    try {
      final snapshot = await widget.client.snapshot()
          .timeout(const Duration(seconds: 3));
      if (!mounted || generation != _generation || !_running) return;
      if (!snapshot.supported) {
        setState(() {
          _error = 'このAndroid端末ではTrafficStatsの端末全体カウンターを取得できません';
        });
        _stop();
        return;
      }
      setState(() {
        final previous = _last;
        if (previous == null) {
          _first = snapshot;
        } else {
          final nextRate = snapshot.since(previous);
          if (nextRate == null) {
            // Counter reset / uptime regression: never report a negative
            // bandwidth value, even on an unsupported OEM implementation.
            _first = snapshot;
            _rate = null;
            _history.clear();
            _notice = 'カウンターのリセットを検知しました。計測基準を更新しました';
          } else {
            _rate = nextRate;
            _history.add(nextRate);
            if (_history.length > _maxSamples) _history.removeAt(0);
          }
        }
        _last = snapshot;
      });
    } catch (_) {
      if (mounted && generation == _generation && _running) {
        setState(() => _error = '通信量を取得できませんでした。再度お試しください');
        _stop();
      }
    } finally {
      _sampling = false;
    }
  }

  static String _bytes(num value) {
    double scaled = value.toDouble();
    const labels = ['B', 'KiB', 'MiB', 'GiB', 'TiB'];
    var unit = 0;
    while (scaled >= 1024 && unit < labels.length - 1) {
      scaled /= 1024;
      unit++;
    }
    return '${scaled.toStringAsFixed(unit == 0 ? 0 : 1)} ${labels[unit]}';
  }

  Widget _metric(String label, String value, String key) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: const TextStyle(fontSize: 12)),
            const SizedBox(height: 6),
            Text(value,
                key: Key(key),
                style: const TextStyle(
                    fontSize: 20, fontWeight: FontWeight.bold)),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final current = _last;
    final base = _first;
    final hasInterval = base != null && current != null &&
        current.rxBytes! >= base.rxBytes! &&
        current.txBytes! >= base.txBytes!;
    final received = hasInterval
        ? _bytes(current.rxBytes! - base.rxBytes!)
        : '測定待ち';
    final sent = hasInterval
        ? _bytes(current.txBytes! - base.txBytes!)
        : '測定待ち';
    final secondsLeft = _expires == null
        ? 0
        : math.max(0, _expires!.difference(DateTime.now()).inSeconds + 1);

    return Scaffold(
      appBar: AppBar(title: const Text('このスマホの通信量')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            const Text('NETLAB-02 / 通信量モニター（試作版）',
                style: TextStyle(fontSize: 19, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            const Text(
              '計測対象：このAndroid端末の全アプリ・全ネットワーク経路の合計。'
              '他の機器の通信量ではありません。'
              'Android TrafficStatsの概算カウンターで、正確な請求量・'
              'Wi-Fi専用量・アプリ別通信内容を表すものではありません。',
            ),
            const SizedBox(height: 14),
            Row(children: [
              Expanded(
                child: FilledButton.icon(
                  key: const Key('traffic_start'),
                  onPressed: _running ? null : _start,
                  icon: const Icon(Icons.play_arrow),
                  label: const Text('計測開始'),
                ),
              ),
              const SizedBox(width: 10),
              OutlinedButton.icon(
                key: const Key('traffic_stop'),
                onPressed: _running ? () => _stop('手動で停止しました') : null,
                icon: const Icon(Icons.stop_circle_outlined),
                label: const Text('停止'),
              ),
            ]),
            const SizedBox(height: 12),
            Text(
              _running ? '計測中（残り約$secondsLeft秒）' : '計測停止中',
              key: const Key('traffic_status'),
            ),
            if (_notice != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(_notice!,
                    style: const TextStyle(color: Colors.orangeAccent)),
              ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: SelectableText(_error!,
                    style: const TextStyle(color: Colors.orangeAccent)),
              ),
            const SizedBox(height: 12),
            Row(children: [
              Expanded(child: _metric('現在の受信速度',
                  _rate == null
                      ? '計測待ち'
                      : '${_bytes(_rate!.receivedPerSecond)}/秒',
                  'traffic_rx_rate')),
              Expanded(child: _metric('現在の送信速度',
                  _rate == null
                      ? '計測待ち'
                      : '${_bytes(_rate!.sentPerSecond)}/秒',
                  'traffic_tx_rate')),
            ]),
            const SizedBox(height: 12),
            Text('直近の通信速度（最大60サンプル）',
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            SizedBox(
              key: const Key('traffic_chart'),
              height: 160,
              child: Card(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: CustomPaint(
                    painter: _TrafficChartPainter(
                      List<DeviceTrafficRate>.unmodifiable(_history)),
                    child: Center(
                      child: _history.isEmpty
                          ? const Text('計測開始後、2回目の取得でグラフを表示します')
                          : null,
                    ),
                  ),
                ),
              ),
            ),
            const Row(children: [
              Icon(Icons.circle, size: 12, color: Colors.cyanAccent),
              SizedBox(width: 5),
              Text('受信', style: TextStyle(fontSize: 12)),
              SizedBox(width: 16),
              Icon(Icons.circle, size: 12, color: Colors.orangeAccent),
              SizedBox(width: 5),
              Text('送信', style: TextStyle(fontSize: 12)),
            ]),
            const SizedBox(height: 12),
            _metric('計測開始からの端末全体受信量', received, 'traffic_rx_total'),
            _metric('計測開始からの端末全体送信量', sent, 'traffic_tx_total'),
            if (_rate?.appReceivedPerSecond != null &&
                _rate?.appSentPerSecond != null)
              Text('参考：Chappy Player自身の通信速度：'
                  '受信 ${_bytes(_rate!.appReceivedPerSecond!)}/秒、'
                  '送信 ${_bytes(_rate!.appSentPerSecond!)}/秒'),
            const SizedBox(height: 16),
            const Text(
              'データ出典：Android TrafficStats（端末再起動後の累積値）。'
              '表示中の速度と開始後の通信量は端末カウンターの差から計算。'
              'データはこの画面のメモリだけで保持し、終了時に破棄します。'
              'ほかのLAN機器の使用量・通信先・通信本文は取得しません。',
              style: TextStyle(fontSize: 12, color: Colors.white60),
            ),
          ],
        ),
      ),
    );
  }
}

class _TrafficChartPainter extends CustomPainter {
  final List<DeviceTrafficRate> samples;
  const _TrafficChartPainter(this.samples);

  @override
  void paint(Canvas canvas, Size size) {
    if (samples.isEmpty || size.width <= 0 || size.height <= 0) return;
    final maxRate = samples.fold<double>(
      1,
      (peak, sample) => math.max(peak,
          math.max(sample.receivedPerSecond, sample.sentPerSecond)),
    );
    void draw(Color color, double Function(DeviceTrafficRate) read) {
      final paint = Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5
        ..strokeCap = StrokeCap.round;
      final points = Path();
      for (var i = 0; i < samples.length; i++) {
        final x = samples.length == 1
            ? 0.0
            : size.width * i / (samples.length - 1);
        final y = size.height -
            math.min(size.height, read(samples[i]) / maxRate * size.height);
        if (i == 0) {
          points.moveTo(x, y);
        } else {
          points.lineTo(x, y);
        }
      }
      canvas.drawPath(points, paint);
    }
    draw(Colors.cyanAccent, (item) => item.receivedPerSecond);
    draw(Colors.orangeAccent, (item) => item.sentPerSecond);
  }

  @override
  bool shouldRepaint(_TrafficChartPainter oldDelegate) =>
      oldDelegate.samples != samples;
}
