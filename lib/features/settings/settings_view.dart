import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app_settings.dart';
import 'tpms_config.dart';

class SettingsView extends StatefulWidget {
  const SettingsView({super.key, this.embedded = false, this.onClose});

  final bool embedded;
  final VoidCallback? onClose;

  @override
  State<SettingsView> createState() => _SettingsViewState();
}

class _SettingsViewState extends State<SettingsView> {
  TpmsConfig _config = TpmsConfig.quad;

  @override
  void initState() {
    super.initState();
    _loadConfig();
  }

  Future<void> _loadConfig() async {
    final prefs = await SharedPreferences.getInstance();
    final id = prefs.getString(TpmsConfig.prefsKey);
    if (!mounted) return;
    setState(() {
      _config = TpmsConfig.fromId(id);
    });
  }

  Future<void> _saveConfig(TpmsConfig config) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(TpmsConfig.prefsKey, config.id);
    if (!mounted) return;
    setState(() {
      _config = config;
    });
  }

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<AppSettings>();
    final content = ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text('Settings', style: Theme.of(context).textTheme.headlineSmall),
        const SizedBox(height: 12),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Appearance', style: Theme.of(context).textTheme.titleMedium),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Dark mode'),
                  subtitle: const Text('Dark green theme with white text'),
                  value: settings.darkMode,
                  onChanged: settings.setDarkMode,
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Monitoring configuration', style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 8),
                ...TpmsConfig.all.map(
                  (config) => RadioListTile<TpmsConfig>(
                    value: config,
                    groupValue: _config,
                    onChanged: (value) {
                      if (value == null) return;
                      _saveConfig(value);
                    },
                    title: Text(config.name),
                    subtitle: Text(
                      '${config.truckCount} truck · ${config.trailerCount} trailer'
                      '${config.trailerCount == 1 ? '' : 's'}',
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Load alerts', style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 4),
                const Text('Set the PSI for perfect axle weight in each sensor detail screen.'),
                const SizedBox(height: 8),
                const Text('Color thresholds:'),
                const SizedBox(height: 4),
                const Text('• Green: 0%–80% of target PSI'),
                const Text('• Yellow: 80%–100% of target PSI'),
                const Text('• Red: over 100% of target PSI'),
              ],
            ),
          ),
        ),
      ],
    );

    if (widget.embedded) {
      return content;
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: content,
    );
  }
}
