import 'telemetry_history_store.dart';

/// Web fallback: history lives only for the lifetime of the tab.
TelemetryHistoryStore createTelemetryHistoryStore() =>
    InMemoryTelemetryHistoryStore();
