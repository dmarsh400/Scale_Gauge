import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'ble_service.dart';
import 'device_detail_view.dart';
import 'tpms_decoder.dart';
import '../settings/tpms_config.dart';

class MonitorView extends StatefulWidget {
  const MonitorView({super.key});

  @override
  State<MonitorView> createState() => MonitorViewState();
}

class MonitorViewState extends State<MonitorView> {
  static const _truckKey = BleService.pairedTruckKey;
  static const _trailerKey = BleService.pairedTrailerKey;
  static const _trailer2Key = BleService.pairedTrailer2Key;
  static const Duration _staleAfter = Duration(seconds: 10);

  String? _truckId;
  String? _trailerId;
  String? _trailer2Id;
  double? _truckLbsPerPsi;
  double? _trailerLbsPerPsi;
  double? _trailer2LbsPerPsi;
  double? _truckTargetPsi;
  double? _trailerTargetPsi;
  double? _trailer2TargetPsi;
  bool _useKg = false;
  TpmsConfig _config = TpmsConfig.quad;
  String? _configIdCache;
  bool _configLoading = false;
  bool _swapInProgress = false;
  final Set<String> _cacheLoadedIds = {};
  bool _autoReconnectDone = false;
  final Map<String, int> _lastStatusById = {};
  final Map<String, DateTime> _lastVibeAt = {};

  String? _previousTargetMac;
  bool? _previousContinuousScan;
  bool _monitoringActive = false;

  @override
  void initState() {
    super.initState();
    _loadSelections();
  }

  Future<void> reloadConfig() async {
    await _loadSelections();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_previousTargetMac == null || _previousContinuousScan == null) {
      final service = context.read<BleService>();
      _previousTargetMac = service.targetMac;
      _previousContinuousScan = service.continuousScan;
    }
  }

  @override
  void dispose() {
    _restoreMonitoring();
    super.dispose();
  }

  Future<void> _loadSelections() async {
    final prefs = await SharedPreferences.getInstance();
    final configId = prefs.getString(TpmsConfig.prefsKey);
    final truckId = prefs.getString(_truckKey);
    final trailerId = prefs.getString(_trailerKey);
    final trailer2Id = prefs.getString(_trailer2Key);
    final truckCal = truckId == null ? null : prefs.getDouble(_calibrationKey(truckId));
    final trailerCal = trailerId == null ? null : prefs.getDouble(_calibrationKey(trailerId));
    final trailer2Cal = trailer2Id == null ? null : prefs.getDouble(_calibrationKey(trailer2Id));
    final truckTarget = truckId == null ? null : prefs.getDouble(_targetPsiKey(truckId));
    final trailerTarget = trailerId == null ? null : prefs.getDouble(_targetPsiKey(trailerId));
    final trailer2Target = trailer2Id == null ? null : prefs.getDouble(_targetPsiKey(trailer2Id));
    if (!mounted) return;
    setState(() {
      _config = TpmsConfig.fromId(configId);
      _configIdCache = configId;
      _truckId = truckId;
      _trailerId = trailerId;
      _trailer2Id = trailer2Id;
      _truckLbsPerPsi = truckCal;
      _trailerLbsPerPsi = trailerCal;
      _trailer2LbsPerPsi = trailer2Cal;
      _truckTargetPsi = truckTarget;
      _trailerTargetPsi = trailerTarget;
      _trailer2TargetPsi = trailer2Target;
    });
  }

  Future<void> _refreshConfigIfNeeded() async {
    if (_configLoading) return;
    _configLoading = true;
    final prefs = await SharedPreferences.getInstance();
    final configId = prefs.getString(TpmsConfig.prefsKey);
    if (!mounted) {
      _configLoading = false;
      return;
    }
    if (configId != _configIdCache) {
      setState(() {
        _config = TpmsConfig.fromId(configId);
        _configIdCache = configId;
      });
    }
    _configLoading = false;
  }

  String _calibrationKey(String deviceId) => 'tpms_calibration_$deviceId';
  String _targetPsiKey(String deviceId) => 'tpms_target_psi_$deviceId';

  Future<void> _saveSelection({required String slot, required String deviceId}) async {
    final prefs = await SharedPreferences.getInstance();
    final service = context.read<BleService>();
    if (slot == _truckKey) {
      await prefs.setString(_truckKey, deviceId);
      await service.loadCachedDecoded(deviceId);
      final cal = prefs.getDouble(_calibrationKey(deviceId));
      if (!mounted) return;
      setState(() {
        _truckId = deviceId;
        _truckLbsPerPsi = cal;
        _truckTargetPsi = prefs.getDouble(_targetPsiKey(deviceId));
      });
    } else if (slot == _trailerKey) {
      await prefs.setString(_trailerKey, deviceId);
      await service.loadCachedDecoded(deviceId);
      final cal = prefs.getDouble(_calibrationKey(deviceId));
      if (!mounted) return;
      setState(() {
        _trailerId = deviceId;
        _trailerLbsPerPsi = cal;
        _trailerTargetPsi = prefs.getDouble(_targetPsiKey(deviceId));
      });
    } else if (slot == _trailer2Key) {
      await prefs.setString(_trailer2Key, deviceId);
      await service.loadCachedDecoded(deviceId);
      final cal = prefs.getDouble(_calibrationKey(deviceId));
      if (!mounted) return;
      setState(() {
        _trailer2Id = deviceId;
        _trailer2LbsPerPsi = cal;
        _trailer2TargetPsi = prefs.getDouble(_targetPsiKey(deviceId));
      });
    }
  }

  Future<void> _unpairSlot(String slot) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(slot);
    if (!mounted) return;
    setState(() {
      if (slot == _truckKey) {
        _truckId = null;
        _truckLbsPerPsi = null;
        _truckTargetPsi = null;
      } else if (slot == _trailerKey) {
        _trailerId = null;
        _trailerLbsPerPsi = null;
        _trailerTargetPsi = null;
      } else if (slot == _trailer2Key) {
        _trailer2Id = null;
        _trailer2LbsPerPsi = null;
        _trailer2TargetPsi = null;
      }
    });
  }

  Future<void> _swapSlots(String a, String b) async {
    if (_swapInProgress) return;
    _swapInProgress = true;
    final prefs = await SharedPreferences.getInstance();
    final aId = prefs.getString(a);
    final bId = prefs.getString(b);

    if (aId == null && bId == null) {
      _swapInProgress = false;
      return;
    }

    if (bId == null) {
      await prefs.remove(a);
    } else {
      await prefs.setString(a, bId);
    }

    if (aId == null) {
      await prefs.remove(b);
    } else {
      await prefs.setString(b, aId);
    }

    await _loadSelections();
    _swapInProgress = false;
  }

  Future<void> _showSwapSheet(BuildContext context) async {
    final hasTrailer2 = _config.trailerCount > 1;
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (context) {
        return ListView(
          shrinkWrap: true,
          children: [
            const ListTile(
              title: Text('Swap sensor assignments'),
              subtitle: Text('Move a sensor to the correct vehicle position.'),
            ),
            ListTile(
              leading: const Icon(Icons.swap_horiz),
              title: const Text('Truck ↔ Trailer'),
              onTap: () {
                Navigator.of(context).pop();
                _swapSlots(_truckKey, _trailerKey);
              },
            ),
            if (hasTrailer2)
              ListTile(
                leading: const Icon(Icons.swap_horiz),
                title: const Text('Truck ↔ Trailer 2'),
                onTap: () {
                  Navigator.of(context).pop();
                  _swapSlots(_truckKey, _trailer2Key);
                },
              ),
            if (hasTrailer2)
              ListTile(
                leading: const Icon(Icons.swap_horiz),
                title: const Text('Trailer ↔ Trailer 2'),
                onTap: () {
                  Navigator.of(context).pop();
                  _swapSlots(_trailerKey, _trailer2Key);
                },
              ),
          ],
        );
      },
    );
  }

  void _scheduleMonitoringSync() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _enableMonitoring();
    });
  }

  Future<void> _enableMonitoring() async {
    final service = context.read<BleService>();
    service.setTargetMac('');
    if (!_monitoringActive) {
      _monitoringActive = true;
    }
    if (!service.continuousScan) {
      await service.setContinuousScan(true);
    }
  }

  Future<void> _restoreMonitoring() async {
    if (!_monitoringActive) return;
    _monitoringActive = false;
    final service = context.read<BleService>();
    if (_previousTargetMac != null) {
      service.setTargetMac(_previousTargetMac!);
    }
    if (_previousContinuousScan != null) {
      await service.setContinuousScan(_previousContinuousScan!);
    }
  }

  @override
  Widget build(BuildContext context) {
    _scheduleMonitoringSync();
    _refreshConfigIfNeeded();

    return Consumer<BleService>(
      builder: (context, service, _) {
        service.setPriorityIds({
          if (_truckId != null) _truckId!,
          if (_trailerId != null) _trailerId!,
          if (_trailer2Id != null) _trailer2Id!,
        });
        _ensureAutoReconnect(service);
        final truckResult = _truckId == null ? null : service.getResultById(_truckId!);
        final trailerResult = _trailerId == null ? null : service.getResultById(_trailerId!);
        final trailer2Result = _trailer2Id == null ? null : service.getResultById(_trailer2Id!);
        final truckCached = _truckId == null ? null : service.getLastDecoded(_truckId!);
        final trailerCached = _trailerId == null ? null : service.getLastDecoded(_trailerId!);
        final trailer2Cached = _trailer2Id == null ? null : service.getLastDecoded(_trailer2Id!);

        final truckDecoded = _resolveDecoded(truckResult, truckCached);
        final trailerDecoded = _resolveDecoded(trailerResult, trailerCached);
        final trailer2Decoded = _resolveDecoded(trailer2Result, trailer2Cached);
        final truckStale = _isStale(truckDecoded);
        final trailerStale = _isStale(trailerDecoded);
        final trailer2Stale = _isStale(trailer2Decoded);

        _maybeNotifyStatus(_truckId, truckStale ? null : truckDecoded?.pressurePsi, _truckTargetPsi);
        _maybeNotifyStatus(_trailerId, trailerStale ? null : trailerDecoded?.pressurePsi, _trailerTargetPsi);
        _maybeNotifyStatus(_trailer2Id, trailer2Stale ? null : trailer2Decoded?.pressurePsi, _trailer2TargetPsi);

        _ensureCachedLoaded(service, [_truckId, _trailerId, _trailer2Id]);

        return ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
          children: [
            _BrandBanner(),
            const SizedBox(height: 12),
            _MonitorHeader(
              useKg: _useKg,
              configName: _config.name,
              onSwap: () => _showSwapSheet(context),
              onUnitsChanged: (value) => setState(() => _useKg = value),
            ),
            const SizedBox(height: 12),
            _SensorCard(
              title: 'Truck Sensor',
              selectedId: _truckId,
              result: truckResult,
              cachedDecoded: truckCached,
              rssi: truckResult?.rssi,
              isStale: truckStale,
              lbsPerPsi: _truckLbsPerPsi,
              targetPsi: _truckTargetPsi,
              useKg: _useKg,
              onPickSensor: () => _pickSensor(context, service, slot: _truckKey),
              onUnpair: _truckId == null ? null : () => _unpairSlot(_truckKey),
              onOpenDetails: _truckId == null
                  ? null
                  : () async {
                      await Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => DeviceDetailView(
                            deviceId: _truckId!,
                            result: truckResult,
                            deviceName: _resolveDeviceName(truckResult, 'Truck Sensor'),
                          ),
                        ),
                      );
                      await _loadSelections();
                    },
            ),
            const SizedBox(height: 12),
            _SensorCard(
              title: 'Trailer Sensor',
              selectedId: _trailerId,
              result: trailerResult,
              cachedDecoded: trailerCached,
              rssi: trailerResult?.rssi,
              isStale: trailerStale,
              lbsPerPsi: _trailerLbsPerPsi,
              targetPsi: _trailerTargetPsi,
              useKg: _useKg,
              onPickSensor: () => _pickSensor(context, service, slot: _trailerKey),
              onUnpair: _trailerId == null ? null : () => _unpairSlot(_trailerKey),
              onOpenDetails: _trailerId == null
                  ? null
                  : () async {
                      await Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => DeviceDetailView(
                            deviceId: _trailerId!,
                            result: trailerResult,
                            deviceName: _resolveDeviceName(trailerResult, 'Trailer Sensor'),
                          ),
                        ),
                      );
                      await _loadSelections();
                    },
            ),
            if (_config.trailerCount > 1) ...[
              const SizedBox(height: 12),
              _SensorCard(
                title: 'Trailer 2 Sensor',
                selectedId: _trailer2Id,
                result: trailer2Result,
                cachedDecoded: trailer2Cached,
                rssi: trailer2Result?.rssi,
                isStale: trailer2Stale,
                lbsPerPsi: _trailer2LbsPerPsi,
                targetPsi: _trailer2TargetPsi,
                useKg: _useKg,
                onPickSensor: () => _pickSensor(context, service, slot: _trailer2Key),
                onUnpair: _trailer2Id == null ? null : () => _unpairSlot(_trailer2Key),
                onOpenDetails: _trailer2Id == null
                    ? null
                    : () async {
                        await Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => DeviceDetailView(
                              deviceId: _trailer2Id!,
                              result: trailer2Result,
                              deviceName: _resolveDeviceName(trailer2Result, 'Trailer 2 Sensor'),
                            ),
                          ),
                        );
                        await _loadSelections();
                      },
              ),
            ],
            const SizedBox(height: 16),
            if (service.results.isEmpty)
              const Text(
                'No sensors found yet. Switch to the Connect tab to scan and pair sensors.',
                textAlign: TextAlign.center,
              )
            else
              Text(
                'Live sensors detected: ${service.results.length}',
                textAlign: TextAlign.center,
              ),
          ],
        );
      },
    );
  }

  Future<void> _pickSensor(BuildContext context, BleService service, {required String slot}) async {
    if (service.results.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No sensors available. Start scanning first.')),
      );
      return;
    }

    final result = await showModalBottomSheet<ScanResult>(
      context: context,
      showDragHandle: true,
      builder: (context) {
        return ListView.separated(
          padding: const EdgeInsets.symmetric(vertical: 8),
          itemCount: service.results.length + 1,
          separatorBuilder: (_, __) => const Divider(height: 1),
          itemBuilder: (context, index) {
            if (index == 0) {
              return const ListTile(
                title: Text('Select a sensor (closest signal first)'),
                subtitle: Text('Move near the tire you want to pair.'),
              );
            }
            final listIndex = index - 1;
            final item = service.results[listIndex];
            final name = item.device.platformName.isNotEmpty
                ? item.device.platformName
                : (item.advertisementData.advName.isNotEmpty
                    ? item.advertisementData.advName
                    : 'Unknown Sensor');
            return ListTile(
              title: Text(name),
              subtitle: Text(item.device.remoteId.str),
              trailing: Text('${item.rssi} dBm'),
              onTap: () => Navigator.of(context).pop(item),
            );
          },
        );
      },
    );

    if (result == null) return;
    await _saveSelection(slot: slot, deviceId: result.device.remoteId.str);
  }

  void _ensureCachedLoaded(BleService service, List<String?> ids) {
    for (final id in ids) {
      if (id == null) continue;
      if (_cacheLoadedIds.contains(id)) continue;
      _cacheLoadedIds.add(id);
      service.loadCachedDecoded(id);
    }
  }

  void _ensureAutoReconnect(BleService service) {
    if (_autoReconnectDone) return;
    _autoReconnectDone = true;
    service.reconnectToPairedSensors();
  }

  TpmsDecoded? _resolveDecoded(ScanResult? result, TpmsDecoded? cached) {
    if (result == null) return cached;
    final decoded = decodeTpmsFromManufacturerData(result);
    if (decoded == null) return cached;
    return decoded.copyWith(timestamp: DateTime.now());
  }

  bool _isStale(TpmsDecoded? decoded) {
    final timestamp = decoded?.timestamp;
    if (timestamp == null) return true;
    return DateTime.now().difference(timestamp) > _staleAfter;
  }

  String _resolveDeviceName(ScanResult? result, String fallback) {
    if (result != null) {
      if (result.device.platformName.isNotEmpty) return result.device.platformName;
      if (result.advertisementData.advName.isNotEmpty) return result.advertisementData.advName;
    }
    return fallback;
  }

  int? _statusLevel(double? pressurePsi, double? targetPsi) {
    if (pressurePsi == null || targetPsi == null || targetPsi <= 0) return null;
    final percent = (pressurePsi / targetPsi) * 100;
    if (percent < 80) return 0;
    if (percent <= 100) return 1;
    return 2;
  }

  void _maybeNotifyStatus(String? deviceId, double? pressurePsi, double? targetPsi) {
    if (deviceId == null) return;
    final level = _statusLevel(pressurePsi, targetPsi);
    if (level == null) return;
    final previous = _lastStatusById[deviceId];
    if (previous == level) return;
    _lastStatusById[deviceId] = level;

    if (previous == null) return;
    final lastAt = _lastVibeAt[deviceId];
    if (lastAt != null && DateTime.now().difference(lastAt).inSeconds < 2) return;
    _lastVibeAt[deviceId] = DateTime.now();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (level == 1) {
        HapticFeedback.lightImpact();
      } else if (level == 2) {
        HapticFeedback.heavyImpact();
        Future.delayed(const Duration(milliseconds: 180), HapticFeedback.heavyImpact);
      }
    });
  }
}

class _MonitorHeader extends StatelessWidget {
  const _MonitorHeader({
    required this.useKg,
    required this.configName,
    required this.onSwap,
    required this.onUnitsChanged,
  });

  final bool useKg;
  final String configName;
  final VoidCallback onSwap;
  final ValueChanged<bool> onUnitsChanged;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Live Monitor', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            Text(
              'Select the truck and trailer sensors to monitor PSI and weight in real time.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 8),
            Text(
              'Config: $configName',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerLeft,
              child: OutlinedButton.icon(
                onPressed: onSwap,
                icon: const Icon(Icons.swap_horiz),
                label: const Text('Swap sensors'),
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                const Text('Units:'),
                const SizedBox(width: 8),
                ChoiceChip(
                  label: const Text('lbs'),
                  selected: !useKg,
                  onSelected: (value) => onUnitsChanged(!value),
                ),
                const SizedBox(width: 8),
                ChoiceChip(
                  label: const Text('kg'),
                  selected: useKg,
                  onSelected: (value) => onUnitsChanged(value),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _SensorCard extends StatelessWidget {
  const _SensorCard({
    required this.title,
    required this.selectedId,
    required this.result,
    required this.cachedDecoded,
    required this.rssi,
    required this.isStale,
    required this.lbsPerPsi,
    required this.targetPsi,
    required this.useKg,
    required this.onPickSensor,
    required this.onUnpair,
    required this.onOpenDetails,
  });

  final String title;
  final String? selectedId;
  final ScanResult? result;
  final TpmsDecoded? cachedDecoded;
  final int? rssi;
  final bool isStale;
  final double? lbsPerPsi;
  final double? targetPsi;
  final bool useKg;
  final VoidCallback onPickSensor;
  final VoidCallback? onUnpair;
  final VoidCallback? onOpenDetails;

  @override
  Widget build(BuildContext context) {
    final decoded = result == null ? cachedDecoded : (decodeTpmsFromManufacturerData(result!) ?? cachedDecoded);
    final pressurePsi = decoded?.pressurePsi;
    final displayPsi = pressurePsi;
    final weightLbs = (displayPsi != null && lbsPerPsi != null) ? displayPsi * lbsPerPsi! : null;
    final weightKg = weightLbs == null ? null : weightLbs * 0.45359237;
    final weightText = weightLbs == null
        ? 'Weight: -- lbs'
        : 'Weight: ${weightLbs.toStringAsFixed(0)} lbs';
    final weightTextKg = weightKg == null
        ? 'Weight: -- kg'
        : 'Weight: ${weightKg.toStringAsFixed(0)} kg';
    final bigStyle = Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700);
    final updatedText = _formatUpdated(decoded?.timestamp, isStale);
    final percent = targetPsi == null || displayPsi == null || isStale
      ? null
      : (displayPsi / targetPsi!) * 100;
    final statusColor = _statusColor(percent);
    final percentText = percent == null ? null : 'Load: ${percent.toStringAsFixed(0)}%';
    final signalLabel = _signalLabel(rssi);
    final signalIcon = _signalIcon(rssi);
    final signalColor = _signalColor(rssi, Theme.of(context).colorScheme);

    final displayName = result == null
        ? null
        : (result!.device.platformName.isNotEmpty
            ? result!.device.platformName
            : (result!.advertisementData.advName.isNotEmpty
                ? result!.advertisementData.advName
                : 'Unknown Sensor'));

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(title, style: Theme.of(context).textTheme.titleMedium),
                ),
                TextButton.icon(
                  onPressed: onPickSensor,
                  icon: const Icon(Icons.swap_horiz),
                  label: const Text('Pair'),
                ),
                if (onUnpair != null)
                  TextButton.icon(
                    onPressed: onUnpair,
                    icon: const Icon(Icons.link_off),
                    label: const Text('Unpair'),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            if (selectedId == null)
              const Text('No sensor selected.')
            else ...[
              Text(displayName ?? selectedId!),
              const SizedBox(height: 4),
              Text('ID: $selectedId'),
            ],
            const SizedBox(height: 12),
            if (decoded == null)
              const Text('Waiting for live data…')
            else if (isStale) ...[
              Row(
                children: [
                  Icon(Icons.warning_amber_rounded, color: Theme.of(context).colorScheme.error),
                  const SizedBox(width: 6),
                  const Text('Signal lost (showing last reading).'),
                ],
              ),
              Text(
                'Pressure: ${displayPsi?.toStringAsFixed(1) ?? '--'} psi',
                style: bigStyle?.copyWith(color: statusColor),
              ),
              Text(updatedText, style: Theme.of(context).textTheme.bodySmall),
            ] else ...[
              Text(
                'Pressure: ${displayPsi?.toStringAsFixed(1) ?? '--'} psi',
                style: bigStyle?.copyWith(color: statusColor),
              ),
              Text(
                'Temperature: ${decoded.temperatureC?.toStringAsFixed(0) ?? '--'} °C',
              ),
              Text(useKg ? weightTextKg : weightText, style: bigStyle?.copyWith(color: statusColor)),
              if (percentText != null) Text(percentText, style: TextStyle(color: statusColor)),
              const SizedBox(height: 4),
              Text(updatedText, style: Theme.of(context).textTheme.bodySmall),
              if (targetPsi == null)
                Text(
                  'Set target PSI in Details to enable alerts.',
                  style: Theme.of(context)
                      .textTheme
                      .bodySmall
                      ?.copyWith(color: Theme.of(context).colorScheme.error),
                ),
              if (lbsPerPsi == null)
                Text(
                  'Calibration missing. Set weight in the sensor detail screen.',
                  style: Theme.of(context)
                      .textTheme
                      .bodySmall
                      ?.copyWith(color: Theme.of(context).colorScheme.error),
                )
              else
                Text('Calibration: ${lbsPerPsi!.toStringAsFixed(1)} lbs/psi'),
            ],
            if (signalLabel != null) ...[
              const SizedBox(height: 6),
              Row(
                children: [
                  Icon(signalIcon, size: 18, color: signalColor),
                  const SizedBox(width: 6),
                  Text('Signal: $signalLabel', style: Theme.of(context).textTheme.bodySmall),
                ],
              ),
            ],
            if (onOpenDetails != null) ...[
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: onOpenDetails,
                  icon: const Icon(Icons.tune),
                  label: const Text('Details'),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  String _formatUpdated(DateTime? timestamp, bool isStale) {
    if (timestamp == null) return 'Last updated: —';
    final h = timestamp.hour.toString().padLeft(2, '0');
    final m = timestamp.minute.toString().padLeft(2, '0');
    final s = timestamp.second.toString().padLeft(2, '0');
    return isStale ? 'Last updated: $h:$m:$s (stale)' : 'Last updated: $h:$m:$s';
  }

  Color? _statusColor(double? percent) {
    if (percent == null) return null;
    if (percent < 80) return Colors.green;
    if (percent <= 100) return Colors.amber;
    return Colors.red;
  }

  String? _signalLabel(int? rssi) {
    if (rssi == null) return null;
    if (rssi >= -60) return 'Strong';
    if (rssi >= -75) return 'Good';
    if (rssi >= -90) return 'Weak';
    return 'Very weak';
  }

  IconData _signalIcon(int? rssi) {
    if (rssi == null) return Icons.signal_cellular_off;
    if (rssi >= -60) return Icons.signal_cellular_alt;
    if (rssi >= -75) return Icons.signal_cellular_alt_2_bar;
    if (rssi >= -90) return Icons.signal_cellular_alt_1_bar;
    return Icons.signal_cellular_connected_no_internet_0_bar;
  }

  Color _signalColor(int? rssi, ColorScheme scheme) {
    if (rssi == null) return scheme.onSurfaceVariant;
    if (rssi >= -60) return Colors.green;
    if (rssi >= -75) return Colors.amber;
    if (rssi >= -90) return scheme.error;
    return scheme.error;
  }
}

class _BrandBanner extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            colors.primary.withOpacity(0.14),
            colors.primary.withOpacity(0.04),
          ],
        ),
        borderRadius: BorderRadius.circular(16),
      ),
      padding: const EdgeInsets.all(16),
      child: Row(
        children: [
          _BrandLogo(height: 44),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'TPMS Live Monitor',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 4),
                Text(
                  'Sutco Transportation Specialists',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _BrandLogo extends StatelessWidget {
  const _BrandLogo({required this.height});

  final double height;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final logo = Image.asset(
      'Sutco_SGC_green.png',
      height: height,
      fit: BoxFit.contain,
    );
    if (!isDark) return logo;
    return ColorFiltered(
      colorFilter: const ColorFilter.matrix(<double>[
        -1, 0, 0, 0, 255,
        0, -1, 0, 0, 255,
        0, 0, -1, 0, 255,
        0, 0, 0, 1, 0,
      ]),
      child: logo,
    );
  }
}
