import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'ble_service.dart';
import 'tpms_decoder.dart';

class DeviceDetailView extends StatefulWidget {
  const DeviceDetailView({
    super.key,
    required this.deviceId,
    this.result,
    this.deviceName,
  });

  final String deviceId;
  final ScanResult? result;
  final String? deviceName;

  @override
  State<DeviceDetailView> createState() => _DeviceDetailViewState();
}

class _DeviceDetailViewState extends State<DeviceDetailView> {
  late final TextEditingController _weightController;
  late final TextEditingController _targetPsiController;
  double? _lbsPerPsi;
  double? _targetPsi;
  bool _useKg = false;
  String? _previousTargetMac;
  bool? _previousContinuousScan;
  bool _monitoringActive = false;
  BleService? _bleService;
  bool _restoreScheduled = false;

  @override
  void initState() {
    super.initState();
    _weightController = TextEditingController();
    _targetPsiController = TextEditingController();
    _loadCalibration();
    _loadTargetPsi();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      context.read<BleService>().loadCachedDecoded(widget.deviceId);
      _enableMonitoring();
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_previousTargetMac == null || _previousContinuousScan == null) {
      _bleService ??= context.read<BleService>();
      _previousTargetMac = _bleService!.targetMac;
      _previousContinuousScan = _bleService!.continuousScan;
    }
  }

  @override
  void dispose() {
    _weightController.dispose();
    _targetPsiController.dispose();
    super.dispose();
  }

  @override
  void deactivate() {
    if (!_restoreScheduled) {
      _restoreScheduled = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _restoreScheduled = false;
        if (mounted) {
          _restoreMonitoring();
        }
      });
    }
    super.deactivate();
  }

  Future<void> _enableMonitoring() async {
    if (_monitoringActive) return;
    _monitoringActive = true;
    final service = _bleService ?? context.read<BleService>();
    service.setTargetMac(widget.deviceId);
    await service.setContinuousScan(true);
  }

  Future<void> _restoreMonitoring() async {
    if (!_monitoringActive) return;
    _monitoringActive = false;
    final service = _bleService;
    if (service == null) return;
    if (_previousTargetMac != null) {
      service.setTargetMac(_previousTargetMac!);
    }
    if (_previousContinuousScan != null) {
      await service.setContinuousScan(_previousContinuousScan!);
    }
  }

  Future<void> _loadCalibration() async {
    final prefs = await SharedPreferences.getInstance();
    final deviceKey = _calibrationKey(widget.deviceId);
    final deviceValue = prefs.getDouble(deviceKey);
    if (!mounted) return;
    setState(() {
      _lbsPerPsi = deviceValue;
    });
  }

  Future<void> _loadTargetPsi() async {
    final prefs = await SharedPreferences.getInstance();
    final key = _targetPsiKey(widget.deviceId);
    final value = prefs.getDouble(key);
    if (!mounted) return;
    setState(() {
      _targetPsi = value;
      if (value != null) {
        _targetPsiController.text = value.toStringAsFixed(0);
      }
    });
  }

  Future<void> _saveCalibration(double lbsPerPsi) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_calibrationKey(widget.deviceId), lbsPerPsi);
    if (!mounted) return;
    setState(() {
      _lbsPerPsi = lbsPerPsi;
    });
  }

  Future<void> _saveTargetPsi(double targetPsi) async {
    final prefs = await SharedPreferences.getInstance();
    final key = _targetPsiKey(widget.deviceId);
    await prefs.setDouble(key, targetPsi);
    if (!mounted) return;
    setState(() {
      _targetPsi = targetPsi;
    });
  }

  String _calibrationKey(String deviceId) => 'tpms_calibration_$deviceId';
  String _targetPsiKey(String deviceId) => 'tpms_target_psi_$deviceId';

  @override
  Widget build(BuildContext context) {
    final service = context.watch<BleService>();
    final liveResult = service.getResultById(widget.deviceId) ?? widget.result;
    final cachedDecoded = service.getLastDecoded(widget.deviceId);
    final deviceName = _resolveDeviceName(liveResult, widget.deviceName);
    final rssiText = liveResult == null ? '—' : liveResult.rssi.toString();

    return Scaffold(
      appBar: AppBar(
        title: Text(deviceName),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _InfoCard(
            title: 'Device Info',
            children: [
              _InfoRow(label: 'ID', value: widget.deviceId),
              _InfoRow(label: 'RSSI', value: rssiText),
              _InfoRow(label: 'Name', value: deviceName),
            ],
          ),
          const SizedBox(height: 16),
          _InfoCard(
            title: 'TPMS Data',
            children: _buildTpmsData(liveResult, cachedDecoded: cachedDecoded),
          ),
          const SizedBox(height: 16),
          _InfoCard(
            title: 'Raw Advertisement (Debug)',
            children: _buildAdvertisementDebug(liveResult, cachedDecoded: cachedDecoded),
          ),
        ],
      ),
    );
  }

  List<Widget> _buildTpmsData(ScanResult? result, {TpmsDecoded? cachedDecoded}) {
    final decoded = result == null ? cachedDecoded : (decodeTpmsFromManufacturerData(result) ?? cachedDecoded);
    final bigStyle = Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700);
    final weightStyle = Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700);
    if (decoded == null) {
      return const [
        Text('No TPMS payload decoded yet.'),
        SizedBox(height: 8),
        Text('Pressure: -- psi'),
        Text('Temperature: -- °C'),
        Text('Battery: -- %'),
      ];
    }

    final pressurePsi = decoded.pressurePsi;
    final pressureText = pressurePsi == null
      ? 'Pressure: -- psi'
      : 'Pressure: ${pressurePsi.toStringAsFixed(1)} psi';
    final tempText = decoded.temperatureC == null
        ? 'Temperature: -- °C'
        : 'Temperature: ${decoded.temperatureC!.toStringAsFixed(0)} °C';

    final weightLbs = (pressurePsi != null && _lbsPerPsi != null)
      ? pressurePsi * _lbsPerPsi!
      : null;
    final weightKg = weightLbs == null ? null : weightLbs * 0.45359237;
    final weightText = weightLbs == null
      ? 'Weight: -- lbs'
      : 'Weight: ${weightLbs.toStringAsFixed(0)} lbs';
    final weightTextKg = weightKg == null
      ? 'Weight: -- kg'
      : 'Weight: ${weightKg.toStringAsFixed(0)} kg';
    final updatedText = _formatUpdated(decoded.timestamp);
    final percent = _targetPsi == null || pressurePsi == null
        ? null
        : (pressurePsi / _targetPsi!) * 100;
    final statusColor = _statusColor(percent);
    final percentText = percent == null ? null : 'Load: ${percent.toStringAsFixed(0)}%';

    return [
      const Text('Decoded from manufacturer data (estimated).'),
      const SizedBox(height: 8),
      Text(pressureText, style: bigStyle?.copyWith(color: statusColor)),
      Text(tempText),
      const Text('Battery: -- %'),
      const SizedBox(height: 12),
      Text(_useKg ? weightTextKg : weightText, style: weightStyle?.copyWith(color: statusColor)),
      if (percentText != null) Text(percentText, style: TextStyle(color: statusColor)),
      const SizedBox(height: 4),
      Text(updatedText, style: Theme.of(context).textTheme.bodySmall),
      const SizedBox(height: 12),
      Text('Target PSI (100% load)', style: Theme.of(context).textTheme.titleSmall),
      const SizedBox(height: 6),
      Row(
        children: [
          Expanded(
            child: TextField(
              controller: _targetPsiController,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(
                labelText: 'Target PSI',
                hintText: 'e.g. 100',
              ),
            ),
          ),
          const SizedBox(width: 8),
          ElevatedButton(
            onPressed: () {
              final raw = _targetPsiController.text.trim();
              final input = double.tryParse(raw);
              if (input == null || input <= 0) return;
              _saveTargetPsi(input);
            },
            child: const Text('Save'),
          ),
        ],
      ),
      Row(
        children: [
          Expanded(
            child: TextField(
              controller: _weightController,
              keyboardType: const TextInputType.numberWithOptions(decimal: false),
              decoration: InputDecoration(
                labelText: _useKg ? 'Set weight (kg)' : 'Set weight (lbs)',
                hintText: _useKg ? 'e.g. 24000' : 'e.g. 50000',
              ),
            ),
          ),
          const SizedBox(width: 8),
          ElevatedButton(
            onPressed: pressurePsi == null
                ? null
                : () {
                    final raw = _weightController.text.trim();
                    final input = double.tryParse(raw);
                    if (input == null || input <= 0 || pressurePsi <= 0) {
                      return;
                    }
                    final lbs = _useKg ? input / 0.45359237 : input;
                    final lbsPerPsi = lbs / pressurePsi;
                    _saveCalibration(lbsPerPsi);
                  },
            child: const Text('Set'),
          ),
        ],
      ),
      Row(
        children: [
          const Text('Units:'),
          const SizedBox(width: 8),
          ChoiceChip(
            label: const Text('lbs'),
            selected: !_useKg,
            onSelected: (value) {
              setState(() {
                _useKg = !value;
              });
            },
          ),
          const SizedBox(width: 8),
          ChoiceChip(
            label: const Text('kg'),
            selected: _useKg,
            onSelected: (value) {
              setState(() {
                _useKg = value;
              });
            },
          ),
        ],
      ),
      if (_lbsPerPsi != null)
        Text('Calibration: ${_lbsPerPsi!.toStringAsFixed(1)} lbs/psi'),
      const SizedBox(height: 8),
      Text('Raw bytes: ${decoded.rawPayload}'),
    ];
  }

  String _formatUpdated(DateTime? timestamp) {
    if (timestamp == null) return 'Last updated: —';
    final h = timestamp.hour.toString().padLeft(2, '0');
    final m = timestamp.minute.toString().padLeft(2, '0');
    final s = timestamp.second.toString().padLeft(2, '0');
    return 'Last updated: $h:$m:$s';
  }

  Color? _statusColor(double? percent) {
    if (percent == null) return null;
    if (percent < 80) return Colors.green;
    if (percent <= 100) return Colors.amber;
    return Colors.red;
  }

  List<Widget> _buildAdvertisementDebug(ScanResult? result, {TpmsDecoded? cachedDecoded}) {
    if (result == null) {
      return [
        const Text('No live advertisement available.'),
        const SizedBox(height: 8),
        Text('Last payload: ${cachedDecoded?.rawPayload ?? '—'}'),
      ];
    }
    final adv = result.advertisementData;
    final serviceUuids = adv.serviceUuids.isEmpty
        ? '—'
        : adv.serviceUuids.map((e) => e.str).join(', ');
    final manufacturerData = adv.manufacturerData.isEmpty
        ? '—'
        : adv.manufacturerData.entries
        .map((e) => '${e.key}: ${formatBytes(e.value)}')
            .join('\n');
    final serviceData = adv.serviceData.isEmpty
        ? '—'
        : adv.serviceData.entries
        .map((e) => '${e.key.str}: ${formatBytes(e.value)}')
            .join('\n');

    return [
      _InfoRow(label: 'Name', value: adv.advName.isEmpty ? '—' : adv.advName),
      _InfoRow(label: 'Connectable', value: adv.connectable.toString()),
      _InfoRow(label: 'TX Power', value: adv.txPowerLevel?.toString() ?? '—'),
      _InfoRow(label: 'Service UUIDs', value: serviceUuids),
      const SizedBox(height: 8),
      const Text('Manufacturer Data:', style: TextStyle(fontWeight: FontWeight.w600)),
      SelectableText(manufacturerData),
      const SizedBox(height: 8),
      const Text('Service Data:', style: TextStyle(fontWeight: FontWeight.w600)),
      SelectableText(serviceData),
    ];
  }

  String _resolveDeviceName(ScanResult? result, String? fallback) {
    if (result != null) {
      if (result.device.platformName.isNotEmpty) return result.device.platformName;
      if (result.advertisementData.advName.isNotEmpty) return result.advertisementData.advName;
    }
    if (fallback != null && fallback.isNotEmpty) return fallback;
    return 'Unknown Sensor';
  }

}

class _InfoCard extends StatelessWidget {
  const _InfoCard({required this.title, required this.children});

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 12),
            ...children,
          ],
        ),
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          SizedBox(
            width: 90,
            child: Text(
              label,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
            ),
          ),
          Expanded(child: Text(value)),
        ],
      ),
    );
  }
}
