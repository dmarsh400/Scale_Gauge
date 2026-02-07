import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'tpms_decoder.dart';

class BleService extends ChangeNotifier {
  static const String pairedTruckKey = 'tpms_monitor_truck_id';
  static const String pairedTrailerKey = 'tpms_monitor_trailer_id';
  static const String pairedTrailer2Key = 'tpms_monitor_trailer2_id';

  final Map<String, ScanResult> _resultsById = {};
  final Map<String, TpmsDecoded> _lastDecodedById = {};
  final Map<String, DateTime> _lastPersistedAt = {};
  final Map<String, DateTime> _lastLoggedAt = {};
  final Set<String> _connectingIds = {};
  final Set<String> _priorityIds = {};
  final Future<SharedPreferences> _prefsFuture = SharedPreferences.getInstance();
  final List<BleScanLogEntry> _scanLog = [];
  bool _autoScanTriggered = false;
  bool _isScanning = false;
  DateTime? _lastScanStartAt;
  DateTime? _lastScanStopAt;
  BluetoothAdapterState _adapterState = BluetoothAdapterState.unknown;
  String? _lastError;
  String? _permissionSummary;
  String _targetMac = '';
  bool _continuousScan = false;
  bool _tpmsOnlyFilter = true;
  Timer? _restartTimer;
  Timer? _scanRetryTimer;
  static const Duration _scanCooldown = Duration(seconds: 15);
  static const Duration _scanTimeout = Duration(seconds: 120);

  StreamSubscription<List<ScanResult>>? _scanResultsSub;
  StreamSubscription<bool>? _scanStateSub;
  StreamSubscription<BluetoothAdapterState>? _adapterSub;

  BleService() {
    _adapterSub = FlutterBluePlus.adapterState.listen((state) {
      _adapterState = state;
      if (state == BluetoothAdapterState.on) {
        _maybeAutoScanOnLaunch();
      }
      notifyListeners();
    });
    _scanStateSub = FlutterBluePlus.isScanning.listen((scanning) {
      _isScanning = scanning;
      if (!scanning && _continuousScan) {
        _lastScanStopAt = DateTime.now();
        _scheduleScanRestart();
      }
      notifyListeners();
    });
    Future.microtask(_maybeAutoScanOnLaunch);
  }

  List<ScanResult> get results {
    final list = _resultsById.values.toList();
    list.sort((a, b) => b.rssi.compareTo(a.rssi));
    return List.unmodifiable(list);
  }
  List<BleScanLogEntry> get scanLog => List.unmodifiable(_scanLog);
  bool get isScanning => _isScanning;
  BluetoothAdapterState get adapterState => _adapterState;
  String? get lastError => _lastError;
  String? get permissionSummary => _permissionSummary;
  String get targetMac => _targetMac;
  bool get continuousScan => _continuousScan;
  bool get tpmsOnlyFilter => _tpmsOnlyFilter;
  TpmsDecoded? getLastDecoded(String deviceId) => _lastDecodedById[deviceId];

  void setPriorityIds(Set<String> ids) {
    _priorityIds
      ..clear()
      ..addAll(ids.map((e) => e.toUpperCase()));
  }

  Future<void> loadCachedDecoded(String deviceId) async {
    final prefs = await _prefsFuture;
    final jsonString = prefs.getString(_lastReadingKey(deviceId));
    if (jsonString == null) return;
    final jsonMap = jsonDecode(jsonString);
    if (jsonMap is! Map<String, dynamic>) return;
    final decoded = TpmsDecoded.fromJson(jsonMap);
    if (decoded == null) return;
    _lastDecodedById[deviceId] = decoded;
    notifyListeners();
  }

  Future<void> reconnectToPairedSensors() async {
    if (_adapterState != BluetoothAdapterState.on) return;
    final permissionOk = await _ensurePermissions();
    if (!permissionOk) return;

    final prefs = await _prefsFuture;
    final ids = <String?>[
      prefs.getString(pairedTruckKey),
      prefs.getString(pairedTrailerKey),
      prefs.getString(pairedTrailer2Key),
    ];

    for (final id in ids) {
      if (id == null || id.isEmpty) continue;
      await connectById(id);
    }
  }

  Future<void> _maybeAutoScanOnLaunch() async {
    if (_autoScanTriggered) return;
    if (_adapterState != BluetoothAdapterState.on) return;
    final prefs = await _prefsFuture;
    final ids = <String?>[
      prefs.getString(pairedTruckKey),
      prefs.getString(pairedTrailerKey),
      prefs.getString(pairedTrailer2Key),
    ];
    final hasPaired = ids.any((id) => id != null && id.isNotEmpty);
    if (!hasPaired) return;
    _autoScanTriggered = true;
    await setContinuousScan(true);
  }

  Future<void> connectById(String deviceId) async {
    if (_connectingIds.contains(deviceId)) return;
    _connectingIds.add(deviceId);
    try {
      final device = BluetoothDevice.fromId(deviceId);
      await device.connect(timeout: const Duration(seconds: 10), autoConnect: true);
    } catch (error) {
      _lastError = 'Auto-connect failed: $error';
      notifyListeners();
    } finally {
      _connectingIds.remove(deviceId);
    }
  }
  ScanResult? getResultById(String deviceId) => _resultsById[deviceId];

  void setTargetMac(String value) {
    final next = value.trim().toUpperCase();
    if (next != _targetMac) {
      _targetMac = next;
      _resultsById.clear();
    }
    notifyListeners();
  }

  Future<void> setContinuousScan(bool value) async {
    _continuousScan = value;
    notifyListeners();
    if (value) {
      await startScan();
    } else {
      _restartTimer?.cancel();
      _scanRetryTimer?.cancel();
      await stopScan();
    }
  }

  void setTpmsOnlyFilter(bool value) {
    if (value == _tpmsOnlyFilter) return;
    _tpmsOnlyFilter = value;
    notifyListeners();
  }

  Future<void> startScan() async {
    _lastError = null;
    notifyListeners();
    if (_isScanning) return;
    final now = DateTime.now();
    final lastStart = _lastScanStartAt;
    if (lastStart != null && now.difference(lastStart) < _scanCooldown) {
      _scheduleScanRestart();
      return;
    }
    if (_adapterState != BluetoothAdapterState.on) {
      _lastError = 'Bluetooth is off.';
      notifyListeners();
      return;
    }
    final permissionOk = await _ensurePermissions();
    if (!permissionOk) {
      _lastError = 'Bluetooth/Location permissions are required to scan.';
      notifyListeners();
      return;
    }
    await _scanResultsSub?.cancel();
    _lastScanStartAt = DateTime.now();
    _scanResultsSub = FlutterBluePlus.scanResults.listen((results) {
      for (final result in results) {
        _scanLog.add(BleScanLogEntry.fromResult(result));
        final decoded = decodeTpmsFromManufacturerData(result);
        if (decoded != null) {
          final deviceId = result.device.remoteId.str;
          final now = DateTime.now();
          final stamped = decoded.copyWith(timestamp: now);
          _lastDecodedById[deviceId] = stamped;
          _persistLastDecoded(deviceId, stamped);
          _logDecoded(deviceId, stamped, result.rssi);
        }
        final id = result.device.remoteId.str;
        final isPriority = _priorityIds.contains(id.toUpperCase());
        if (isPriority || !_tpmsOnlyFilter || decoded != null) {
          if (_targetMac.isEmpty || _matchesTarget(result) || isPriority) {
            _resultsById[id] = result;
          }
        }
      }
      _trimScanLog();
      notifyListeners();
    });
    await FlutterBluePlus.startScan(timeout: _scanTimeout);
  }

  Future<void> stopScan() async {
    _restartTimer?.cancel();
    _scanRetryTimer?.cancel();
    await FlutterBluePlus.stopScan();
  }

  void _scheduleScanRestart() {
    if (_scanRetryTimer?.isActive ?? false) return;
    final now = DateTime.now();
    final lastStop = _lastScanStopAt;
    final elapsed = lastStop == null ? _scanCooldown : now.difference(lastStop);
    final wait = elapsed >= _scanCooldown ? Duration.zero : _scanCooldown - elapsed;
    _scanRetryTimer = Timer(wait, () {
      _scanRetryTimer = null;
      if (_continuousScan) {
        startScan();
      }
    });
  }

  void clearScanLog() {
    _scanLog.clear();
    notifyListeners();
  }

  bool _matchesTarget(ScanResult result) {
    final id = result.device.remoteId.str.toUpperCase();
    return id == _targetMac;
  }


  void _trimScanLog() {
    final cutoff = DateTime.now().subtract(const Duration(seconds: 30));
    _scanLog.removeWhere((entry) => entry.timestamp.isBefore(cutoff));
    const maxEntries = 400;
    if (_scanLog.length > maxEntries) {
      _scanLog.removeRange(0, _scanLog.length - maxEntries);
    }
  }

  String _lastReadingKey(String deviceId) => 'tpms_last_$deviceId';

  Future<void> _persistLastDecoded(String deviceId, TpmsDecoded decoded) async {
    final now = DateTime.now();
    final last = _lastPersistedAt[deviceId];
    if (last != null && now.difference(last).inSeconds < 5) {
      return;
    }
    _lastPersistedAt[deviceId] = now;
    final prefs = await _prefsFuture;
    final payload = decoded
        .copyWith(timestamp: now)
        .toJson();
    await prefs.setString(_lastReadingKey(deviceId), jsonEncode(payload));
  }

  void _logDecoded(String deviceId, TpmsDecoded decoded, int rssi) {
    final now = DateTime.now();
    final last = _lastLoggedAt[deviceId];
    if (last != null && now.difference(last).inSeconds < 2) {
      return;
    }
    _lastLoggedAt[deviceId] = now;
    final psi = decoded.pressurePsi?.toStringAsFixed(1) ?? '--';
    final temp = decoded.temperatureC?.toStringAsFixed(0) ?? '--';
    debugPrint('TPMS $deviceId psi=$psi temp=$temp rssi=$rssi');
  }

  Future<bool> _ensurePermissions() async {
    if (kIsWeb) return true;
    final permissions = <Permission>[];

    if (Platform.isAndroid) {
      permissions.addAll([
        Permission.bluetoothScan,
        Permission.bluetoothConnect,
        Permission.locationWhenInUse,
      ]);
    } else if (Platform.isIOS) {
      permissions.addAll([
        Permission.bluetooth,
        Permission.locationWhenInUse,
      ]);
    }

    if (permissions.isEmpty) return true;
    final results = await permissions.request();
    _permissionSummary = results.entries
      .map((e) => '${e.key}: ${e.value.name}')
      .join(', ');
    final granted = results.values.every((status) => status.isGranted);
    if (!granted) return false;

    if (Platform.isAndroid) {
      final serviceStatus = await Permission.location.serviceStatus;
      if (!serviceStatus.isEnabled) {
        _lastError = 'Location services are off. Enable Location + Bluetooth scanning.';
        return false;
      }
    }

    return true;
  }

  Future<void> connect(ScanResult result) async {
    try {
      await result.device.connect();
    } catch (error) {
      _lastError = 'Connect failed: $error';
      notifyListeners();
    }
  }

  Future<void> disconnect(ScanResult result) async {
    await result.device.disconnect();
  }

  @override
  void dispose() {
    _scanResultsSub?.cancel();
    _scanStateSub?.cancel();
    _adapterSub?.cancel();
    _restartTimer?.cancel();
    _scanRetryTimer?.cancel();
    super.dispose();
  }
}

class BleScanLogEntry {
  BleScanLogEntry({
    required this.timestamp,
    required this.deviceId,
    required this.name,
    required this.rssi,
    required this.serviceUuids,
    required this.manufacturerData,
  });

  final DateTime timestamp;
  final String deviceId;
  final String name;
  final int rssi;
  final List<String> serviceUuids;
  final String manufacturerData;

  factory BleScanLogEntry.fromResult(ScanResult result) {
    final adv = result.advertisementData;
    final manufacturerData = adv.manufacturerData.isEmpty
        ? '—'
        : adv.manufacturerData.entries
            .map((e) => '${e.key}: ${_formatBytes(e.value)}')
            .join('; ');

    return BleScanLogEntry(
      timestamp: DateTime.now(),
      deviceId: result.device.remoteId.str,
      name: adv.advName.isNotEmpty
          ? adv.advName
          : (result.device.platformName.isNotEmpty ? result.device.platformName : 'Unknown'),
      rssi: result.rssi,
      serviceUuids: adv.serviceUuids.map((e) => e.str).toList(),
      manufacturerData: manufacturerData,
    );
  }
}

String _formatBytes(List<int> bytes) {
  return bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join(' ');
}
