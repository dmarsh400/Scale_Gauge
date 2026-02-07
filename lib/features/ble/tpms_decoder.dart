import 'package:flutter_blue_plus/flutter_blue_plus.dart';

class TpmsDecoded {
  const TpmsDecoded({
    required this.pressurePsi,
    required this.temperatureC,
    required this.statusByte,
    required this.rawPayload,
    this.timestamp,
  });

  final double? pressurePsi;
  final double? temperatureC;
  final int statusByte;
  final String rawPayload;
  final DateTime? timestamp;

  Map<String, dynamic> toJson() {
    return {
      'pressurePsi': pressurePsi,
      'temperatureC': temperatureC,
      'statusByte': statusByte,
      'rawPayload': rawPayload,
      'timestamp': timestamp?.millisecondsSinceEpoch,
    };
  }

  static TpmsDecoded? fromJson(Map<String, dynamic>? json) {
    if (json == null) return null;
    final pressure = json['pressurePsi'];
    final temperature = json['temperatureC'];
    final status = json['statusByte'];
    final raw = json['rawPayload'];
    if (status is! int || raw is! String) return null;
    return TpmsDecoded(
      pressurePsi: pressure is num ? pressure.toDouble() : null,
      temperatureC: temperature is num ? temperature.toDouble() : null,
      statusByte: status,
      rawPayload: raw,
      timestamp: json['timestamp'] is int
          ? DateTime.fromMillisecondsSinceEpoch(json['timestamp'] as int)
          : null,
    );
  }

  TpmsDecoded copyWith({
    double? pressurePsi,
    double? temperatureC,
    int? statusByte,
    String? rawPayload,
    DateTime? timestamp,
  }) {
    return TpmsDecoded(
      pressurePsi: pressurePsi ?? this.pressurePsi,
      temperatureC: temperatureC ?? this.temperatureC,
      statusByte: statusByte ?? this.statusByte,
      rawPayload: rawPayload ?? this.rawPayload,
      timestamp: timestamp ?? this.timestamp,
    );
  }
}

TpmsDecoded? decodeTpmsFromManufacturerData(ScanResult result) {
  final adv = result.advertisementData;
  if (adv.manufacturerData.isEmpty) return null;

  // TPMS payloads observed: 12 bytes with last 6 bytes matching MAC.
  // Manufacturer ID may vary (e.g., 0x0200, 0x0400, 0x0800), so we decode any entry.
  for (final entry in adv.manufacturerData.entries) {
    final data = entry.value;
    if (data.length < 6) {
      continue;
    }

    final b0 = data[0];
    final b1 = data[1];
    final rawPressure = (data[2] << 8) | data[3];

    // Empirical fit based on provided samples:
    // psi ≈ (rawPressure - 0x0065) / 6.3
    double? pressurePsi;
    if (rawPressure >= 0x0065) {
      pressurePsi = (rawPressure - 0x0065) / 6.3;
    }

    // Temperature appears to track byte b1 (in °C) from samples.
    final temperatureC = b1.toDouble();

    return TpmsDecoded(
      pressurePsi: pressurePsi,
      temperatureC: temperatureC,
      statusByte: b0,
      rawPayload: formatBytes(data),
    );
  }

  return null;
}

String formatBytes(List<int> bytes) {
  return bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join(' ');
}