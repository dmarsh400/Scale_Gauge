import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:provider/provider.dart';

import 'ble_service.dart';
import 'device_detail_view.dart';
import 'widgets/device_tile.dart';
import '../settings/settings_view.dart';

class ScanView extends StatefulWidget {
  const ScanView({super.key, this.embedded = false});

  final bool embedded;

  @override
  State<ScanView> createState() => _ScanViewState();
}

class _ScanViewState extends State<ScanView> {
  late final TextEditingController _macController;

  @override
  void initState() {
    super.initState();
    _macController = TextEditingController();
  }

  @override
  void dispose() {
    _macController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<BleService>(
      builder: (context, service, _) {
        final adapterState = service.adapterState;
        final isBluetoothOn = adapterState == BluetoothAdapterState.on;
        Future<void> toggleScan() async {
          if (!isBluetoothOn) return;
          if (service.isScanning) {
            await service.stopScan();
          } else {
            await service.startScan();
          }
        }

        if (_macController.text != service.targetMac) {
          _macController.text = service.targetMac;
          _macController.selection = TextSelection.fromPosition(
            TextPosition(offset: _macController.text.length),
          );
        }

        final body = ListView(
          padding: EdgeInsets.only(bottom: widget.embedded ? 96 : 16),
          children: [
            _StatusCard(
              adapterState: adapterState,
              isScanning: service.isScanning,
              error: service.lastError,
              permissionSummary: service.permissionSummary,
              deviceCount: service.results.length,
              targetMac: service.targetMac,
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Column(
                children: [
                  TextField(
                    controller: _macController,
                    textCapitalization: TextCapitalization.characters,
                    decoration: const InputDecoration(
                      labelText: 'Target MAC (optional)',
                      hintText: 'C8:17:F5:B1:27:50',
                    ),
                    onChanged: (value) => service.setTargetMac(value),
                  ),
                  if (service.targetMac.isNotEmpty)
                    Align(
                      alignment: Alignment.centerLeft,
                      child: TextButton(
                        onPressed: () => service.setTargetMac(''),
                        child: const Text('Clear target filter'),
                      ),
                    ),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Continuous scan'),
                    value: service.continuousScan,
                    onChanged: isBluetoothOn
                        ? (value) async => service.setContinuousScan(value)
                        : null,
                  ),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Filter to TPMS sensors'),
                      subtitle: const Text('Hide non-TPMS BLE devices'),
                      value: service.tpmsOnlyFilter,
                      onChanged: (value) => service.setTpmsOnlyFilter(value),
                    ),
                  ExpansionTile(
                    tilePadding: EdgeInsets.zero,
                    title: Text('Scan log (${service.scanLog.length})'),
                    subtitle: const Text('Raw advertisements with timestamps'),
                    trailing: TextButton(
                      onPressed: service.scanLog.isEmpty ? null : service.clearScanLog,
                      child: const Text('Clear'),
                    ),
                    children: [
                      SizedBox(
                        height: 180,
                        child: service.scanLog.isEmpty
                            ? const Center(child: Text('No scan events yet.'))
                            : ListView.separated(
                                itemCount: service.scanLog.length,
                                separatorBuilder: (_, __) => const Divider(height: 1),
                                itemBuilder: (context, index) {
                                  final entry = service.scanLog[service.scanLog.length - 1 - index];
                                  final time =
                                      '${entry.timestamp.hour.toString().padLeft(2, '0')}:'
                                      '${entry.timestamp.minute.toString().padLeft(2, '0')}:'
                                      '${entry.timestamp.second.toString().padLeft(2, '0')}';
                                  final services = entry.serviceUuids.isEmpty
                                      ? '—'
                                      : entry.serviceUuids.join(', ');
                                  return ListTile(
                                    dense: true,
                                    title: Text('${entry.name} (${entry.rssi} dBm)'),
                                    subtitle: Text(
                                      '[$time] ${entry.deviceId}\nServices: $services\nMfg: ${entry.manufacturerData}',
                                    ),
                                    isThreeLine: true,
                                  );
                                },
                              ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            if (!isBluetoothOn)
              const Padding(
                padding: EdgeInsets.all(24),
                child: Text(
                  'Bluetooth is off. Turn it on to scan for TPMS sensors.',
                  textAlign: TextAlign.center,
                ),
              )
            else if (service.results.isEmpty)
              Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  children: [
                    const Text(
                      'No sensors found yet.',
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 12),
                    ElevatedButton.icon(
                      onPressed: toggleScan,
                      icon: Icon(
                        service.isScanning ? Icons.stop_circle : Icons.search,
                      ),
                      label: Text(
                        service.isScanning ? 'Stop scan' : 'Start scan',
                      ),
                    ),
                  ],
                ),
              )
            else
              ListView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: service.results.length,
                itemBuilder: (context, index) {
                  final result = service.results[index];
                  return DeviceTile(
                    result: result,
                    onTap: () {
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => DeviceDetailView(
                            deviceId: result.device.remoteId.str,
                            result: result,
                          ),
                        ),
                      );
                    },
                  );
                },
              ),
          ],
        );

        if (widget.embedded) {
          return body;
        }

        return Scaffold(
          appBar: AppBar(
            title: const Text('TPMS Sensors'),
            actions: [
              IconButton(
                tooltip: service.isScanning ? 'Stop scan' : 'Start scan',
                icon: Icon(service.isScanning ? Icons.stop_circle : Icons.search),
                onPressed: isBluetoothOn ? toggleScan : null,
              ),
              IconButton(
                tooltip: 'Settings',
                icon: const Icon(Icons.settings),
                onPressed: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const SettingsView()),
                  );
                },
              ),
            ],
          ),
          body: body,
          floatingActionButton: FloatingActionButton.extended(
            onPressed: isBluetoothOn ? toggleScan : null,
            icon: Icon(service.isScanning ? Icons.stop_circle : Icons.search),
            label: Text(service.isScanning ? 'Stop scan' : 'Scan'),
          ),
        );
      },
    );
  }
}

class _StatusCard extends StatelessWidget {
  const _StatusCard({
    required this.adapterState,
    required this.isScanning,
    this.error,
    this.permissionSummary,
    required this.deviceCount,
    required this.targetMac,
  });

  final BluetoothAdapterState adapterState;
  final bool isScanning;
  final String? error;
  final String? permissionSummary;
  final int deviceCount;
  final String targetMac;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.all(16),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Bluetooth: ${adapterState.name}',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Text(
              isScanning ? 'Scanning for sensors…' : 'Idle',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: 4),
            Text(
              'Devices found: $deviceCount',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            if (targetMac.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(
                'Target filter: $targetMac',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
            if (permissionSummary != null) ...[
              const SizedBox(height: 4),
              Text(
                'Permissions: $permissionSummary',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
            if (error != null) ...[
              const SizedBox(height: 8),
              Text(
                error!,
                style: Theme.of(context)
                    .textTheme
                    .bodySmall
                    ?.copyWith(color: Theme.of(context).colorScheme.error),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
