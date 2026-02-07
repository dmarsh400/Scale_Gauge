class TpmsConfig {
  const TpmsConfig({
    required this.id,
    required this.name,
    required this.truckCount,
    required this.trailerCount,
  });

  final String id;
  final String name;
  final int truckCount;
  final int trailerCount;

  static const String prefsKey = 'tpms_monitor_config';

  static const quad = TpmsConfig(
    id: 'quad',
    name: 'Quad',
    truckCount: 1,
    trailerCount: 1,
  );

  static const bTrain = TpmsConfig(
    id: 'b-train',
    name: 'B-Train',
    truckCount: 1,
    trailerCount: 2,
  );

  static const all = [quad, bTrain];

  static TpmsConfig fromId(String? id) {
    return all.firstWhere((config) => config.id == id, orElse: () => quad);
  }
}
