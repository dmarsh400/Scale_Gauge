import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:provider/provider.dart';

import 'features/ble/ble_service.dart';
import 'features/ble/monitor_view.dart';
import 'features/ble/scan_view.dart';
import 'features/settings/settings_view.dart';

class HomeView extends StatefulWidget {
  const HomeView({super.key});

  @override
  State<HomeView> createState() => _HomeViewState();
}

class _HomeViewState extends State<HomeView> {
  int _index = 0;
  final GlobalKey<MonitorViewState> _monitorKey = GlobalKey<MonitorViewState>();

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

        final title = _index == 0
            ? 'Live Monitor'
            : (_index == 1 ? 'Connect Sensors' : 'Settings');
        final actions = <Widget>[
          if (_index == 1)
            IconButton(
              tooltip: service.isScanning ? 'Stop scan' : 'Start scan',
              icon: Icon(service.isScanning ? Icons.stop_circle : Icons.search),
              onPressed: isBluetoothOn ? toggleScan : null,
            ),
        ];

        return Scaffold(
          appBar: AppBar(
            leadingWidth: 72,
            leading: Padding(
              padding: const EdgeInsets.only(left: 12),
              child: _BrandedLogo(),
            ),
            title: Text(title),
            actions: actions,
          ),
          body: IndexedStack(
            index: _index,
            children: [
              MonitorView(key: _monitorKey),
              const ScanView(embedded: true),
              SettingsView(
                embedded: true,
                onClose: () => _monitorKey.currentState?.reloadConfig(),
              ),
            ],
          ),
          floatingActionButton: _index == 1
              ? FloatingActionButton.extended(
                  onPressed: isBluetoothOn ? toggleScan : null,
                  icon: Icon(service.isScanning ? Icons.stop_circle : Icons.search),
                  label: Text(service.isScanning ? 'Stop scan' : 'Scan'),
                )
              : null,
          bottomNavigationBar: NavigationBar(
            selectedIndex: _index,
            onDestinationSelected: (index) => setState(() => _index = index),
            destinations: const [
              NavigationDestination(
                icon: Icon(Icons.speed),
                label: 'Monitor',
              ),
              NavigationDestination(
                icon: Icon(Icons.bluetooth_searching),
                label: 'Connect',
              ),
              NavigationDestination(
                icon: Icon(Icons.settings),
                label: 'Settings',
              ),
            ],
          ),
        );
      },
    );
  }
}

class _BrandedLogo extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final logo = Image.asset('Sutco_SGC_green.png', fit: BoxFit.contain);
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
