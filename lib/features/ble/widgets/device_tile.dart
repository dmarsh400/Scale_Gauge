import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';

class DeviceTile extends StatelessWidget {
  const DeviceTile({super.key, required this.result, this.onTap});

  final ScanResult result;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final device = result.device;
    final name = device.platformName.isNotEmpty ? device.platformName : 'Unknown Sensor';

    return ListTile(
      leading: const Icon(Icons.tire_repair),
      title: Text(name),
      subtitle: Text(device.remoteId.str),
      trailing: Text('${result.rssi} dBm'),
      onTap: onTap,
    );
  }
}
