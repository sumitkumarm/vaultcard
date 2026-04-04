abstract interface class TelemetryService {
  Future<void> track(String event, [Map<String, Object?> properties = const {}]);
}

class NoOpTelemetryService implements TelemetryService {
  const NoOpTelemetryService();

  @override
  Future<void> track(
    String event, [
    Map<String, Object?> properties = const {},
  ]) async {}
}
