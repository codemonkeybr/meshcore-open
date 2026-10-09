import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../connector/meshcore_connector.dart';
import '../connector/meshcore_protocol.dart';
import '../helpers/telemetry_series.dart';
import '../l10n/l10n.dart';
import '../models/app_settings.dart';
import '../models/contact.dart';
import '../models/telemetry_history.dart';
import '../services/app_settings_service.dart';
import '../services/repeater_history_fetcher.dart';
import '../services/telemetry_history_service.dart';
import '../theme/mesh_theme.dart';
import '../widgets/adaptive_app_bar_title.dart';
import '../widgets/empty_state.dart';
import '../widgets/mesh_ui.dart';
import '../widgets/repeater_login_dialog.dart';
import '../widgets/room_login_dialog.dart';
import '../widgets/telemetry_chart.dart';

/// Charts of the readings saved for a repeater or room: radio statistics,
/// neighbor SNR and sensor values, with a button to fetch new readings.
class TelemetryHistoryScreen extends StatefulWidget {
  final Contact contact;

  const TelemetryHistoryScreen({super.key, required this.contact});

  @override
  State<TelemetryHistoryScreen> createState() => _TelemetryHistoryScreenState();
}

enum _Section { radio, neighbors, sensors }

class _TelemetryHistoryScreenState extends State<TelemetryHistoryScreen> {
  HistoryRange _range = HistoryRange.month;
  final Set<_Section> _collapsed = {};

  bool _fetching = false;
  Map<HistoryFetchStep, HistoryStepState> _steps = {};
  Map<HistoryFetchStep, String> _attempts = {};
  HistoryFetchFailure? _failure;
  bool _failureUsedSavedPassword = false;

  bool get _isRepeater => widget.contact.type == advTypeRepeater;
  bool get _isRoom => widget.contact.type == advTypeRoom;

  String get _nodeKey =>
      TelemetryHistoryService.keyOf(widget.contact.publicKeyHex);

  String _deviceKey(MeshCoreConnector connector) =>
      TelemetryHistoryService.keyOf(connector.selfPublicKeyHex);

  @override
  void initState() {
    super.initState();
    final connector = context.read<MeshCoreConnector>();
    unawaited(
      context.read<TelemetryHistoryService>().load(
        _deviceKey(connector),
        _nodeKey,
      ),
    );
  }

  Future<void> _refresh({String? password}) async {
    if (_fetching) return;
    final connector = context.read<MeshCoreConnector>();
    final history = context.read<TelemetryHistoryService>();
    setState(() {
      _fetching = true;
      _failure = null;
      _steps = {};
      _attempts = {};
    });
    final result =
        await RepeaterHistoryFetcher(
          connector: connector,
          history: history,
        ).fetch(
          widget.contact,
          password: password,
          onProgress: (step, state) {
            if (!mounted) return;
            setState(() => _steps = {..._steps, step: state});
          },
          onAttempt: (step, attempt, max) {
            if (!mounted) return;
            setState(() => _attempts = {..._attempts, step: '$attempt/$max'});
          },
        );
    if (!mounted) return;
    setState(() {
      _fetching = false;
      _failure = result.failure;
      _failureUsedSavedPassword = result.usedSavedPassword;
    });
  }

  void _openLogin() {
    if (_isRoom) {
      showDialog(
        context: context,
        builder: (_) => RoomLoginDialog(
          room: widget.contact,
          onLogin: (password, isAdmin) => _refresh(password: password),
        ),
      );
    } else {
      showDialog(
        context: context,
        builder: (_) => RepeaterLoginDialog(
          repeater: widget.contact,
          onLogin: (password, isAdmin) => _refresh(password: password),
        ),
      );
    }
  }

  Future<void> _confirmClear() async {
    final l10n = context.l10n;
    final connector = context.read<MeshCoreConnector>();
    final history = context.read<TelemetryHistoryService>();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(l10n.history_clearConfirmTitle),
        content: Text(l10n.history_clearConfirmBody(widget.contact.name)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text(l10n.common_cancel),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            style: TextButton.styleFrom(
              foregroundColor: Theme.of(dialogContext).colorScheme.error,
            ),
            child: Text(l10n.history_clear),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await history.clear(_deviceKey(connector), _nodeKey);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final connector = context.watch<MeshCoreConnector>();
    final historyService = context.watch<TelemetryHistoryService>();
    final history = historyService.cached(_deviceKey(connector), _nodeKey);
    final canRefresh = connector.isConnected && !_fetching;

    return Scaffold(
      appBar: AppBar(
        title: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            AdaptiveAppBarTitle(l10n.history_title),
            Text(
              widget.contact.name,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.normal,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
        centerTitle: true,
        actions: [
          IconButton(
            icon: _fetching
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.refresh),
            tooltip: connector.isConnected
                ? l10n.history_refresh
                : l10n.history_refreshNeedsConnection,
            onPressed: canRefresh ? () => _refresh() : null,
          ),
          PopupMenuButton<String>(
            onSelected: (value) {
              if (value == 'clear') _confirmClear();
            },
            itemBuilder: (context) => [
              PopupMenuItem(
                value: 'clear',
                child: Text(
                  l10n.history_clear,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
            ],
          ),
        ],
      ),
      body: SafeArea(
        top: false,
        child: Column(
          children: [
            if (_fetching) _buildProgressStrip(),
            if (!_fetching && _failure != null) _buildFailureStrip(),
            Expanded(
              child: history.isEmpty && !_fetching
                  ? _buildEmpty()
                  : _buildCharts(history, connector),
            ),
          ],
        ),
      ),
    );
  }

  // --- refresh feedback ----------------------------------------------------

  Widget _buildProgressStrip() {
    final l10n = context.l10n;
    final steps = <(HistoryFetchStep, String)>[
      (HistoryFetchStep.login, l10n.history_stepLogin),
      (HistoryFetchStep.radio, l10n.history_stepRadio),
      if (_isRepeater) (HistoryFetchStep.neighbors, l10n.history_stepNeighbors),
      (HistoryFetchStep.sensors, l10n.history_stepSensors),
    ];
    return MeshCard(
      margin: const EdgeInsets.fromLTRB(16, 10, 16, 0),
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            l10n.history_fetchTitle,
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 8),
          for (final (step, label) in steps)
            _StepRow(
              label: label,
              state: _steps[step] ?? HistoryStepState.pending,
              attempt: _attempts[step],
            ),
        ],
      ),
    );
  }

  Widget _buildFailureStrip() {
    final l10n = context.l10n;
    final failure = _failure!;
    final String message;
    var showLogin = false;
    switch (failure) {
      case HistoryFetchFailure.notConnected:
        message = l10n.history_failNotConnected;
      case HistoryFetchFailure.loginRejected:
        message = _failureUsedSavedPassword
            ? l10n.history_failRejectedSaved
            : l10n.history_failRejectedGuest;
        showLogin = true;
      case HistoryFetchFailure.noAnswer:
        message = l10n.history_failNoAnswer;
    }
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(16, 10, 16, 0),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: MeshPalette.warnBg,
        border: Border.all(color: MeshPalette.warnLine),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            l10n.history_failTitle,
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 4),
          Text(
            message,
            style: TextStyle(
              fontSize: 12.5,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 8),
          OutlinedButton(
            onPressed: showLogin ? _openLogin : () => _refresh(),
            child: Text(
              showLogin ? l10n.history_loginButton : l10n.history_tryAgain,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmpty() {
    final l10n = context.l10n;
    final connector = context.watch<MeshCoreConnector>();
    return EmptyState(
      icon: Icons.history,
      title: l10n.history_emptyTitle,
      subtitle: l10n.history_emptyBody,
      action: OutlinedButton(
        onPressed: connector.isConnected && !_fetching
            ? () => _refresh()
            : null,
        child: Text(l10n.history_getReadings),
      ),
    );
  }

  // --- charts --------------------------------------------------------------

  Widget _buildCharts(NodeHistory history, MeshCoreConnector connector) {
    final l10n = context.l10n;
    final now = DateTime.now();
    final cutoff = _range.cutoff(now);
    final start =
        cutoff ?? _earliest(history) ?? now.subtract(const Duration(days: 1));

    final imperial =
        context.watch<AppSettingsService>().settings.unitSystem ==
        UnitSystem.imperial;

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 24),
      children: [
        SegmentedButton<HistoryRange>(
          showSelectedIcon: false,
          segments: [
            ButtonSegment(
              value: HistoryRange.week,
              label: Text(l10n.history_rangeWeek),
            ),
            ButtonSegment(
              value: HistoryRange.month,
              label: Text(l10n.history_rangeMonth),
            ),
            ButtonSegment(
              value: HistoryRange.threeMonths,
              label: Text(l10n.history_range3Months),
            ),
            ButtonSegment(
              value: HistoryRange.all,
              label: Text(l10n.history_rangeAll),
            ),
          ],
          selected: {_range},
          onSelectionChanged: (s) => setState(() => _range = s.first),
        ),
        const SizedBox(height: 8),
        if (history.radio.isNotEmpty)
          _buildSection(
            _Section.radio,
            l10n.history_sectionRadio,
            _radioCharts(history.radio, start, now),
          ),
        if (_isRepeater && history.neighbors.isNotEmpty)
          ..._neighborSection(history.neighbors, start, now, connector),
        if (history.sensors.isNotEmpty)
          _buildSection(
            _Section.sensors,
            l10n.history_sectionSensors,
            _sensorCharts(history.sensors, start, now, imperial),
          ),
        Padding(
          padding: const EdgeInsets.fromLTRB(8, 14, 8, 0),
          child: Text(
            l10n.history_footer,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 12,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ),
      ],
    );
  }

  DateTime? _earliest(NodeHistory h) {
    final times = <DateTime>[
      ...h.radio.map((s) => s.time),
      ...h.neighbors.map((s) => s.time),
      ...h.sensors.map((s) => s.time),
    ];
    if (times.isEmpty) return null;
    return times.reduce((a, b) => a.isBefore(b) ? a : b);
  }

  Widget _buildSection(_Section section, String title, List<Widget> children) {
    final collapsed = _collapsed.contains(section);
    return MeshCard(
      margin: const EdgeInsets.symmetric(vertical: 6),
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            onTap: () => setState(() {
              collapsed ? _collapsed.remove(section) : _collapsed.add(section);
            }),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      title,
                      style: const TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 15,
                      ),
                    ),
                  ),
                  Icon(collapsed ? Icons.expand_more : Icons.expand_less),
                ],
              ),
            ),
          ),
          if (!collapsed)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: children,
              ),
            ),
        ],
      ),
    );
  }

  List<SeriesPoint> _prepare(List<SeriesPoint> points, DateTime? cutoff) =>
      bucketSeries(pointsSince(points, cutoff));

  Widget _chartBlock({
    required String title,
    required List<ChartSeries> series,
    required DateTime start,
    required DateTime end,
    String unit = '',
    int decimals = 0,
    double? minY,
    double? maxY,
    double minSpan = 1,
    bool nonNegative = false,
    bool integers = false,
    bool legend = false,
  }) {
    final scheme = Theme.of(context).colorScheme;
    final hasData = series.any((s) => s.points.isNotEmpty);
    return Padding(
      padding: const EdgeInsets.only(top: 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                title,
                style: const TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: 13,
                ),
              ),
              if (unit.isNotEmpty) ...[
                const SizedBox(width: 6),
                Text(
                  unit,
                  style: TextStyle(
                    fontSize: 12,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ],
            ],
          ),
          if (legend)
            Padding(
              padding: const EdgeInsets.only(top: 2, bottom: 2),
              child: Wrap(
                spacing: 12,
                children: [
                  for (final s in series)
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 8,
                          height: 8,
                          decoration: BoxDecoration(
                            color: s.color,
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 5),
                        Text(
                          s.label,
                          style: TextStyle(
                            fontSize: 11,
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                ],
              ),
            ),
          const SizedBox(height: 12),
          if (!hasData)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 18),
              child: Text(
                context.l10n.history_noReadingsInRange,
                style: TextStyle(
                  fontSize: 12.5,
                  color: scheme.onSurfaceVariant,
                ),
              ),
            )
          else
            TelemetryChart(
              series: series,
              start: start,
              end: end,
              unit: unit.isEmpty ? '' : ' $unit',
              decimals: decimals,
              minY: minY,
              maxY: maxY,
              minSpan: minSpan,
              nonNegative: nonNegative,
              integers: integers,
            ),
        ],
      ),
    );
  }

  List<Widget> _radioCharts(
    List<RadioSample> samples,
    DateTime start,
    DateTime end,
  ) {
    final l10n = context.l10n;
    final cutoff = _range.cutoff(end);
    List<SeriesPoint> pts(double Function(RadioSample) pick) => _prepare([
      for (final s in samples) SeriesPoint(s.time, pick(s)),
    ], cutoff);

    return [
      _chartBlock(
        title: l10n.history_chartBattery,
        unit: 'V',
        decimals: 2,
        minSpan: 0.5,
        start: start,
        end: end,
        series: [
          ChartSeries(
            label: l10n.history_chartBattery,
            color: MeshPalette.signal,
            fill: true,
            points: pts((s) => s.batteryMv / 1000.0),
          ),
        ],
      ),
      _chartBlock(
        title: l10n.history_chartSnr,
        unit: 'dB',
        decimals: 1,
        minSpan: 10,
        start: start,
        end: end,
        series: [
          ChartSeries(
            label: l10n.history_chartSnr,
            color: MeshPalette.blue,
            fill: true,
            points: pts((s) => s.snr),
          ),
        ],
      ),
      _chartBlock(
        title: l10n.history_chartRssi,
        integers: true,
        unit: 'dBm',
        minSpan: 20,
        start: start,
        end: end,
        series: [
          ChartSeries(
            label: l10n.history_chartRssi,
            color: MeshPalette.magenta,
            points: pts((s) => s.rssi.toDouble()),
          ),
        ],
      ),
      _chartBlock(
        title: l10n.history_chartNoise,
        integers: true,
        unit: 'dBm',
        minSpan: 20,
        start: start,
        end: end,
        series: [
          ChartSeries(
            label: l10n.history_chartNoise,
            color: const Color(0xFF8B8CF8),
            points: pts((s) => s.noiseFloor.toDouble()),
          ),
        ],
      ),
      _chartBlock(
        title: l10n.history_chartSent,
        nonNegative: true,
        integers: true,
        legend: true,
        start: start,
        end: end,
        series: [
          ChartSeries(
            label: l10n.history_legendDirect,
            color: MeshPalette.blue,
            points: pts((s) => s.sentDirect.toDouble()),
          ),
          ChartSeries(
            label: l10n.history_legendFlood,
            color: MeshPalette.warn,
            points: pts((s) => s.sentFlood.toDouble()),
          ),
        ],
      ),
      _chartBlock(
        title: l10n.history_chartDuplicates,
        nonNegative: true,
        integers: true,
        legend: true,
        start: start,
        end: end,
        series: [
          ChartSeries(
            label: l10n.history_legendDirect,
            color: MeshPalette.blue,
            points: pts((s) => s.dupDirect.toDouble()),
          ),
          ChartSeries(
            label: l10n.history_legendFlood,
            color: MeshPalette.warn,
            points: pts((s) => s.dupFlood.toDouble()),
          ),
        ],
      ),
      _chartBlock(
        title: l10n.history_chartErrors,
        nonNegative: true,
        integers: true,
        start: start,
        end: end,
        series: [
          ChartSeries(
            label: l10n.history_chartErrors,
            color: MeshPalette.alert,
            fill: true,
            points: pts((s) => s.errors.toDouble()),
          ),
        ],
      ),
    ];
  }

  String _neighborName(String prefixHex, MeshCoreConnector connector) {
    for (final c in connector.allContactsUnfiltered) {
      if (c.type == advTypeRepeater &&
          c.publicKeyHex.toLowerCase().startsWith(prefixHex.toLowerCase())) {
        return c.name;
      }
    }
    return prefixHex.toUpperCase();
  }

  List<Widget> _neighborSection(
    List<NeighborSample> samples,
    DateTime start,
    DateTime end,
    MeshCoreConnector connector,
  ) {
    final l10n = context.l10n;
    final cutoff = _range.cutoff(end);
    final byPrefix = <String, List<SeriesPoint>>{};
    for (final sample in samples) {
      for (final r in sample.readings) {
        byPrefix
            .putIfAbsent(r.prefixHex, () => [])
            .add(SeriesPoint(sample.time, r.snr));
      }
    }
    final entries = byPrefix.entries.toList()
      ..sort(
        (a, b) => _neighborName(a.key, connector).toLowerCase().compareTo(
          _neighborName(b.key, connector).toLowerCase(),
        ),
      );

    final children = <Widget>[];
    for (final e in entries) {
      final name = _neighborName(e.key, connector);
      final all = e.value;
      if (all.length == 1) {
        children.add(_singleReading(name, all.first.value));
        continue;
      }
      children.add(
        _chartBlock(
          title: name,
          unit: 'dB',
          decimals: 1,
          minSpan: 10,
          start: start,
          end: end,
          series: [
            ChartSeries(
              label: name,
              color: MeshPalette.blue,
              points: _prepare(all, cutoff),
            ),
          ],
        ),
      );
    }
    if (entries.any((e) => e.value.length == 1)) {
      children.add(
        Padding(
          padding: const EdgeInsets.only(top: 16),
          child: Text(
            l10n.history_singleReading,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 12,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ),
      );
    }
    return [
      _buildSection(
        _Section.neighbors,
        l10n.history_sectionNeighborsCount(entries.length),
        children,
      ),
    ];
  }

  Widget _singleReading(String name, double snr) {
    return Padding(
      padding: const EdgeInsets.only(top: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            name,
            style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
          ),
          const SizedBox(height: 6),
          Center(
            child: Text(
              '${snr.toStringAsFixed(2)} dB',
              style: MeshTheme.mono(
                fontSize: 22,
                fontWeight: FontWeight.w600,
                color: MeshTheme.snrColor(snr, blocked: false),
              ),
            ),
          ),
        ],
      ),
    );
  }

  List<Widget> _sensorCharts(
    List<SensorSample> samples,
    DateTime start,
    DateTime end,
    bool imperial,
  ) {
    final l10n = context.l10n;
    final cutoff = _range.cutoff(end);
    // "<channel>/<name>" -> points, grouped by channel for display.
    final byKey = <String, List<SeriesPoint>>{};
    for (final s in samples) {
      for (final e in s.values.entries) {
        byKey.putIfAbsent(e.key, () => []).add(SeriesPoint(s.time, e.value));
      }
    }
    int channelOf(String key) => int.tryParse(key.split('/').first) ?? 0;
    String nameOf(String key) => key.split('/').last;
    final keys = byKey.keys.toList()
      ..sort((a, b) {
        final c = channelOf(a).compareTo(channelOf(b));
        return c != 0 ? c : nameOf(a).compareTo(nameOf(b));
      });

    final colors = [
      MeshPalette.warn,
      const Color(0xFF2DD4BF),
      MeshPalette.signal,
      MeshPalette.magenta,
      MeshPalette.blue,
    ];
    final widgets = <Widget>[];
    int? lastChannel;
    var colorIndex = 0;
    for (final key in keys) {
      final channel = channelOf(key);
      final name = nameOf(key);
      if (channel != lastChannel) {
        lastChannel = channel;
        widgets.add(
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Text(
              l10n.telemetry_channelTitle(channel),
              style: TextStyle(
                fontSize: 11,
                letterSpacing: 0.6,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        );
      }
      final pts = _prepare([
        for (final p in byKey[key]!)
          SeriesPoint(
            p.time,
            sensorDisplayValue(name, p.value, imperial: imperial),
          ),
      ], cutoff);
      widgets.add(
        _chartBlock(
          title: sensorLabel(name),
          unit: sensorUnit(name, imperial: imperial),
          decimals: 1,
          minSpan: name == 'temperature' ? 10 : 1,
          start: start,
          end: end,
          series: [
            ChartSeries(
              label: sensorLabel(name),
              color: colors[colorIndex++ % colors.length],
              fill: true,
              points: pts,
            ),
          ],
        ),
      );
    }
    return widgets;
  }
}

class _StepRow extends StatelessWidget {
  final String label;
  final HistoryStepState state;

  /// "1/3" style counter, shown while the step is being tried (and after it
  /// gave up, so the number of tries stays visible).
  final String? attempt;

  const _StepRow({required this.label, required this.state, this.attempt});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final Widget icon;
    switch (state) {
      case HistoryStepState.running:
        icon = const SizedBox(
          width: 14,
          height: 14,
          child: CircularProgressIndicator(strokeWidth: 2),
        );
      case HistoryStepState.done:
        icon = Icon(Icons.check_circle, size: 16, color: MeshPalette.signal);
      case HistoryStepState.failed:
        icon = Icon(Icons.error_outline, size: 16, color: MeshPalette.warn);
      case HistoryStepState.pending:
        icon = Icon(
          Icons.circle_outlined,
          size: 16,
          color: scheme.onSurfaceVariant,
        );
    }
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          SizedBox(width: 18, child: Center(child: icon)),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                color: state == HistoryStepState.pending
                    ? scheme.onSurfaceVariant
                    : scheme.onSurface,
              ),
            ),
          ),
          if (attempt != null &&
              (state == HistoryStepState.running ||
                  state == HistoryStepState.failed))
            Text(
              attempt!,
              style: MeshTheme.mono(
                fontSize: 12,
                color: scheme.onSurfaceVariant,
              ),
            ),
        ],
      ),
    );
  }
}
